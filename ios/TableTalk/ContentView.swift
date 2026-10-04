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

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if model.screen == .setup { setup } else { conversation }
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
                        Text("TableTalk").font(.largeTitle.bold())
                        Text("English ↔ Español").font(.headline)
                    }
                }
                Text("One phone. Two voices.").font(.title2.bold())
                Text("Un teléfono. Dos voces.").font(.title3)
                Text("Set the phone between you. Each person reads their own side and taps to speak. Captions appear after a short speaking turn.")
                Text("Coloque el teléfono entre ustedes. Cada persona lee su lado y toca para hablar. Los subtítulos aparecen al terminar cada intervención.")
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
                    Text("Audio and captions are not saved by TableTalk. Leaving the conversation clears its history. Speech requests require on-device processing. Missing local models fail visibly. iOS cannot block screenshots or revoke this app's network access; use airplane mode with Wi-Fi off for an offline visit.")
                    Text("TableTalk no guarda audio ni subtítulos. Al salir se borra la conversación. La voz se procesa en el dispositivo. iOS no permite bloquear capturas de pantalla ni quitar el acceso a internet de la app. Use modo avión, sin Wi-Fi.")
                    Text("Ask both people's permission before recording. Verify important meanings with a qualified interpreter. / Pida permiso antes de grabar. Verifique los mensajes importantes con un intérprete cualificado.")
                }.font(.footnote)
            }.padding(24).frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
        }
    }

    private var conversation: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                VStack(spacing: 0) {
                    conversationControls
                    HStack(spacing: 0) {
                        CaptionPanel(model: model, language: .spanish).rotationEffect(.degrees(180))
                        Divider()
                        CaptionPanel(model: model, language: .english)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    CaptionPanel(model: model, language: .spanish).rotationEffect(.degrees(180))
                    conversationControls
                    CaptionPanel(model: model, language: .english)
                }
            }
        }
    }

    private var conversationControls: some View {
        VStack(spacing: 4) {
            if model.isSample {
                Text("SAMPLE · MICROPHONE OFF / EJEMPLO · SIN MICRÓFONO")
                    .font(.caption.bold()).multilineTextAlignment(.center)
                    .accessibilityIdentifier("demo.label")
            }
            HStack(spacing: 12) {
                Button("Setup / Preparación", action: model.showSetup)
                    .accessibilityIdentifier("conversation.setup")
                Spacer(minLength: 0)
                Button("Clear / Borrar", action: model.clear)
                    .accessibilityIdentifier("conversation.clear")
            }.buttonStyle(.bordered).font(.callout.bold())
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.green.opacity(0.1))
    }

    private func updateRevealPreference() {
        model.setRevealEnabled(!reduceMotion && !UIAccessibility.isVoiceOverRunning)
    }
}

private struct CaptionPanel: View {
    @ObservedObject var model: ConversationModel
    let language: SourceLanguage
    @ScaledMetric(relativeTo: .title2) private var captionSize = 25
    @State private var followsNewest = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.displayName).font(.title3.bold())
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if model.turns.isEmpty {
                            Text(language == .english ? "Your conversation will appear here." : "La conversación aparecerá aquí.")
                                .font(.title3).foregroundStyle(Theme.ink.opacity(0.65))
                        }
                        ForEach(model.turns) { turn in
                            VStack(alignment: .leading, spacing: 6) {
                                caption(turn, for: language)
                                    .font(.system(size: captionSize, weight: .semibold))
                                    .accessibilityIdentifier("caption.\(turn.sourceLanguage == language ? "source" : "translation").\(language == .english ? "english" : "spanish")")
                                caption(turn, for: language.other)
                                    .font(.body).foregroundStyle(Theme.ink.opacity(0.8))
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
            Text(statusLabel).font(.caption)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityIdentifier("status.\(language == .english ? "english" : "spanish")")
            Button { model.speak(language) } label: {
                Label(speakLabel, systemImage: model.phase == .recording && model.speaking == language ? "stop.fill" : "mic.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(.white)
            }.buttonStyle(.borderedProminent)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .disabled(!model.isSample && (!model.ready || model.phase == .processing ||
                    (model.phase == .recording && model.speaking != language)))
                .accessibilityIdentifier("speak.\(language == .english ? "english" : "spanish")")
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language == .english ? "English panel" : "Panel Español")
        .accessibilityIdentifier("panel.\(language == .english ? "english" : "spanish")")
    }

    // Reserve the final wrapped layout immediately and change only the ink.
    // Accessibility always receives the entire caption, including hidden words.
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
            .textSelection(.enabled)
    }

    private var speakLabel: String {
        if model.phase == .recording && model.speaking == language {
            return language == .english ? "Finish speaking" : "Terminar"
        }
        return language == .english ? "Speak English" : "Hablar español"
    }

    private var statusLabel: String {
        let parts = model.status.components(separatedBy: " / ")
        return (language == .english ? parts.first : parts.last) ?? model.status
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
