import SwiftUI
import SwiftData
import Supabase

@main
struct NutriCoreApp: App {
    init() {
        // SwiftData keeps its store in Application Support (inside the App Group, shared with the widgets). On a
        // fresh install that folder doesn't exist yet, and Core Data logs a page of errors before recovering, so
        // make it first.
        let fm = FileManager.default
        let folders = [fm.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
                           .appendingPathComponent("Library/Application Support"),
                       fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first]
        for case let folder? in folders { try? fm.createDirectory(at: folder, withIntermediateDirectories: true) }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // UI tests and screenshots: straight to the tabs on the sample store (`-uiTestTabs`, optionally
            // `-uiTestTab data`). Compiled out of release builds.
            if UITestLaunch.freshStart {
                root
            } else if let tab = UITestLaunch.tab {
                ContentView(initialTab: tab).modelContainer(VitalisPreviewData.container).preferredColorScheme(.dark)
            } else {
                root
            }
            #else
            root
            #endif
        }
        .modelContainer(for: [
            MealEntry.self, UserProfile.self, DailyHydration.self,
            SourceBatch.self, Supplier.self, BiomarkerReading.self,
            OutcomeLog.self, SunSession.self, Goal.self,
        ])
    }

    private var root: some View {
        RootView()
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                Task { try? await supabase.auth.session(from: url) }
            }
    }
}

#if DEBUG
enum UITestLaunch {
    /// `-uiTestFresh`: forget sign-in, onboarding, consent and the guest paywall, so the first-run path shows.
    static let freshStart: Bool = {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestFresh") else { return false }
        // Written as explicit "off" values (not removed), so nothing in another defaults domain can show through.
        let defaults = UserDefaults.standard
        for key in ["isGuest", "hasCompletedOnboarding", "guestDismissedPaywall"] { defaults.set(false, forKey: key) }
        defaults.set(0, forKey: "legalAcceptedVersion")
        defaults.removeObject(forKey: "legalAcceptedAt")
        return true
    }()

    static var tab: AppTab? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTestTabs") else { return nil }
        if let i = args.firstIndex(of: "-uiTestTab"), i + 1 < args.count {
            return ["home": .home, "map": .map, "scan": .scan, "data": .data, "profile": .profile][args[i + 1]] ?? .home
        }
        return .home
    }
}
#endif

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
