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
    @State private var showIntro = true

    var body: some View {
        ZStack {
            Group {
                if model.settings.hasOnboarded {
                    MapHomeView()
                } else {
                    WelcomeView()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: model.settings.hasOnboarded)

            if showIntro, model.settings.hasOnboarded {
                IntroView { showIntro = false }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }
}

/// Entrada de marca al abrir la app: el logotipo traza su diagonal roja y se desvanece.
/// Dura menos de un segundo, el mapa ya se está cargando debajo y con «Reducir movimiento»
/// solo hay un fundido breve.
private struct IntroView: View {
    let onFinish: () -> Void
    @State private var progress: CGFloat = 0
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            NEXColor.black.ignoresSafeArea()
            RadialGradient(colors: [NEXColor.red.opacity(0.16), .clear], center: .center, startRadius: 4, endRadius: 260)
                .ignoresSafeArea()
            NEXLogo(size: 76, progress: progress)
                .scaleEffect(scale)
                .shadow(color: NEXColor.red.opacity(0.4), radius: 22)
        }
        .task {
            if NEXMotion.reduced {
                progress = 1
                try? await Task.sleep(for: .milliseconds(250))
            } else {
                withAnimation(.smooth(duration: 0.5)) { progress = 1 }
                try? await Task.sleep(for: .milliseconds(560))
                withAnimation(.easeIn(duration: 0.25)) { scale = 1.08 }
            }
            withAnimation(.easeOut(duration: 0.3)) { onFinish() }
        }
        .accessibilityHidden(true)
    }
}
