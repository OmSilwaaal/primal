import SwiftUI
import SwiftData
import Supabase

@main
struct NutriCoreApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    Task { try? await supabase.auth.session(from: url) }
                }
        }
        .modelContainer(for: [
            MealEntry.self, UserProfile.self, DailyHydration.self,
            SourceBatch.self, Supplier.self, BiomarkerReading.self,
            OutcomeLog.self, SunSession.self,
        ])
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
    private let DEV_BYPASS_AUTH = false
    // ────────────────────────────────────────────────────────────────────────

    var body: some View {
        content
            .task(id: authManager.isAuthenticated) {
                // The subscription belongs to the Apple ID, so check it whether or not anyone is signed in.
                await subManager.refreshEntitlement()
                if authManager.isAuthenticated {
                    await SocialService.shared.bootstrap()
                } else {
                    SocialService.shared.reset()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if DEV_BYPASS_AUTH {
            ContentView()
        } else if authManager.isGuest {
            // Skip goes straight in: no setup, and no paywall since guests can't subscribe without an account.
            // Profile setup stays available from the Profile tab.
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
