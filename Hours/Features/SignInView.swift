import GoogleSignInSwift
import SwiftUI

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var notice: String?
    @State private var needsConfirmation = false
    @State private var showingRegister = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 36) {
                Wordmark()
                    .padding(.top, 56)

                VStack(spacing: 22) {
                    LinedField(label: "Email") {
                        TextField("Email", text: $email, prompt: Text(verbatim: "you@example.com"))
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .email)
                            .onSubmit { focus = .password }
                    }
                    LinedField(label: "Password") {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focus, equals: .password)
                            .onSubmit { Task { await signIn() } }
                    }
                }

                VStack(spacing: 14) {
                    if let error { FormMessage(text: error) }
                    if let notice { FormMessage(text: notice, isError: false) }

                    Button {
                        Task { await signIn() }
                    } label: {
                        if isWorking { ProgressView().tint(Theme.buttonText) } else { Text("Sign in") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isWorking || email.isEmpty || password.isEmpty)

                    if needsConfirmation {
                        Button("Resend confirmation email") { Task { await resend() } }
                            .font(.subheadline.weight(.medium))
                    }

                    if GoogleAuth.isConfigured {
                        OrDivider()
                        GoogleSignInButton(scheme: colorScheme == .dark ? .light : .dark, style: .wide) {
                            Task { await signInWithGoogle() }
                        }
                        .disabled(isWorking)
                    }
                }

                HStack(spacing: 18) {
                    Button("Forgot password?") { Task { await forgot() } }
                    Text("·").foregroundStyle(Theme.line)
                    Button("Create an account") { showingRegister = true }
                }
                .font(Theme.serif(.subheadline))
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper)
        .safeAreaInset(edge: .top, spacing: 0) { BarberStripe() }
        .sheet(isPresented: $showingRegister) {
            RegisterView(prefilledEmail: email)
        }
    }

    private func signIn() async {
        guard !email.isEmpty, !password.isEmpty, !isWorking else { return }
        focus = nil
        await working {
            do {
                try await session.signIn(email: email, password: password)
            } catch let apiError as APIError where apiError.code == "email_not_confirmed" {
                needsConfirmation = true
                error = "Confirm your email first, using the link we sent you."
            }
        }
    }

    private func signInWithGoogle() async {
        await working { try await session.signInWithGoogle() }
    }

    private func resend() async {
        await working { notice = try await session.resendConfirmation(email: email) }
    }

    private func forgot() async {
        guard !email.isEmpty else {
            error = "Enter your email first, then tap Forgot password."
            focus = .email
            return
        }
        await working { notice = try await session.forgotPassword(email: email) }
    }

    private func working(_ action: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        error = nil
        notice = nil
        do { try await action() } catch { self.error = error.localizedDescription }
    }
}

private struct Wordmark: View {
    var body: some View {
        VStack(spacing: 10) {
            Eyebrow("The barber's book")
            Text("Hours")
                .font(Theme.display(64))
                .foregroundStyle(Theme.ink)
            OrnamentRule()
            Text("Your chair, your day.")
                .font(Theme.serif(.body).italic())
                .foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Eyebrow("or", color: Theme.muted)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .padding(.vertical, 4)
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

    private var canSubmit: Bool {
        !isWorking && !email.isEmpty && password.count >= 12 && password == confirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("New account")
                        Text(sentMessage == nil ? "Take a seat." : "Check your email.")
                            .font(Theme.display(34))
                            .foregroundStyle(Theme.ink)
                    }

                    if let sentMessage {
                        Text(sentMessage)
                            .foregroundStyle(Theme.ink)
                        Text("Open the link in the email, then come back here and sign in.")
                            .foregroundStyle(Theme.muted)
                        Button("Back to sign in") { dismiss() }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        LinedField(label: "Email") {
                            TextField("Email", text: $email, prompt: Text(verbatim: "you@example.com"))
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        LinedField(label: "Password") {
                            SecureField("At least 12 characters", text: $password)
                                .textContentType(.newPassword)
                        }
                        LinedField(label: "Password again") {
                            SecureField("Same as above", text: $confirm)
                                .textContentType(.newPassword)
                        }

                        if !confirm.isEmpty && password != confirm {
                            FormMessage(text: "Passwords don't match.")
                        } else if let error {
                            FormMessage(text: error)
                        }

                        Button {
                            Task { await register() }
                        } label: {
                            if isWorking { ProgressView().tint(Theme.buttonText) } else { Text("Create account") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSubmit)

                        Text("We'll email you a link to confirm the address before you can sign in.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(28)
            }
            .background(Theme.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sentMessage == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
        .tint(Theme.brass)
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
