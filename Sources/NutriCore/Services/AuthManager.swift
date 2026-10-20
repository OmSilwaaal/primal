import AuthenticationServices
import Foundation
import Supabase
import Combine
import UIKit

let supabase = SupabaseClient(
    supabaseURL: AppConstants.supabaseURL,
    supabaseKey: AppConstants.supabaseAnonKey
)

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var authError: String?
    /// Skipped login: the app runs on local data only, with no account behind it.
    @Published private(set) var isGuest = UserDefaults.standard.bool(forKey: "isGuest")
    
    private var authStateListener: Task<Void, Never>?
    
    init() {
        startListeningToAuthState()
    }
    
    private func startListeningToAuthState() {
        Task {
            for await (event, session) in await supabase.auth.authStateChanges {
                self.isAuthenticated = (session != nil)
                if session != nil { self.setGuest(false) }
            }
        }
    }
    
    func signUp(email: String, password: String) async {
        isLoading = true
        authError = nil
        do {
            let response = try await supabase.auth.signUp(email: email, password: password)
            print("Signed up user: \(response.user.id)")
            
            // Supabase automatically signs in after sign up if email confirmation is disabled.
            // If it requires email confirmation, the session might remain nil until confirmed.
        } catch {
            authError = error.localizedDescription
            print("SignUp Error: \(error)")
        }
        isLoading = false
    }
    
    func signIn(email: String, password: String) async {
        isLoading = true
        authError = nil
        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            print("Signed in user: \(session.user.id)")
        } catch {
            authError = error.localizedDescription
            print("SignIn Error: \(error)")
        }
        isLoading = false
    }
    
    func signInWithApple() async {
        isLoading = true
        authError = nil
        do {
            let appleSignInManager = AppleSignInManager()
            let result = try await appleSignInManager.startSignIn()
            
            // Result is "idToken|nonce"
            let components = result.components(separatedBy: "|")
            guard components.count == 2 else {
                throw NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid token result format."])
            }
            
            let idToken = components[0]
            let nonce = components[1]
            
            _ = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            
            print("Successfully signed in with Apple via native sheet.")
        } catch let error as ASAuthorizationError where error.code == .canceled {
            authError = nil   // user closed the sheet
        } catch let error as ASAuthorizationError {
            authError = "Apple sign-in couldn't start. Make sure you're signed in to an Apple Account in Settings."
            print("Apple SignIn Error: \(error)")
        } catch {
            authError = error.localizedDescription
            print("Apple SignIn Error: \(error)")
        }
        isLoading = false
    }
    
    func signInWithGoogle() async {
        isLoading = true
        authError = nil
        do {
            // Presents an ASWebAuthenticationSession and exchanges the callback for a session,
            // so the auth state listener fires as soon as the user finishes in the sheet.
            try await supabase.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "com.omsilwal.NutriCorePrimal://login-callback")
            )
        } catch {
            // Cancelling the sheet is not an error worth surfacing.
            if (error as NSError).code != 1 {
                authError = error.localizedDescription
            }
            print("Google SignIn Error: \(error)")
        }
        isLoading = false
    }

    func continueAsGuest() {
        authError = nil
        setGuest(true)
    }

    private func setGuest(_ value: Bool) {
        isGuest = value
        UserDefaults.standard.set(value, forKey: "isGuest")
    }

    var currentEmail: String? { supabase.auth.currentUser?.email }

    /// Starts an email change; Supabase emails a confirmation link to the new address.
    /// Returns an error message, or nil on success.
    func updateEmail(_ email: String) async -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.contains("@"), trimmed.contains(".") else { return "Enter a valid email address." }
        do {
            _ = try await supabase.auth.update(user: UserAttributes(email: trimmed))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Permanently deletes the account on the server (and cancels billing), then clears local state.
    /// Returns an error message, or nil on success.
    func deleteAccount() async -> String? {
        do {
            try await supabase.functions.invoke("delete-account")
        } catch {
            return "Couldn't delete your account. Check your connection and try again."
        }
        try? await supabase.auth.signOut()
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "accountDisplayName")
        SubscriptionManager.shared.clearOnSignOut()
        SocialService.shared.reset()
        return nil
    }

    func signOut() async {
        // A guest has no session; just return to the login screen and keep their local data.
        if isGuest {
            setGuest(false)
            return
        }
        do {
            try await supabase.auth.signOut()
            
            // Wipe user defaults so the next user starts fresh
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
            SubscriptionManager.shared.clearOnSignOut()
            SocialService.shared.reset()
            UserDefaults.standard.removeObject(forKey: "accountDisplayName")
            
        } catch {
            print("SignOut Error: \(error)")
        }
    }
}
