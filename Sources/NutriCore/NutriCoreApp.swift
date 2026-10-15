import SwiftUI
import SwiftData
import Supabase
import StripePaymentSheet

@main
struct NutriCoreApp: App {
    @AppStorage("isWhiteTheme") private var isWhiteTheme = false
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(isWhiteTheme ? .light : .dark)
                .animation(.easeInOut(duration: 0.4), value: isWhiteTheme)
                .onOpenURL { url in
                    // Stripe redirects (3-D Secure, bank auth) come back through our URL scheme too.
                    if StripeAPI.handleURLCallback(with: url) { return }
                    Task { try? await supabase.auth.session(from: url) }
                }
        }
        .modelContainer(for: [MealEntry.self, UserProfile.self, FastingState.self, DailyHydration.self])
    }
}

// MARK: - Root routing view
struct RootView: View {
    @StateObject private var authManager = AuthManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var subManager = SubscriptionManager.shared

    // ── DEV BYPASS ──────────────────────────────────────────────────────────
    // Set this to `true` to skip login & onboarding during development.
    // Set back to `false` before shipping.
    private let DEV_BYPASS_AUTH = true
    // ────────────────────────────────────────────────────────────────────────

    var body: some View {
        content
            .task(id: authManager.isAuthenticated) {
                if authManager.isAuthenticated { await subManager.refreshEntitlement() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if DEV_BYPASS_AUTH {
            ContentView()
        } else if authManager.isAuthenticated {
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
