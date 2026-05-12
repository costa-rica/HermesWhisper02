import SwiftUI

struct LoginView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var email = "nrodrig1@gmail.com"
    @State private var password = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var verificationEmail: String?

    var body: some View {
        Form {
            Section {
                Text(appEnvironment.activeServerName)
                    .foregroundStyle(.secondary)
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    sendCode()
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("Send code")
                    }
                }
                .disabled(isSending || email.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle("Login")
        .navigationDestination(item: $verificationEmail) { email in
            VerifyCodeView(email: email)
        }
    }

    private func sendCode() {
        isSending = true
        errorMessage = nil

        Task {
            do {
                try await appEnvironment.login(email: email, password: password)
                verificationEmail = email
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
