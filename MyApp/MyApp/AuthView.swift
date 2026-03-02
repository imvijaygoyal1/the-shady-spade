import SwiftUI

struct AuthView: View {
    @Environment(AuthViewModel.self) private var authVM
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .signIn

    enum Page { case signIn, signUp, verifyEmail }

    var body: some View {
        ZStack {
            Color.darkBG.ignoresSafeArea()
            switch page {
            case .signIn:
                SignInPage(onCreateAccount: { page = .signUp })
            case .signUp:
                SignUpPage(onSignIn: { page = .signIn }, onVerify: { page = .verifyEmail },
                           onCancel: { dismiss() })
            case .verifyEmail:
                VerifyEmailPage(onVerified: { dismiss() })
            }
        }
        .onAppear {
            // Already signed in and verified (e.g. returning user)
            if authVM.isEmailVerified { dismiss() }
        }
        .onChange(of: authVM.isEmailVerified) { _, verified in
            if verified { dismiss() }   // covers sign-in AND verify-email pages
        }
    }
}

// MARK: - Sign In Page

private struct SignInPage: View {
    @Environment(AuthViewModel.self) private var authVM
    var onCreateAccount: () -> Void

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                headerView(title: "Sign In")

                VStack(spacing: 16) {
                    AuthTextField(title: "Email", text: $email, keyboardType: .emailAddress)
                    AuthTextField(title: "Password", text: $password, isSecure: true)
                    errorLabel(authVM.errorMessage)
                }
                .padding()
                .glassmorphic(cornerRadius: 20)

                primaryButton(title: "Sign In", isLoading: authVM.isLoading,
                              disabled: email.isEmpty || password.isEmpty) {
                    Task { await authVM.signIn(email: email, password: password) }
                }

                linkButton(prefix: "Don't have an account? ", link: "Create one",
                           action: onCreateAccount)
            }
            .padding()
        }
    }
}

// MARK: - Sign Up Page

private struct SignUpPage: View {
    @Environment(AuthViewModel.self) private var authVM
    var onSignIn: () -> Void
    var onVerify: () -> Void
    var onCancel: () -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var passwordMismatch: Bool {
        !confirmPassword.isEmpty && password != confirmPassword
    }

    var body: some View {
        VStack(spacing: 0) {
            // Cancel bar — always pinned above the scroll view
            HStack {
                Button("Cancel") {
                    HapticManager.impact(.light)
                    onCancel()
                }
                .font(.body)
                .foregroundStyle(.masterGold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 28) {
                    headerView(title: "Create Account")

                VStack(spacing: 16) {
                    AuthTextField(title: "Display Name", text: $name)
                    AuthTextField(title: "Email", text: $email, keyboardType: .emailAddress)
                    AuthTextField(title: "Password", text: $password, isSecure: true)
                    AuthTextField(title: "Confirm Password", text: $confirmPassword, isSecure: true)
                    if passwordMismatch {
                        errorLabel("Passwords do not match")
                    }
                    errorLabel(authVM.errorMessage)
                }
                .padding()
                .glassmorphic(cornerRadius: 20)

                primaryButton(title: "Create Account", isLoading: authVM.isLoading,
                              disabled: name.isEmpty || email.isEmpty || password.isEmpty
                                      || passwordMismatch) {
                    Task {
                        await authVM.signUp(name: name, email: email, password: password)
                        if authVM.errorMessage == nil { onVerify() }
                    }
                }

                linkButton(prefix: "Already have an account? ", link: "Sign in",
                           action: onSignIn)
                }
                .padding()
            } // ScrollView
        } // VStack
    }
}

// MARK: - Verify Email Page

private struct VerifyEmailPage: View {
    @Environment(AuthViewModel.self) private var authVM
    var onVerified: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.masterGold.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Text("✉️")
                        .font(.system(size: 48))
                }
                Text("Check Your Inbox")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("A verification email was sent to\n\(maskedEmail(authVM.user?.email))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.masterGold)
                Text("Checking every 3 seconds…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .glassmorphic(cornerRadius: 16)

            primaryButton(title: "Resend Email", isLoading: authVM.isLoading, disabled: false) {
                Task { await authVM.sendVerificationEmail() }
            }

            Spacer()
        }
        .padding()
        .task {
            let maxAttempts = 60 // 3 minutes at 3-second intervals
            var attempt = 0
            while !authVM.isEmailVerified && attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await authVM.reloadUser()
                attempt += 1
                if authVM.isEmailVerified {
                    HapticManager.success()
                    onVerified()
                    return
                }
            }
        }
    }
}

// MARK: - Auth Text Field

private struct AuthTextField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Group {
                if isSecure {
                    SecureField("", text: $text)
                        .accessibilityLabel(title)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                        .autocorrectionDisabled(keyboardType == .emailAddress)
                        .accessibilityLabel(title)
                }
            }
            .tint(.masterGold)
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - Shared view helpers (file-private free functions)

private func headerView(title: String) -> some View {
    VStack(spacing: 10) {
        Text("♠")
            .font(.system(size: 56, weight: .black))
            .foregroundStyle(.masterGold)
        Text(title)
            .font(.title.bold())
            .foregroundStyle(.white)
        Text("The Shady Spade")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
    .padding(.top, 40)
}

private func primaryButton(title: String, isLoading: Bool, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
    Button {
        HapticManager.impact(.medium)
        action()
    } label: {
        Group {
            if isLoading {
                ProgressView().tint(.black)
            } else {
                Text(title).fontWeight(.bold)
            }
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(disabled || isLoading ? Color.masterGold.opacity(0.45) : Color.masterGold)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(BouncyButton())
    .disabled(disabled || isLoading)
}

private func linkButton(prefix: String, link: String, action: @escaping () -> Void) -> some View {
    Button {
        HapticManager.impact(.light)
        action()
    } label: {
        (Text(prefix).foregroundStyle(.secondary) + Text(link).foregroundStyle(.masterGold).bold())
            .font(.subheadline)
    }
}

private func maskedEmail(_ email: String?) -> String {
    guard let email, let atIndex = email.firstIndex(of: "@") else { return "your email" }
    let local = String(email[email.startIndex..<atIndex])
    let domain = String(email[atIndex...])
    let visible = local.prefix(2)
    let masked = String(repeating: "*", count: max(0, local.count - 2))
    return "\(visible)\(masked)\(domain)"
}

@ViewBuilder
private func errorLabel(_ message: String?) -> some View {
    if let message {
        Text(message)
            .font(.caption)
            .foregroundStyle(.defenseRose)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
