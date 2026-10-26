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
    @AppStorage(AuthManager.guestDismissedPaywallKey) private var guestDismissedPaywall = false
    @StateObject private var subManager = SubscriptionManager.shared
    @State private var legalAccepted = LegalAcceptance.isCurrent

    // ── DEV BYPASS ──────────────────────────────────────────────────────────
    // Set this to `true` to skip login & onboarding during development.
    // Set back to `false` before shipping.
    private let DEV_BYPASS_AUTH = false
    // ────────────────────────────────────────────────────────────────────────

    var body: some View {
        ZStack {
            content
            LaunchHandoff()
        }
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
        } else if (authManager.isAuthenticated || authManager.isGuest) && !legalAccepted {
            // Nothing past the login screen is usable until the current policies are accepted.
            LegalConsentView { withAnimation(.smooth) { legalAccepted = true } }
        } else if authManager.isGuest {
            // Guests skip profile setup (it stays available from the Profile tab). They see the paywall once,
            // since an App Store subscription doesn't need an account, and can dismiss it with "Not now".
            if subManager.isSubscribed || guestDismissedPaywall {
                ContentView()
            } else {
                PaywallView(onNotNow: { guestDismissedPaywall = true })
            }
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
