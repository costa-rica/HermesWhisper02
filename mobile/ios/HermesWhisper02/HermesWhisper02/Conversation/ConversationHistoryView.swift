import SwiftUI

struct ConversationHistoryView: View {
    @ObservedObject var store: ConversationStore
    let activeServerName: String
    let onResume: (String) -> Void

    @State private var sessions: [ConversationSession] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if sessions.isEmpty {
                    Text("No conversations yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        NavigationLink {
                            ConversationDetailView(
                                store: store,
                                session: session,
                                onResume: onResume
                            )
                        } label: {
                            ConversationHistoryRow(session: session)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                remove(session)
                            } label: {
                                Text("Remove from this device")
                            }
                        }
                    }
                }
            } header: {
                Text(activeServerName)
                    .textCase(nil)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            reload()
        }
        .onChange(of: store.changeToken) { _, _ in
            reload()
        }
        .alert("History unavailable", isPresented: errorPresented) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unable to load conversation history.")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func reload() {
        do {
            sessions = try store.listSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ session: ConversationSession) {
        do {
            try store.deleteSession(sessionID: session.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ConversationHistoryRow: View {
    let session: ConversationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.title ?? session.lastMessagePreview ?? "Untitled conversation")
                .font(.body)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(session.updatedAt, style: .relative)
                Text(messageCountText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var messageCountText: String {
        session.messageCount == 1 ? "1 message" : "\(session.messageCount) messages"
    }
}
