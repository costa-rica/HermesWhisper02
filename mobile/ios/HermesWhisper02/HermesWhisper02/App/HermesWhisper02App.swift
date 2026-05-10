import SwiftUI

@main
struct HermesWhisper02App: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            VoiceView()
                .environment(environment)
        }
    }
}
