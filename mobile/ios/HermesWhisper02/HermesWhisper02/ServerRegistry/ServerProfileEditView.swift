import SwiftUI

struct ServerProfileEditView: View {
    enum Mode {
        case add
        case edit(ServerProfile)
    }

    @Environment(\.dismiss) private var dismiss

    private let mode: Mode
    private let onSave: (ServerProfile) throws -> Void
    private let probe: ServerInfoProbe

    @State private var displayName: String
    @State private var baseURL: String
    @State private var notes: String
    @State private var authKind: ServerProfile.AuthKind = .bearer2FA
    @State private var isProbing = false
    @State private var errorMessage: String?

    init(
        mode: Mode,
        probe: ServerInfoProbe = ServerInfoProbe(),
        onSave: @escaping (ServerProfile) throws -> Void
    ) {
        self.mode = mode
        self.probe = probe
        self.onSave = onSave

        switch mode {
        case .add:
            _displayName = State(initialValue: "")
            _baseURL = State(initialValue: "https://")
            _notes = State(initialValue: "")
        case let .edit(profile):
            _displayName = State(initialValue: profile.displayName)
            _baseURL = State(initialValue: profile.baseURL.absoluteString)
            _notes = State(initialValue: profile.notes ?? "")
            _authKind = State(initialValue: profile.authKind)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $displayName)
                    TextField("Base URL", text: $baseURL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Button {
                        runProbe()
                    } label: {
                        if isProbing {
                            ProgressView()
                        } else {
                            Text("Probe")
                        }
                    }
                    .disabled(isProbing)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(validBaseURL == nil || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var title: String {
        switch mode {
        case .add:
            "Add Server"
        case .edit:
            "Edit Server"
        }
    }

    private var validBaseURL: URL? {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    private func runProbe() {
        guard let url = validBaseURL else {
            errorMessage = "Enter a valid http or https URL."
            return
        }

        isProbing = true
        errorMessage = nil
        Task {
            do {
                let info = try await probe.fetch(baseURL: url)
                if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayName = info.name
                }
                authKind = info.auth
            } catch {
                errorMessage = error.localizedDescription
            }
            isProbing = false
        }
    }

    private func save() {
        guard let url = validBaseURL else {
            errorMessage = "Enter a valid http or https URL."
            return
        }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required."
            return
        }

        do {
            let profileID: UUID
            switch mode {
            case .add:
                profileID = UUID()
            case let .edit(profile):
                profileID = profile.id
            }

            try onSave(
                ServerProfile(
                    id: profileID,
                    displayName: trimmedName,
                    baseURL: url,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    authKind: authKind
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
