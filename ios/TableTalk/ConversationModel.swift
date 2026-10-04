import Foundation
import SwiftUI
import Translation
import TableTalkCore
import UIKit

/// All conversation state is RAM-only and confined to the main actor.
@MainActor
final class ConversationModel: ObservableObject {
    enum Screen { case setup, conversation }
    enum Phase { case idle, recording, processing }
    struct TranslationJob: Identifiable, Sendable {
        enum Purpose: Sendable { case prepare, check, turn }
        let id = UUID()
        let purpose: Purpose
        let source: SourceLanguage
        let text: String
        let generation: UInt64
        var turnID: UInt64? = nil
    }

    @Published private(set) var screen = Screen.setup
    @Published private(set) var ledger = ConversationLedger()
    @Published private(set) var phase = Phase.idle
    @Published private(set) var speaking: SourceLanguage?
    @Published private(set) var isSample = false
    @Published private(set) var ready = false
    @Published private(set) var setupBusy = false
    @Published private(set) var status = "Prepare English and Spanish before using Whipple Chat."
    @Published private(set) var translationJob: TranslationJob?
    @Published private(set) var revealingTurnID: UInt64?
    @Published private(set) var captionReveal: CaptionReveal?
    @Published private(set) var lastRequestedLanguage: SourceLanguage?
    @Published private var viewerNotice: String?
    @Published private var sampleTranslating = false
    private let speech = SpeechCapture()
    private var pending: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var revealEnabled = !UIAccessibility.isReduceMotionEnabled
        && !UIAccessibility.isVoiceOverRunning
    private var foreground = true

    var turns: [ConversationTurn] { ledger.turns }
    var lastTranscript: String { ledger.turns.last?.source ?? "" }
    var canRetry: Bool {
        foreground && screen == .conversation && phase == .idle
            && lastRequestedLanguage != nil && (isSample || ready)
    }
    var canCorrect: Bool {
        foreground && screen == .conversation && phase == .idle && !lastTranscript.isEmpty
    }

    var viewerInstruction: String {
        let instruction: String
        if screen != .conversation {
            instruction = "ESPERE. El operador está preparando Whipple Chat."
        } else if phase == .recording {
            instruction = speaking == .spanish
                ? "AHORA: Hable despacio y con claridad. Una frase breve a la vez."
                : "ESPERE. El operador está hablando."
        } else if phase == .processing {
            instruction = translationJob?.purpose == .turn || sampleTranslating
                ? "ESPERE. Estamos traduciendo."
                : "ESPERE. Estamos transcribiendo."
        } else {
            instruction = viewerNotice ?? "ESPERE. El operador le indicará cuándo hablar."
        }
        return isSample ? "EJEMPLO. Micrófono apagado. " + instruction : instruction
    }

    var operatorInstruction: String {
        if phase == .recording {
            if isSample {
                return speaking == .spanish
                    ? "Sample only · microphone off. Previewing a Spanish speaker turn. Tap Stop to advance the sample."
                    : "Sample only · microphone off. Previewing an English operator turn. Tap Stop to advance the sample."
            }
            let instruction = speaking == .spanish
                ? "Listening to the Spanish speaker. Ask for one short, clear sentence. Tap Stop when finished."
                : "Speak slowly and clearly, one short sentence at a time. Tap Stop when finished."
            return instruction
        }
        if phase == .processing {
            if isSample { return status }
            let translating = translationJob?.purpose == .turn || sampleTranslating
            let instruction = translating ? "Translating locally. Please wait." : "Transcribing locally. Please wait."
            return instruction
        }
        return status
    }

    func requestPermissions() {
        cancelWork()
        setupBusy = true
        let generation = ledger.generation
        pending = Task {
            let granted = await SpeechCapture.requestPermissions()
            guard ledger.isCurrent(generation), !Task.isCancelled else { return }
            setupBusy = false
            status = granted
                ? "Permissions enabled. Prepare languages or check readiness."
                : "Microphone and Speech permissions are required. Enable them in Settings → Whipple Chat. Sample mode remains available."
        }
    }

