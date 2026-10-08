import SwiftUI
import UIKit
import Translation
import TableTalkCore

private enum Theme {
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let ink = Color(red: 0.11, green: 0.18, blue: 0.17)
    static let green = Color(red: 0.13, green: 0.39, blue: 0.35)
}

struct ContentView: View {
    @ObservedObject var model: ConversationModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var flipViewer = false
    @State private var correctionPresented = false
    @State private var correctionText = ""

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if model.screen == .setup { setup } else { conversation }
        }
        .sheet(isPresented: $correctionPresented, onDismiss: { correctionText = "" }) { correctionSheet }
        .onChange(of: model.screen) { _, screen in
            if screen == .setup { correctionPresented = false; correctionText = "" }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { correctionPresented = false; correctionText = "" }
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.green)
        .onAppear { updateRevealPreference() }
        .onChange(of: reduceMotion) { _, _ in updateRevealPreference() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            updateRevealPreference()
        }
        .background {
            if let job = model.translationJob {
                TranslationHost(model: model, job: job)
                    .id(job.id)
            }
        }
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.largeTitle).foregroundStyle(Theme.green).accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text("Whipple Chat").font(.largeTitle.bold())
                        Text("English ↔ Español").font(.headline)
                    }
                }
                Text("One operator. Two languages.").font(.title2.bold())
                Text("Un operador. Dos idiomas.").font(.title3)
                Text("You control both language turns. The Spanish speaker behind the glass follows the display without touching the phone. Ask for one short sentence at a time.")
                Text("La persona detrás del cristal no necesita tocar el teléfono. Espere la señal del operador y hable despacio y con claridad.")
                VStack(alignment: .leading, spacing: 14) {
                    Text("Prepare before the visit / Prepare antes de la visita").font(.headline)
                    Text("1. In iPhone Settings → General → Keyboard, enable Dictation and English (US) and Spanish (Spain). Apple manages these speech assets; this app cannot install them. If local speech is unavailable, follow the iPhone guide in the repository.")
                    Text("1. En Ajustes → General → Teclado, active Dictado e inglés (EE. UU.) y español (España). Apple gestiona los modelos de voz.")
                    Button(action: model.requestPermissions) {
                        Label("Enable microphone & Speech / Activar permisos", systemImage: "mic.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered).disabled(model.setupBusy)
                    Text("2. On Wi-Fi, prepare translation languages. Approve Apple's download prompt. / Con Wi-Fi, prepare los idiomas de traducción y acepte la descarga de Apple.")
                    Button(action: model.prepareLanguages) {
                        Label("Prepare translation / Preparar traducción", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered).disabled(model.setupBusy)
                        .accessibilityIdentifier("setup.prepareTranslation")
                    Text("3. Turn on airplane mode and turn Wi-Fi off. Check readiness, then test both speaking directions. / Active el modo avión y apague Wi-Fi. Compruebe y pruebe ambos idiomas.")
                    Button(action: model.checkReadiness) {
                        Label("Check offline readiness / Comprobar", systemImage: "checkmark.shield")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered).disabled(model.setupBusy)
                        .accessibilityIdentifier("setup.checkReadiness")
                }
                .padding(18).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
                if model.setupBusy {
                    HStack { ProgressView(); Text("Checking… / Comprobando…") }
                    Button("Cancel / Cancelar", action: model.showSetup).buttonStyle(.bordered)
                }
                Text(model.status).font(.callout).accessibilityIdentifier("setup.status")
                Button(action: model.startConversation) {
                    Text("Start conversation / Iniciar conversación")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                }.buttonStyle(.borderedProminent).disabled(!model.ready || model.setupBusy)
                    .accessibilityIdentifier("setup.startConversation")
                Button(action: model.startSample) {
                    Text("Try sample layout · no microphone / Ver ejemplo")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.bordered).accessibilityIdentifier("setup.startSample")
                VStack(alignment: .leading, spacing: 10) {
                    Label("Private by design / Privacidad", systemImage: "hand.raised")
                        .font(.headline)
                    Text("Audio and captions are not saved by Whipple Chat. Leaving the conversation clears its history. Speech requests require on-device processing. Missing local models fail visibly. iOS cannot block screenshots or revoke this app's network access; use airplane mode with Wi-Fi off for an offline visit.")
                    Text("Whipple Chat no guarda audio ni subtítulos. Al salir se borra la conversación. La voz se procesa en el dispositivo. iOS no permite bloquear capturas de pantalla ni quitar el acceso a internet de la app. Use modo avión, sin Wi-Fi.")
                    Text("Ask both people's permission before recording. Verify important meanings with a qualified interpreter. / Pida permiso antes de grabar. Verifique los mensajes importantes con un intérprete cualificado.")
                }.font(.footnote)
            }.padding(24).frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
        }
    }

    private var conversation: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                HStack(spacing: 0) {
                    viewer.frame(width: geometry.size.width * 0.40)
                    Divider()
                    operatorPanel(compact: true)
                }
            } else {
                VStack(spacing: 0) {
                    viewer.frame(height: geometry.size.height * 0.40)
                    Divider()
                    operatorPanel(compact: false)
                }
            }
        }
    }

    private var viewer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Whipple Chat · Español").font(.headline)
                .dynamicTypeSize(...DynamicTypeSize.large)
            if model.isSample {
                Text("EJEMPLO · MICRÓFONO APAGADO").font(.caption.bold())
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }
            Text(model.viewerInstruction.replacingOccurrences(of: "EJEMPLO. Micrófono apagado. ", with: ""))
                .font(.title2.bold())
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(model.viewerInstruction)
                .accessibilityIdentifier("viewer.instructions")
            CaptionHistory(model: model, language: .spanish, showCounterpart: false)
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rotationEffect(.degrees(flipViewer ? 180 : 0))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Español. Spanish viewer. No touch required.")
        .accessibilityIdentifier("panel.spanish")
    }

    private func operatorPanel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Whipple Chat · Operator").font(.headline)
                .dynamicTypeSize(...DynamicTypeSize.large)
            Text(model.operatorInstruction).font(.caption.bold())
                .dynamicTypeSize(...DynamicTypeSize.large)
                .accessibilityIdentifier("operator.instructions")
            if model.isSample {
                Text("SAMPLE · MICROPHONE OFF").font(.caption.bold())
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .accessibilityIdentifier("demo.label")
            }
            CaptionHistory(model: model, language: .english, showCounterpart: true)
                .frame(minHeight: 38)
            HStack(spacing: 6) {
                operatorButton("Speak English", id: "speak.english", enabled: model.phase == .idle) { model.speak(.english) }
                operatorButton("Listen to Spanish", id: "speak.spanish", enabled: model.phase == .idle) { model.speak(.spanish) }
            }
            HStack(spacing: 6) { stopButton; retryButton; correctionButton(short: true) }
            HStack(spacing: 6) { clearButton; flipButton(short: true); setupButton }
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.green.opacity(0.06))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("English operator. All conversation controls.")
        .accessibilityIdentifier("panel.english")
    }

    private var stopButton: some View {
        operatorButton("Stop", id: "conversation.stop", enabled: model.phase == .recording,
                       label: "Stop the current speaking turn", action: model.stopSpeaking)
    }

    private var retryButton: some View {
        operatorButton("Retry", id: "conversation.retry", enabled: model.canRetry,
                       label: "Record the last language again", action: model.retryLastTurn)
    }

    private func correctionButton(short: Bool) -> some View {
        operatorButton(short ? "Edit" : "Edit transcript", id: "conversation.correct", enabled: model.canCorrect,
                       label: "Correct the last transcript and translate again") {
            model.finishReveal()
            correctionText = model.lastTranscript
            correctionPresented = true
        }
    }

    private var clearButton: some View {
        operatorButton("Clear", id: "conversation.clear", action: model.clear)
    }

    private var setupButton: some View {
        operatorButton("Setup", id: "conversation.setup", action: model.showSetup)
    }

    private func flipButton(short: Bool) -> some View {
        operatorButton(short ? "Flip" : "Flip Spanish view", id: "viewer.flip",
                       label: "Flip the Spanish display for the viewer") {
            model.finishReveal()
            flipViewer.toggle()
        }
    }

    private func operatorButton(_ title: String, id: String, enabled: Bool = true,
                                label: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.callout.bold()).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered).dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .disabled(!enabled)
        .accessibilityLabel(label ?? title)
        .accessibilityIdentifier(id)
    }

    private var correctionSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Correct only what was actually said.").font(.headline)
                TextEditor(text: $correctionText)
                    .accessibilityLabel("Last spoken transcript")
                    .accessibilityIdentifier("correction.transcript")
                    .border(Theme.green.opacity(0.35))
                if model.isSample {
                    Text("Sample corrections use fixed preview text, not real translation.").font(.footnote)
                }
                Button("Translate again") {
                    model.correctLastTranscript(correctionText)
                    correctionPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(correctionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("correction.translate")
            }
            .padding()
            .navigationTitle("Correct transcript")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { correctionPresented = false }
                        .accessibilityIdentifier("correction.cancel")
                }
            }
        }
        .overlay {
            if scenePhase != .active {
                Theme.paper.ignoresSafeArea()
                    .overlay(Text("Whipple Chat").font(.title.bold()))
                    .accessibilityLabel("Whipple Chat privacy cover")
            }
        }
    }

    private func updateRevealPreference() {
        model.setRevealEnabled(!reduceMotion && !UIAccessibility.isVoiceOverRunning)
    }
}

