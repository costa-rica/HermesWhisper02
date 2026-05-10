import SwiftUI

struct VoiceView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        VStack(spacing: 16) {
            Text("Hello, HermesWhisper02")
                .font(.title2)
            Text(appEnvironment.activeServerName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    VoiceView()
        .environment(AppEnvironment())
}
