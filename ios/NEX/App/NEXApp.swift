import SwiftUI

@main
struct NEXApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(NEXColor.red)
                .task { await model.restoreSession() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    model.setForeground(phase == .active)
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.settings.hasOnboarded {
                MapHomeView()
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.settings.hasOnboarded)
    }
}
