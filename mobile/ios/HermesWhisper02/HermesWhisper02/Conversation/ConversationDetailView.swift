import SwiftUI

struct ConversationDetailView: View {
    @ObservedObject var store: ConversationStore
    let session: ConversationSession
    let onResume: (String) -> Void

    @State private var messages: [ConversationMessage] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ConversationTranscriptView(messages: messages, liveUserText: nil)
            Divider()
            Button {
                onResume(session.id)
            } label: {
                Label("Resume", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .navigationTitle(session.title ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            reload()
        }
        .onChange(of: store.changeToken) { _, _ in
            reload()
        }
        .alert("Conversation unavailable", isPresented: errorPresented) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unable to load this conversation.")
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
            messages = try store.loadMessages(sessionID: session.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
