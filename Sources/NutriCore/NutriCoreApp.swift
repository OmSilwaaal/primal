import SwiftUI
import SwiftData

@main
struct NutriCoreApp: App {
    @AppStorage("isWhiteTheme") private var isWhiteTheme = false
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(isWhiteTheme ? .light : .dark)
                .animation(.easeInOut(duration: 0.4), value: isWhiteTheme)
        }
        .modelContainer(for: [MealEntry.self, UserProfile.self])
    }
}

// MARK: - Root routing view
struct RootView: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        if authManager.isAuthenticated {
            ContentView()
        } else {
            OnboardingView()
        }
    }
}
