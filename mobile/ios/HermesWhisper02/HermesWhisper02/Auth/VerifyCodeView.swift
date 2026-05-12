import SwiftUI

struct VerifyCodeView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    let email: String

    @State private var code = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text(email)
                    .foregroundStyle(.secondary)
                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .onChange(of: code) { _, newValue in
                        code = String(newValue.filter(\.isNumber).prefix(6))
                    }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    verify()
                } label: {
                    if isVerifying {
                        ProgressView()
                    } else {
                        Text("Verify")
                    }
                }
                .disabled(isVerifying || code.count != 6)
            }
        }
        .navigationTitle("Verify")
    }

    private func verify() {
        isVerifying = true
        errorMessage = nil

        Task {
            do {
                try await appEnvironment.verify(email: email, code: code)
            } catch {
                errorMessage = error.localizedDescription
            }
            isVerifying = false
        }
    }
}
