import AVFoundation
import Foundation
import Speech
import TableTalkCore

/// One bounded speaking turn. Audio is passed in memory to Apple's on-device recognizer;
/// this service never opens a file, creates a network request, or logs a transcript.
@MainActor
final class SpeechCapture {
    enum CaptureError: LocalizedError {
        case permissions, unsupported, inputUnavailable, tooShort, tooQuiet
        case interrupted, timedOut, recognitionFailed, emptyTranscript

        var errorDescription: String? {
            switch self {
            case .permissions:
                return "Allow microphone and speech access in Settings. / Permite el micrófono y reconocimiento de voz en Ajustes."
            case .unsupported:
                return "On-device speech is unavailable for this language. / La voz sin conexión no está disponible para este idioma."
            case .inputUnavailable:
                return "Microphone unavailable. Try again. / Micrófono no disponible. Inténtalo de nuevo."
            case .tooShort:
                return "Speak for at least half a second. / Habla durante al menos medio segundo."
            case .tooQuiet:
                return "No clear speech heard. Please try again. / No se oyó la voz. Inténtalo de nuevo."
            case .interrupted:
                return "Audio interrupted. Please repeat your turn. / Audio interrumpido. Repite tu turno."
            case .timedOut:
                return "Speech recognition timed out. Please try again. / El reconocimiento tardó demasiado. Inténtalo de nuevo."
            case .recognitionFailed:
                return "On-device speech failed. Check setup and try again. / Falló la voz sin conexión. Revisa la preparación e inténtalo de nuevo."
            case .emptyTranscript:
                return "No words recognized. Please try again. / No se reconocieron palabras. Inténtalo de nuevo."
            }
        }
    }

    /// Capability only: does not request permission, activate the microphone, or download assets.
    static func supports(_ language: SourceLanguage) -> Bool {
        SFSpeechRecognizer(locale: locale(for: language))?.supportsOnDeviceRecognition == true
    }

    static var permissionsGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted &&
            SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static func requestPermissions() async -> Bool {
        let microphone = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard microphone else { return false }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        return speech
    }

    private static func locale(for language: SourceLanguage) -> Locale {
        Locale(identifier: language == .english ? "en-US" : "es-ES")
    }

    private var generation = UUID()
    private var activeID: UUID?
    private let resources = CaptureResources()
    private var recognizer: SFSpeechRecognizer?
    private var capturing = false
    private var durationTask: Task<Void, Never>?
    private var finalResultTask: Task<Void, Never>?
    private var finishedCallback: ((Result<String, Error>) -> Void)?
    private var stoppedCallback: (() -> Void)?

    func start(
        language: SourceLanguage,
        onFinished: @escaping (Result<String, Error>) -> Void,
        onStopped: @escaping () -> Void
    ) throws {
        cancel()
        guard Self.permissionsGranted else { throw CaptureError.permissions }
        guard let recognizer = SFSpeechRecognizer(locale: Self.locale(for: language)),
              recognizer.supportsOnDeviceRecognition else {
            throw CaptureError.unsupported
        }

        let id = UUID()
        generation = id
        activeID = id
        finishedCallback = onFinished
        stoppedCallback = onStopped
        self.recognizer = recognizer

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            resources.sessionActive = true

            // Created only after the user starts a real turn. Demo mode never creates an engine.
            let engine = AVAudioEngine()
            resources.engine = engine
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0,
                  format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
                throw CaptureError.inputUnavailable
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = false
            request.taskHint = .dictation
            let gate = AudioFrameGate(request: request, format: format)
            resources.gate = gate

            resources.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                // Only a final transcript is eligible for display. Never promote a partial result.
                let finalText = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                let failed = error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.activeID == id else { return }
                    if let finalText {
                        self.acceptFinal(finalText)
                    } else if failed {
                        self.complete(.failure(CaptureError.recognitionFailed))
                    }
                }
            }

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                if gate.append(buffer) {
                    Task { @MainActor [weak self] in
                        guard let self, self.activeID == id else { return }
                        self.finish()
                    }
                }
            }
            resources.tapInstalled = true
            engine.prepare()
            try engine.start()
            capturing = true
            installInterruptionObservers(id: id)
            durationTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(AudioSamples.maxSeconds) * 1_000_000_000) } catch { return }
                guard let self, self.activeID == id else { return }
                self.finish()
            }
        } catch {
            // A throwing start owns no callbacks; the caller presents the failure.
            finishedCallback = nil
            stoppedCallback = nil
            cancel()
            if let captureError = error as? CaptureError { throw captureError }
            throw CaptureError.inputUnavailable
        }
    }

    /// Stops capture now and gives the recognizer at most ten seconds to finalize.
    func finish() {
        guard let id = activeID, capturing else { return }
        let stopped = stopMicrophone()
        if let error = audioQualityError() {
            // Keep the saved stop callback until all internal cleanup has completed.
            stoppedCallback = stopped
            complete(.failure(error))
            return
        }
        finalResultTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            guard let self, self.activeID == id else { return }
            self.complete(.failure(CaptureError.timedOut))
        }
        stopped?()
    }

    /// Invalidates this turn before stopping anything; queued recognition callbacks are ignored.
    func cancel() {
        generation = UUID()
        activeID = nil
        let stopped = stopMicrophone()
        releaseRecognition()
        finishedCallback = nil
        stopped?()
    }

    private func acceptFinal(_ transcript: String) {
        // A recognizer can finish spontaneously while the user is still speaking.
        let stopped = stopMicrophone()
        stoppedCallback = stopped
        if let error = audioQualityError() {
            complete(.failure(error))
            return
        }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        complete(text.isEmpty ? .failure(CaptureError.emptyTranscript) : .success(text))
    }

    private func audioQualityError() -> CaptureError? {
        guard let metrics = resources.gate?.metrics else { return .tooShort }
        let minimumSeconds = Double(AudioSamples.minimumSamples) / Double(AudioSamples.sampleRate)
        if metrics.duration < minimumSeconds { return .tooShort }
        if !metrics.rms.isFinite || metrics.rms < AudioSamples.minimumRMS { return .tooQuiet }
        return nil
    }

    private func complete(_ result: Result<String, Error>) {
        guard let id = activeID else { return }
        activeID = nil
        let stopped = stopMicrophone()
        let finished = finishedCallback
        finishedCallback = nil
        releaseRecognition()
        stopped?()
        // A callback can clear the conversation or start a fresh turn reentrantly.
        guard generation == id else { return }
        finished?(result)
    }

    /// Ends the request under the same lock used by the audio tap, then tears down hardware.
    /// Returns the callback so callers can finish all state changes before calling user code.
    private func stopMicrophone() -> (() -> Void)? {
        capturing = false
        durationTask?.cancel()
        durationTask = nil
        resources.stopMicrophone()
        let stopped = stoppedCallback
        stoppedCallback = nil
        return stopped
    }

    private func releaseRecognition() {
        finalResultTask?.cancel()
        finalResultTask = nil
        resources.recognitionTask?.cancel()
        resources.recognitionTask = nil
        recognizer = nil
        resources.gate = nil
    }

    private func installInterruptionObservers(id: UUID) {
        for name in [AVAudioSession.interruptionNotification,
                     AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification] {
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: AVAudioSession.sharedInstance(), queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.activeID == id, self.capturing else { return }
                    self.complete(.failure(CaptureError.interrupted))
                }
            }
            resources.observers.append(observer)
        }
    }

    deinit {
        durationTask?.cancel()
        finalResultTask?.cancel()
        // Stored-property destruction releases resources without crossing actor isolation.
    }
}

