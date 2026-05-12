import SwiftUI

struct VoiceView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var logoutError: String?
    @State private var showingServers = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Hello, HermesWhisper02")
                .font(.title2)
            Text(appEnvironment.activeServerName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Log out", role: .destructive) {
                logout()
            }
            .buttonStyle(.bordered)
            Button {
                showingServers = true
            } label: {
                Label("Servers", systemImage: "server.rack")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .sheet(isPresented: $showingServers) {
            NavigationStack {
                ServerRegistryView()
            }
        }
        .alert("Logout failed", isPresented: logoutFailed) {
            Button("OK", role: .cancel) {
                logoutError = nil
            }
        } message: {
            Text(logoutError ?? "Unable to clear stored credentials.")
        }
    }

    private var logoutFailed: Binding<Bool> {
        Binding(
            get: { logoutError != nil },
            set: { isPresented in
                if !isPresented {
                    logoutError = nil
                }
            }
        )
    }

    private func logout() {
        do {
            try appEnvironment.logout()
        } catch {
            logoutError = error.localizedDescription
        }
    }
}

#Preview {
    VoiceView()
        .environment(AppEnvironment())
}