private struct CaptionHistory: View {
    @ObservedObject var model: ConversationModel
    let language: SourceLanguage
    let showCounterpart: Bool
    @ScaledMetric(relativeTo: .title2) private var captionSize = 25
    @State private var followsNewest = true

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.turns.isEmpty {
                        Text(language == .english ? "Start either language turn below." : "Espere la señal del operador.")
                            .font(.title3).foregroundStyle(Theme.ink.opacity(0.65))
                    }
                    ForEach(model.turns) { turn in
                        VStack(alignment: .leading, spacing: 6) {
                            caption(turn, for: language)
                                .font(.system(size: captionSize, weight: .semibold))
                                .accessibilityIdentifier("caption.\(turn.sourceLanguage == language ? "source" : "translation").\(language == .english ? "english" : "spanish")")
                            if showCounterpart {
                                caption(turn, for: language.other)
                                    .font(.body).foregroundStyle(Theme.ink.opacity(0.8))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).id(turn.id)
                        Divider()
                    }
                }.padding(.vertical, 4)
            }
            .accessibilityIdentifier("captions.\(language == .english ? "english" : "spanish")")
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting || phase == .decelerating {
                    followsNewest = false
                    model.finishReveal()
                }
            }
            .onChange(of: model.turns.last?.id) { _, id in
                followsNewest = true
                if let id { scroll.scrollTo(id, anchor: .top) }
            }
            .onChange(of: model.turns.last?.translation) { _, _ in
                if followsNewest, let id = model.turns.last?.id { scroll.scrollTo(id, anchor: .top) }
            }
        }
    }

    // Layout the final full string first; only its ink changes during reveal.
    private func caption(_ turn: ConversationTurn, for reader: SourceLanguage) -> some View {
        let fullText = turn.text(for: reader) ?? (turn.translationFailed
            ? (reader == .english ? "Translation unavailable" : "Traducción no disponible")
            : (reader == .english ? "Translating." : "Traduciendo."))
        let count = reader != turn.sourceLanguage && model.revealingTurnID == turn.id
            ? (model.captionReveal?.visibleCharacters ?? fullText.count) : fullText.count
        var content = AttributedString(String(fullText.prefix(count)))
        var hidden = AttributedString(String(fullText.dropFirst(count)))
        hidden.foregroundColor = .clear
        content.append(hidden)
        return Text(content)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(fullText)
    }
}

private struct TranslationHost: View {
    @ObservedObject var model: ConversationModel
    let job: ConversationModel.TranslationJob

    var body: some View {
        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            .translationTask(TranslationSession.Configuration(
                source: Locale.Language(identifier: job.source.code),
                target: Locale.Language(identifier: job.source.other.code))) { @Sendable [model, job] session in
                await model.perform(job, using: session)
            }
    }
}