/// Deliberately non-Sendable and owned exclusively by SpeechCapture: all ordinary accesses
/// occur on its main actor. Callbacks never capture this holder. Its final release is exclusive,
/// so deinit can synchronously clean up on any thread without assuming main-actor execution.
/// AVAudioEngine/session cleanup does not require the main thread; the concurrently running
/// audio tap touches only AudioFrameGate, whose append/endAudio operations share a lock.
private final class CaptureResources {
    var engine: AVAudioEngine?
    var recognitionTask: SFSpeechRecognitionTask?
    var gate: AudioFrameGate?
    var tapInstalled = false
    var sessionActive = false
    var observers: [NSObjectProtocol] = []

    func stopMicrophone() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        gate?.endAudio()
        engine?.stop()
        if tapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine = nil
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
    }

    deinit {
        stopMicrophone()
        recognitionTask?.cancel()
    }
}

/// The audio tap is not on the main actor. This lock serializes append/endAudio and protects
/// frame/RMS accounting. No audio is queued to the main actor or retained by this gate.
private final class AudioFrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let sampleRate: Double
    private let channelCount: Int
    private let maxFrames: Int
    private var frames = 0
    private var sumSquares = 0.0
    private var accepting = true
    private var ended = false

    init(request: SFSpeechAudioBufferRecognitionRequest, format: AVAudioFormat) {
        self.request = request
        sampleRate = format.sampleRate
        channelCount = Int(format.channelCount)
        maxFrames = Int(format.sampleRate * Double(AudioSamples.maxSeconds))
    }

    /// Returns true once, when the 12-second frame bound is reached.
    func append(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard accepting, let channels = buffer.floatChannelData else { return false }
        let accepted = min(Int(buffer.frameLength), maxFrames - frames)
        guard accepted > 0 else { return false }

        let boundedBuffer: AVAudioPCMBuffer
        if accepted < Int(buffer.frameLength) {
            // Never append even one frame beyond the cap or mutate an engine-owned buffer.
            guard let tail = AVAudioPCMBuffer(pcmFormat: buffer.format,
                                             frameCapacity: AVAudioFrameCount(accepted)),
                  let tailChannels = tail.floatChannelData else {
                accepting = false
                return true
            }
            tail.frameLength = AVAudioFrameCount(accepted)
            for channel in 0..<channelCount {
                tailChannels[channel].update(from: channels[channel], count: accepted)
            }
            boundedBuffer = tail
        } else {
            boundedBuffer = buffer
        }

        for channel in 0..<channelCount {
            for index in 0..<accepted {
                let value = Double(channels[channel][index])
                sumSquares += value * value
            }
        }
        frames += accepted
        request.append(boundedBuffer)
        if frames >= maxFrames {
            accepting = false
            return true
        }
        return false
    }

    func endAudio() {
        lock.lock()
        defer { lock.unlock() }
        accepting = false
        guard !ended else { return }
        ended = true
        request.endAudio()
    }

    var metrics: (duration: Double, rms: Double) {
        lock.lock()
        defer { lock.unlock() }
        let count = frames * channelCount
        return (Double(frames) / sampleRate, count > 0 ? sqrt(sumSquares / Double(count)) : 0)
    }
}
