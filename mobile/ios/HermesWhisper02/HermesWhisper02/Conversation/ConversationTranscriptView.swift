import SwiftUI

struct ConversationTranscriptView: View {
    let messages: [ConversationMessage]
    var liveUserText: String?

    private var items: [ConversationTranscriptItem] {
        var items = messages.map(ConversationTranscriptItem.init(message:))
        if let liveUserText = liveUserText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !liveUserText.isEmpty {
            items.append(ConversationTranscriptItem(
                id: "live-user-transcript",
                role: .user,
                text: liveUserText
            ))
        }
        return items
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            ConversationBubble(item: item, maxWidth: geometry.size.width * 0.80)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .onAppear {
                    scrollToBottom(proxy)
                }
                .onChange(of: items.count) { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastID = items.last?.id else {
            return
        }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct ConversationTranscriptItem: Identifiable, Equatable {
    let id: String
    let role: ConversationMessage.Role
    let text: String

    init(id: String, role: ConversationMessage.Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }

    init(message: ConversationMessage) {
        id = message.id
        role = message.role
        text = message.text
    }
}

private struct ConversationBubble: View {
    let item: ConversationTranscriptItem
    let maxWidth: CGFloat

    var body: some View {
        HStack {
            if item.role == .user {
                Spacer(minLength: 48)
            }

            Text(item.text)
                .textSelection(.enabled)
                .font(.body)
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: maxWidth, alignment: alignment)
                .background(backgroundStyle)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if item.role == .assistant {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: rowAlignment)
    }

    private var alignment: Alignment {
        item.role == .user ? .trailing : .leading
    }

    private var rowAlignment: Alignment {
        item.role == .user ? .trailing : .leading
    }

    private var foregroundStyle: Color {
        item.role == .user ? .white : .primary
    }

    private var backgroundStyle: Color {
        item.role == .user ? .accentColor : Color(.secondarySystemBackground)
    }
}
