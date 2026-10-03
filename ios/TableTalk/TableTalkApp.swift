import SwiftUI

@main
struct TableTalkApp: App {
    @StateObject private var model = ConversationModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .overlay {
                    if scenePhase != .active {
                        Color(.systemBackground).ignoresSafeArea()
                            .overlay(Text("TableTalk").font(.largeTitle.bold()))
                            .accessibilityLabel("TableTalk privacy cover")
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    model.sceneChanged(active: phase == .active)
                }
        }
    }
}
