import SwiftUI
import FirebaseAuth
import Observation

@Observable final class AuthViewModel {
    var user: FirebaseAuth.User? = nil
    var isEmailVerified: Bool = false
    var isLoading: Bool = false
    var errorMessage: String? = nil

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        // Firebase is not yet configured at init time (SwiftUI lifecycle).
        // Call start() after FirebaseApp.configure() via .task in the root view.
    }

    func start() {
        guard authStateHandle == nil else { return }
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.user = user
            self.isEmailVerified = user?.isEmailVerified ?? false
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signUp(name: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            await updateDisplayName(name)
            try await result.user.sendEmailVerification()
        } catch {
            errorMessage = authErrorMessage(error)
        }
        isLoading = false
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = authErrorMessage(error)
        }
        isLoading = false
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            // Sign-out failure is non-critical on the client side
        }
    }

    func sendVerificationEmail() async {
        isLoading = true
        errorMessage = nil
        do {
            try await user?.sendEmailVerification()
        } catch {
            errorMessage = "Failed to send verification email. Please try again."
        }
        isLoading = false
    }

    func reloadUser() async {
        do {
            try await user?.reload()
            isEmailVerified = Auth.auth().currentUser?.isEmailVerified ?? false
        } catch {
            // Reload failures are non-critical; verification state will sync on next auth event
        }
    }

    func updateDisplayName(_ name: String) async {
        let req = Auth.auth().currentUser?.createProfileChangeRequest()
        req?.displayName = name
        do {
            try await req?.commitChanges()
        } catch {
            // Display name update failure is non-critical
        }
    }

    // MARK: - Private

    private func authErrorMessage(_ error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .emailAlreadyInUse:
            return "An account with this email already exists."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .wrongPassword, .invalidCredential, .userNotFound:
            return "Incorrect email or password."
        case .tooManyRequests:
            return "Too many attempts. Please try again later."
        case .networkError:
            return "Network error. Please check your connection."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