    func prepareLanguages() { startProbe(download: true) }
    func checkReadiness() { startProbe(download: false) }

    private func startProbe(download: Bool) {
        cancelWork()
        ready = false
        setupBusy = true
        status = download
            ? "Preparing English and Spanish. Follow Apple's download prompt."
            : "Checking local languages."
        translationJob = TranslationJob(purpose: download ? .prepare : .check,
            source: .english, text: "Hello", generation: ledger.generation)
    }

    /// Called only by the nonisolated, Sendable SwiftUI translationTask closure.
    /// The session never crosses into main-actor state or outlives its owning view task.
    nonisolated func perform(_ job: TranslationJob, using session: TranslationSession) async {
        guard await current(job), !Task.isCancelled else { return }
        do {
            if job.purpose == .prepare {
                // Downloading is reachable only from the explicit setup button.
                try await session.prepareTranslation()
                guard await current(job), !Task.isCancelled else { return }
            }
            guard await installed(job.source) else { throw AppError.missingTranslation }
            guard await current(job), !Task.isCancelled else { return }
            // Setup/check uses fixed nonsensitive probes; visit uses just the current turn.
            let response = try await session.translate(job.text)
            guard await current(job), !Task.isCancelled else { return }
            let targetText = response.targetText
            guard !targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppError.emptyTranslation
            }
            if job.purpose != .turn {
                guard await installed(job.source) else { throw AppError.missingTranslation }
                guard await current(job), !Task.isCancelled else { return }
            }
            await complete(job, targetText: targetText)
        } catch {
            // Only the job crosses actors; system errors may contain conversation text.
            await fail(job)
        }
    }

    private func complete(_ job: TranslationJob, targetText: String) {
        guard current(job), !Task.isCancelled else { return }
        if job.purpose == .turn, let turnID = job.turnID {
            if ledger.finish(expected: job.generation, id: turnID,
                translation: targetText, failed: false) {
                beginReveal(generation: job.generation, turnID: turnID)
            }
            translationJob = nil
            phase = .idle
            viewerNotice = nil
            status = "Translation ready. Start your turn or invite the Spanish speaker."
        } else {
            if job.source == .english {
                translationJob = TranslationJob(purpose: job.purpose, source: .spanish,
                    text: "Hola", generation: job.generation)
            } else {
                translationJob = nil
                setupBusy = false
                ready = SpeechCapture.permissionsGranted && SpeechCapture.supports(.english)
                    && SpeechCapture.supports(.spanish)
                status = ready
                    ? "Local language checks passed. Test both directions in airplane mode with Wi-Fi off before a visit."
                    : "Translation is ready. Enable microphone and Speech permissions and English/Spanish Dictation in iPhone Settings, then check again."
            }
        }
    }

    private func fail(_ job: TranslationJob) {
        guard current(job), !Task.isCancelled else { return }
        if let id = job.turnID {
            _ = ledger.finish(expected: job.generation, id: id, translation: nil, failed: true)
            status = "Translation unavailable; transcript kept. Retry the turn, correct the transcript, or return to setup."
            viewerNotice = "ESPERE. No se pudo traducir la frase. Avise al operador."
        } else {
            ready = false
            status = "Local language check failed. Prepare languages on Wi-Fi and try again on a physical iPhone."
            viewerNotice = "ESPERE. La traducción local no está disponible. Avise al operador."
        }
        // Never display/log system errors that could contain conversation text.
        translationJob = nil
        setupBusy = false
        phase = .idle
    }

    private func current(_ job: TranslationJob) -> Bool {
        ledger.isCurrent(job.generation) && translationJob?.id == job.id
    }

    nonisolated private func installed(_ source: SourceLanguage) async -> Bool {
        await LanguageAvailability().status(from: Locale.Language(identifier: source.code),
            to: Locale.Language(identifier: source.other.code)) == .installed
    }

    func startConversation() {
        guard ready, foreground else { return }
        cancelWork()
        let generation = ledger.generation
        setupBusy = true
        pending = Task {
            let english = await installed(.english)
            let spanish = await installed(.spanish)
            guard ledger.isCurrent(generation), !Task.isCancelled else { return }
            setupBusy = false
            pending = nil
            guard foreground else {
                ready = false
                status = "Whipple Chat setup interrupted. Check readiness before restarting."
                return
            }
            guard english, spanish, SpeechCapture.permissionsGranted,
                  SpeechCapture.supports(.english), SpeechCapture.supports(.spanish) else {
                ready = false
                status = "Local languages or permissions changed. Check readiness again."
                return
            }
            isSample = false
            screen = .conversation
            status = "Start your turn or invite the Spanish speaker. Speak slowly and clearly, up to 12 seconds."
        }
    }

    func startSample() {
        cancelWork()
        isSample = true
        screen = .conversation
        addSample(.english)
    }

    func speak(_ language: SourceLanguage) {
        guard foreground, screen == .conversation else { return }
        if isSample {
            guard phase == .idle else { return }
            finishReveal()
            viewerNotice = nil
            lastRequestedLanguage = language
            speaking = language
            phase = .recording
            status = "Whipple Chat sample only · microphone off. Tap Stop to preview the next step."
            return
        }
        if phase == .recording {
            if speaking == language { stopSpeaking() }
            return
        }
        guard phase == .idle, ready else { return }
        lastRequestedLanguage = language
        viewerNotice = nil
        phase = .processing
        status = "Checking local readiness for this turn."
        let generation = ledger.generation
        pending = Task {
            guard await installed(language), !Task.isCancelled,
                  ledger.isCurrent(generation), foreground else {
                if !Task.isCancelled, ledger.isCurrent(generation) {
                    phase = .idle
                    ready = false
                    status = "Local translation is missing. Return to setup."
                    viewerNotice = "ESPERE. La traducción local no está disponible. Avise al operador."
                }
                return
            }
            do {
                finishReveal()
                speaking = language
                try speech.start(language: language, onFinished: { [weak self] result in
                    guard let self, self.foreground, self.ledger.isCurrent(generation) else { return }
                    self.speaking = nil
                    switch result {
                    case .success(let text):
                        guard let id = self.ledger.addSource(expected: generation, language: language, source: text) else {
                            self.phase = .idle
                            return
                        }
                        self.phase = .processing
                        self.status = "Translating locally. Please wait."
                        self.translationJob = TranslationJob(purpose: .turn, source: language,
                            text: text, generation: generation, turnID: id)
                    case .failure(let error):
                        self.captureFailed(error)
                    }
                }, onStopped: { [weak self] in
                    guard let self, self.ledger.isCurrent(generation) else { return }
                    self.phase = .processing
                    self.status = "Transcribing locally. Please wait."
                })
                phase = .recording
                status = "Listening. Speak slowly and clearly. Tap Stop when finished."
            } catch {
                captureFailed(error)
            }
        }
    }

    func stopSpeaking() {
        guard foreground, screen == .conversation, phase == .recording,
              let language = speaking else { return }
        guard isSample else { speech.finish(); return }
        speaking = nil
        phase = .processing
        sampleTranslating = false
        status = "Whipple Chat sample only · microphone off. Simulating transcription."
        let generation = ledger.generation
        var transcriptionDelay: UInt64 = 1_200_000_000
        var translationDelay: UInt64 = 800_000_000
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-slow-stages") {
            transcriptionDelay = 3_000_000_000
            translationDelay = 3_000_000_000
        }
        #endif
        pending = Task {
            do { try await Task.sleep(nanoseconds: transcriptionDelay) }
            catch { return }
            guard !Task.isCancelled, ledger.isCurrent(generation), foreground,
                  screen == .conversation, isSample, phase == .processing else { return }
            let sample = sampleTexts(language)
            guard let id = ledger.addSource(expected: generation, language: language,
                source: sample.source) else {
                phase = .idle
                pending = nil
                return
            }
            sampleTranslating = true
            status = "Whipple Chat sample only · microphone off. Simulating translation."
            do { try await Task.sleep(nanoseconds: translationDelay) }
            catch { return }
            guard !Task.isCancelled, ledger.isCurrent(generation), foreground,
                  screen == .conversation, isSample, phase == .processing else { return }
            if ledger.finish(expected: generation, id: id, translation: sample.translation, failed: false) {
                beginReveal(generation: generation, turnID: id)
            }
            sampleTranslating = false
            phase = .idle
            status = "Whipple Chat sample only · microphone off. Start your turn or invite the Spanish speaker."
            pending = nil
        }
    }

    func retryLastTurn() {
        guard canRetry, let language = lastRequestedLanguage else { return }
        speak(language)
    }

    func correctLastTranscript(_ text: String) {
        guard canCorrect, let last = ledger.turns.last,
              let generation = ledger.reviseLastSource(expected: ledger.generation, source: text) else { return }
        // Revision invalidates old callbacks before cancellation can trigger them.
        cancelCurrentWork()
        viewerNotice = nil
        lastRequestedLanguage = last.sourceLanguage
        guard let revised = ledger.turns.last else { return }
        if isSample {
            let preview = revised.sourceLanguage == .english
                ? "Ejemplo de traducción. Este texto no se ha traducido; el micrófono está apagado."
                : "Translation preview only. This edited text has not been translated; microphone is off."
            if ledger.finish(expected: generation, id: revised.id, translation: preview, failed: false) {
                beginReveal(generation: generation, turnID: revised.id)
            }
            status = "Whipple Chat sample only · microphone off. Corrected text saved for this sample; translation is a fixed preview."
        } else {
            phase = .processing
            status = "Translating your corrected transcript locally. Please wait."
            translationJob = TranslationJob(purpose: .turn, source: revised.sourceLanguage,
                text: revised.source, generation: generation, turnID: revised.id)
        }
    }

    private func captureFailed(_ error: Error) {
        phase = .idle
        speaking = nil
        if let captureError = error as? SpeechCapture.CaptureError {
            status = captureError.localizedDescription.components(separatedBy: " / ").first
                ?? "Local speech could not be captured. Retry the turn."
            switch captureError {
            case .permissions, .unsupported:
                ready = false
                viewerNotice = "ESPERE. La voz local no está disponible. Avise al operador."
            case .inputUnavailable:
                viewerNotice = "ESPERE. El micrófono no está disponible. Avise al operador."
            case .tooShort, .tooQuiet, .interrupted, .timedOut, .recognitionFailed, .emptyTranscript:
                viewerNotice = "ESPERE. No se entendió la frase. El operador le indicará cuándo repetir. Hable despacio y con claridad."
            }
        } else {
            status = "Local speech or microphone unavailable. Check setup and retry the turn."
            viewerNotice = "ESPERE. No se pudo reconocer la voz. Avise al operador."
        }
    }

    private func sampleTexts(_ language: SourceLanguage) -> (source: String, translation: String) {
        var english = language == .english ? "Hello" : "How are you?"
        var spanish = language == .english ? "Hola" : "¿Cómo está?"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-long-captions") {
            english = "Hello. Please speak slowly so I can understand each sentence. We can take a short break, ask another question, and make sure the translated words remain easy to read on this screen."
            spanish = "Hola. Por favor, hable despacio para que pueda entender cada frase. Podemos hacer una pausa, otra pregunta y comprobar que las palabras traducidas sigan siendo fáciles de leer en esta pantalla."
        }
        #endif
        return language == .english ? (english, spanish) : (spanish, english)
    }

    private func addSample(_ language: SourceLanguage) {
        finishReveal()
        lastRequestedLanguage = language
        viewerNotice = nil
        let sample = sampleTexts(language)
        let generation = ledger.generation
        if let id = ledger.addSource(expected: ledger.generation, language: language,
            source: sample.source) {
            if ledger.finish(expected: generation, id: id,
                translation: sample.translation, failed: false) {
                beginReveal(generation: generation, turnID: id)
            }
        }
        status = "Whipple Chat sample only · microphone off. Start your turn or invite the Spanish speaker."
    }

    func clear() {
        cancelWork()
        status = isSample ? "Whipple Chat sample cleared · microphone off. Start a sample turn."
            : "Conversation cleared. Start your turn or invite the Spanish speaker."
    }

    func showSetup() {
        cancelWork()
        screen = .setup
        isSample = false
        ready = false
        status = "Check local readiness before starting Whipple Chat."
    }

    func sceneChanged(active: Bool) {
        foreground = active
        if !active {
            let hadConversation = screen == .conversation
            // Invalidate setup work too, so an interrupted readiness check cannot stay busy.
            cancelWork()
            ready = false
            screen = .setup
            isSample = false
            status = hadConversation
                ? "Conversation cleared when Whipple Chat left the foreground. Check readiness before restarting."
                : "Whipple Chat setup interrupted. Check readiness before restarting."
        }
    }

    private func cancelWork() {
        ledger.clear()
        cancelCurrentWork()
        lastRequestedLanguage = nil
        viewerNotice = nil
    }

    /// Cancels only the active operation; transcript revision preserves prior turns.
    private func cancelCurrentWork() {
        finishReveal()
        pending?.cancel()
        pending = nil
        speech.cancel()
        translationJob = nil
        phase = .idle
        speaking = nil
        setupBusy = false
        sampleTranslating = false
    }

    func setRevealEnabled(_ enabled: Bool) {
        revealEnabled = enabled && !UIAccessibility.isReduceMotionEnabled
            && !UIAccessibility.isVoiceOverRunning
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reduced-motion") {
            revealEnabled = false
        }
        #endif
        if !revealEnabled { finishReveal() }
    }

    /// Removing the presentation mask exposes the complete ledger text immediately.
    func finishReveal() {
        guard revealTask != nil || captionReveal != nil || revealingTurnID != nil else { return }
        revealTask?.cancel()
        revealTask = nil
        captionReveal = nil
        revealingTurnID = nil
    }

    private func beginReveal(generation: UInt64, turnID: UInt64) {
        finishReveal()
        guard ledger.isCurrent(generation), foreground, screen == .conversation,
              let text = ledger.turns.first(where: { $0.id == turnID })?.translation else { return }
        var enabled = revealEnabled && !UIAccessibility.isReduceMotionEnabled
            && !UIAccessibility.isVoiceOverRunning
        var tickNanoseconds: UInt64 = 70_000_000
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-reduced-motion") { enabled = false }
        if arguments.contains("--ui-testing-slow-reveal") { tickNanoseconds = 350_000_000 }
        #endif
        let reveal = CaptionReveal(text: text, enabled: enabled)
        guard !reveal.isComplete else { return }
        revealingTurnID = turnID
        captionReveal = reveal
        revealTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: tickNanoseconds) }
                catch { return }
                guard !Task.isCancelled, let self, self.foreground,
                      self.screen == .conversation, self.ledger.isCurrent(generation),
                      self.revealingTurnID == turnID, var reveal = self.captionReveal else { return }
                reveal.advance()
                if reveal.isComplete {
                    self.finishReveal()
                    return
                }
                self.captionReveal = reveal
            }
        }
    }

    private enum AppError: Error { case missingTranslation, emptyTranslation }
}
