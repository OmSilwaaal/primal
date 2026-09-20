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
        .modelContainer(for: [MealEntry.self, UserProfile.self, FastingState.self, DailyHydration.self])
    }
}

// MARK: - Root routing view
struct RootView: View {
    @StateObject private var authManager = AuthManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var subManager = SubscriptionManager.shared

    var body: some View {
        if authManager.isAuthenticated {
            if hasCompletedOnboarding {
                if subManager.isSubscribed {
                    ContentView()
                } else {
                    PaywallView()
                }
            } else {
                ProfileSetupView()
            }
        } else {
            OnboardingView()
        }
    }
}
