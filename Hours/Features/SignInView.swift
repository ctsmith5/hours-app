import SwiftUI

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var notice: String?
    @State private var needsConfirmation = false
    @State private var showingRegister = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Text("Sign in")
                            if isWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isWorking || email.isEmpty || password.isEmpty)

                    if needsConfirmation {
                        Button("Resend confirmation email") { Task { await resend() } }
                    }
                    Button("Forgot password") { Task { await forgot() } }
                        .disabled(email.isEmpty)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if let notice {
                    Section { Text(notice) }
                }

                Section {
                    Button("Create an account") { showingRegister = true }
                }
            }
            .navigationTitle("Hours")
            .sheet(isPresented: $showingRegister) {
                RegisterView(prefilledEmail: email)
            }
        }
    }

    private func signIn() async {
        isWorking = true
        defer { isWorking = false }
        error = nil
        notice = nil
        do {
            try await session.signIn(email: email, password: password)
        } catch let apiError as APIError where apiError.code == "email_not_confirmed" {
            needsConfirmation = true
            error = "Confirm your email first. Use the link we sent you."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resend() async {
        await run { try await session.resendConfirmation(email: email) }
    }

    private func forgot() async {
        await run { try await session.forgotPassword(email: email) }
    }

    private func run(_ action: () async throws -> String) async {
        error = nil
        do { notice = try await action() } catch { self.error = error.localizedDescription }
    }
}

struct RegisterView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var password = ""
    @State private var confirm = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var sentMessage: String?

    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let sentMessage {
                    Section {
                        Text(sentMessage)
                        Text("Open the link in the email, then come back and sign in.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password (12+ characters)", text: $password)
                            .textContentType(.newPassword)
                        SecureField("Password again", text: $confirm)
                            .textContentType(.newPassword)
                    }
                    Section {
                        Button("Create account") { Task { await register() } }
                            .disabled(isWorking || email.isEmpty || password.count < 12 || password != confirm)
                    } footer: {
                        if !confirm.isEmpty && password != confirm { Text("Passwords don't match.") }
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Create account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sentMessage == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    private func register() async {
        isWorking = true
        defer { isWorking = false }
        error = nil
        do {
            sentMessage = try await session.register(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
