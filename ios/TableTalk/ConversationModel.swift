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
    @Published private(set) var status = "Prepare both languages before a visit. / Prepare ambos idiomas antes de la visita."
    @Published private(set) var translationJob: TranslationJob?
    @Published private(set) var revealingTurnID: UInt64?
    @Published private(set) var captionReveal: CaptionReveal?
    private let speech = SpeechCapture()
    private var pending: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var revealEnabled = !UIAccessibility.isReduceMotionEnabled
        && !UIAccessibility.isVoiceOverRunning
    private var foreground = true

    var turns: [ConversationTurn] { ledger.turns }

    func requestPermissions() {
        cancelWork()
        setupBusy = true
        let generation = ledger.generation
        pending = Task {
            let granted = await SpeechCapture.requestPermissions()
            guard ledger.isCurrent(generation), !Task.isCancelled else { return }
            setupBusy = false
            status = granted
                ? "Permissions enabled. Prepare languages or check readiness. / Permisos activados. Prepare los idiomas o compruebe la disponibilidad."
                : "Microphone and Speech permissions are required. Enable them in Settings → TableTalk. Sample mode remains available. / Active Micrófono y Reconocimiento de voz en Ajustes → TableTalk."
        }
    }

    func prepareLanguages() { startProbe(download: true) }
    func checkReadiness() { startProbe(download: false) }

    private func startProbe(download: Bool) {
        cancelWork()
        ready = false
        setupBusy = true
        status = download
            ? "Preparing English and Spanish. Follow Apple's download prompt. / Preparando inglés y español. Siga las instrucciones de Apple."
            : "Checking local languages… / Comprobando los idiomas locales…"
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
            status = "Tap your side to speak. / Toque su lado para hablar."
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
                    ? "Local language checks passed. Test both directions in airplane mode with Wi-Fi off before a visit. / Pruebas locales completas. Pruebe ambos idiomas en modo avión, sin Wi-Fi."
                    : "Translation is ready. Enable microphone and Speech permissions and English/Spanish Dictation in iPhone Settings, then check again. / Traducción lista. Active los permisos y Dictado en inglés y español en Ajustes y compruebe de nuevo."
            }
        }
    }

    private func fail(_ job: TranslationJob) {
        guard current(job), !Task.isCancelled else { return }
        if let id = job.turnID {
            _ = ledger.finish(expected: job.generation, id: id, translation: nil, failed: true)
            status = "Translation unavailable; original kept. Clear or return to setup to retry. / Traducción no disponible; se conserva el original."
        } else {
            ready = false
            status = "Local language check failed. Prepare languages on Wi-Fi and try again on a physical iPhone. / Falló la comprobación local. Prepare los idiomas con Wi-Fi y pruebe en un iPhone físico."
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
            guard ledger.isCurrent(generation), !Task.isCancelled, foreground else { return }
            setupBusy = false
            guard english, spanish, SpeechCapture.permissionsGranted,
                  SpeechCapture.supports(.english), SpeechCapture.supports(.spanish) else {
                ready = false
                status = "Local languages or permissions changed. Check readiness again. / Compruebe de nuevo los idiomas y permisos."
                return
            }
            isSample = false
            screen = .conversation
            status = "Tap your side to speak. Maximum 12 seconds. / Toque su lado. Máximo 12 segundos."
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
        if isSample { addSample(language); return }
        if phase == .recording {
            if speaking == language { speech.finish() }
            return
        }
        guard phase == .idle, ready else { return }
        phase = .processing
        let generation = ledger.generation
        pending = Task {
            guard await installed(language), !Task.isCancelled,
                  ledger.isCurrent(generation), foreground else {
                if ledger.isCurrent(generation) {
                    phase = .idle
                    ready = false
                    status = "Local translation is missing. Return to setup. / Falta la traducción local. Vuelva a Preparación."
                }
                return
            }
            do {
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
                        self.status = "Translating locally… / Traduciendo en el dispositivo…"
                        self.translationJob = TranslationJob(purpose: .turn, source: language,
                            text: text, generation: generation, turnID: id)
                    case .failure(let error):
                        self.phase = .idle
                        self.status = (error as? SpeechCapture.CaptureError)?.localizedDescription
                            ?? "No local speech result. Check Dictation languages. / Sin resultado local. Compruebe los idiomas de Dictado."
                    }
                }, onStopped: { [weak self] in
                    guard let self, self.ledger.isCurrent(generation) else { return }
                    self.phase = .processing
                    self.status = "Finishing local recognition… / Finalizando el reconocimiento local…"
                })
                // Only a successfully started recording ends the previous reveal.
                finishReveal()
                phase = .recording
                status = "Listening—tap again to finish. / Escuchando—toque de nuevo para terminar."
            } catch {
                phase = .idle
                speaking = nil
                status = (error as? SpeechCapture.CaptureError)?.localizedDescription
                    ?? "Local speech or microphone unavailable. Return to setup. / Voz local o micrófono no disponible. Vuelva a Preparación."
            }
        }
    }

    private func addSample(_ language: SourceLanguage) {
        finishReveal()
        var english = language == .english ? "Hello" : "How are you?"
        var spanish = language == .english ? "Hola" : "¿Cómo está?"
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-long-captions") {
            english = "Hello. Please speak slowly so I can understand each sentence. We can take a short break, ask another question, and make sure the translated words remain easy to read on this screen."
            spanish = "Hola. Por favor, hable despacio para que pueda entender cada frase. Podemos hacer una pausa breve, hacer otra pregunta y comprobar que las palabras traducidas sigan siendo fáciles de leer en esta pantalla."
        }
        #endif
        let generation = ledger.generation
        if let id = ledger.addSource(expected: ledger.generation, language: language,
            source: language == .english ? english : spanish) {
            if ledger.finish(expected: generation, id: id,
                translation: language == .english ? spanish : english, failed: false) {
                beginReveal(generation: generation, turnID: id)
            }
        }
        status = "Sample only · microphone off / Solo ejemplo · micrófono apagado"
    }

    func clear() {
        cancelWork()
        status = isSample ? "Sample cleared · microphone off / Ejemplo borrado · micrófono apagado"
            : "Cleared. Tap your side to speak. / Borrado. Toque su lado para hablar."
    }

    func showSetup() {
        cancelWork()
        screen = .setup
        isSample = false
        ready = false
        status = "Check local readiness before starting. / Compruebe la disponibilidad local antes de comenzar."
    }

    func sceneChanged(active: Bool) {
        foreground = active
        if !active {
            finishReveal()
            // Clear conversation immediately, including on interruptions/app switcher.
            if screen == .conversation { clear(); ready = false; screen = .setup; isSample = false }
        }
    }

    private func cancelWork() {
        finishReveal()
        ledger.clear()
        pending?.cancel()
        pending = nil
        speech.cancel()
        translationJob = nil
        phase = .idle
        speaking = nil
        setupBusy = false
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
        if arguments.contains("--ui-testing-slow-reveal") { tickNanoseconds = 200_000_000 }
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
