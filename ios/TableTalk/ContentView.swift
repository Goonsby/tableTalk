import SwiftUI
import Translation
import TableTalkCore

private enum Theme {
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let ink = Color(red: 0.11, green: 0.18, blue: 0.17)
    static let green = Color(red: 0.13, green: 0.39, blue: 0.35)
}

struct ContentView: View {
    @ObservedObject var model: ConversationModel
    @ScaledMetric(relativeTo: .title2) private var captionSize = 25

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if model.screen == .setup { setup } else { conversation }
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.green)
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
        VStack(spacing: 0) {
            panel(.spanish)
                .rotationEffect(.degrees(180))
            VStack(spacing: 6) {
                if model.isSample {
                    Text("SAMPLE · MICROPHONE OFF / EJEMPLO · SIN MICRÓFONO")
                        .font(.caption.bold()).multilineTextAlignment(.center)
                        .accessibilityIdentifier("demo.label")
                }
                HStack {
                    Button("Setup / Preparación", action: model.showSetup)
                        .accessibilityIdentifier("conversation.setup")
                    Spacer()
                    Button("Clear / Borrar", action: model.clear)
                        .accessibilityIdentifier("conversation.clear")
                }.buttonStyle(.bordered).font(.callout.bold())
                Text(model.status).font(.caption).multilineTextAlignment(.center)
                    .accessibilityIdentifier("conversation.status")
            }.padding(.horizontal, 14).padding(.vertical, 8)
                .background(Theme.green.opacity(0.1))
            panel(.english)
        }
    }

    private func panel(_ language: SourceLanguage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language == .english ? "English" : "Español").font(.title3.bold())
                Spacer()
                Text(language == .english ? "YOUR SIDE" : "SU LADO")
                    .font(.caption.weight(.semibold)).tracking(1.3)
            }
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if model.turns.isEmpty {
                            Text(language == .english ? "Your conversation will appear here." : "La conversación aparecerá aquí.")
                                .font(.title3).foregroundStyle(Theme.ink.opacity(0.65))
                        }
                        ForEach(model.turns) { turn in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(turn.text(for: language) ?? (turn.translationFailed
                                    ? (language == .english ? "Translation unavailable" : "Traducción no disponible")
                                    : (language == .english ? "Translating…" : "Traduciendo…")))
                                    .font(.system(size: captionSize, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("caption.\(turn.sourceLanguage == language ? "source" : "translation").\(language == .english ? "english" : "spanish")")
                                Text(turn.text(for: language.other) ?? (turn.translationFailed
                                    ? "Translation unavailable / Traducción no disponible"
                                    : "Translating… / Traduciendo…"))
                                    .font(.body).foregroundStyle(Theme.ink.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading).id(turn.id)
                            Divider()
                        }
                    }.padding(.vertical, 4)
                }
                .onChange(of: model.turns) { _, turns in
                    if let id = turns.last?.id { scroll.scrollTo(id, anchor: .bottom) }
                }
            }
            Button { model.speak(language) } label: {
                Label(speakLabel(language), systemImage: model.phase == .recording && model.speaking == language ? "stop.fill" : "mic.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }.buttonStyle(.borderedProminent)
                .disabled(!model.isSample && (!model.ready || model.phase == .processing ||
                    (model.phase == .recording && model.speaking != language)))
                .accessibilityIdentifier("speak.\(language == .english ? "english" : "spanish")")
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language == .english ? "English panel" : "Panel Español")
        .accessibilityIdentifier("panel.\(language == .english ? "english" : "spanish")")
    }

    private func speakLabel(_ language: SourceLanguage) -> String {
        if model.phase == .recording && model.speaking == language {
            return language == .english ? "Finish speaking" : "Terminar"
        }
        return language == .english ? "Speak English" : "Hablar español"
    }
}

private struct TranslationHost: View {
    @ObservedObject var model: ConversationModel
    let job: ConversationModel.TranslationJob

    var body: some View {
        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            .translationTask(TranslationSession.Configuration(
                source: Locale.Language(identifier: job.source.code),
                target: Locale.Language(identifier: job.source.other.code))) { session in
                await model.perform(job, using: session)
            }
    }
}
