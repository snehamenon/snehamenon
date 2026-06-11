import SwiftUI

@main
struct MuseApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
    }
}

/// Routes through the four-stage core loop.
struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            MuseTheme.background.ignoresSafeArea()
            switch app.stage {
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .scan:
                FaceScanView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .intent:
                IntentView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .looks:
                LookOptionsView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .tutorial:
                TutorialView()
                    .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .opacity))
            }
        }
        .animation(.spring(duration: 0.45), value: app.stage)
    }
}
