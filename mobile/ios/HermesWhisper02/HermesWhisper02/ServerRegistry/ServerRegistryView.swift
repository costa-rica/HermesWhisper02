import SwiftUI

struct ServerRegistryView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    private let store: ServerRegistryStore

    @State private var profiles: [ServerProfile] = []
    @State private var editorMode: ServerProfileEditView.Mode?
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .inactive

    init(store: ServerRegistryStore? = nil) {
        self.store = store ?? (try! ServerRegistryStore())
    }

    var body: some View {
        List {
            ForEach(profiles) { profile in
                Button {
                    select(profile)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName)
                                .foregroundStyle(.primary)
                            Text(profile.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.id == appEnvironment.activeProfile.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                        Button {
                            editorMode = .edit(profile)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit \(profile.displayName)")
                    }
                }
                .contextMenu {
                    Button("Edit") {
                        editorMode = .edit(profile)
                    }
                }
            }
            .onDelete(perform: delete)
            .onMove(perform: move)
        }
        .navigationTitle("Servers")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorMode = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Server")
            }
        }
        .sheet(item: editorBinding) { item in
            ServerProfileEditView(mode: item.mode) { profile in
                try save(profile, mode: item.mode)
            }
        }
        .alert("Server Registry Error", isPresented: errorPresented) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unable to update servers.")
        }
        .onAppear(perform: load)
    }

    private var editorBinding: Binding<IdentifiedEditorMode?> {
        Binding(
            get: {
                editorMode.map(IdentifiedEditorMode.init(mode:))
            },
            set: { value in
                editorMode = value?.mode
            }
        )
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

    private func load() {
        do {
            profiles = try store.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func select(_ profile: ServerProfile) {
        appEnvironment.switchActiveProfile(profile)
    }

    private func delete(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        do {
            try store.save(profiles)
            if !profiles.contains(where: { $0.id == appEnvironment.activeProfile.id }),
               let first = profiles.first {
                appEnvironment.switchActiveProfile(first)
            }
        } catch {
            errorMessage = error.localizedDescription
            load()
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
        do {
            try store.reorder(profiles)
        } catch {
            errorMessage = error.localizedDescription
            load()
        }
    }

    private func save(
        _ profile: ServerProfile,
        mode: ServerProfileEditView.Mode
    ) throws {
        switch mode {
        case .add:
            try store.add(profile)
        case .edit:
            try store.update(profile)
        }
        load()
        appEnvironment.switchActiveProfile(profile)
    }
}

private struct IdentifiedEditorMode: Identifiable {
    let mode: ServerProfileEditView.Mode

    var id: String {
        switch mode {
        case .add:
            "add"
        case let .edit(profile):
            "edit-\(profile.id.uuidString)"
        }
    }
}
