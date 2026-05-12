import SwiftUI

@main
struct HermesWhisper02App: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
    }
}

private struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        Group {
            if appEnvironment.isAuthenticated {
                VoiceView()
            } else {
                NavigationStack {
                    LoginView()
                }
            }
        }
        .onAppear {
            appEnvironment.refreshCredentials()
        }
    }
}
