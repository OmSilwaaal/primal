import Foundation
import Supabase
import Combine

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
    
    private var authStateListener: Task<Void, Never>?
    
    init() {
        startListeningToAuthState()
    }
    
    private func startListeningToAuthState() {
        Task {
            for await (event, session) in await supabase.auth.authStateChanges {
                self.isAuthenticated = (session != nil)
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
    
    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            print("SignOut Error: \(error)")
        }
    }
}
