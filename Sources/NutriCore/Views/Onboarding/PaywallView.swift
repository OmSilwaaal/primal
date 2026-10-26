import SwiftUI

struct PaywallView: View {
    @StateObject private var subManager = SubscriptionManager.shared
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedPlan: SubscriptionManager.Plan = .annual
    /// Guests only: dismisses the paywall and continues into the app.
    var onNotNow: (() -> Void)? = nil

    var body: some View {
        ZStack {
            AppBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.section) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            AlgizMark().fill(Color.ncPrimary).frame(width: 14, height: 18).accessibilityHidden(true)
                            Text("Membership").serifCaps(11).foregroundColor(.ncPrimary.opacity(0.8))
                        }
                        Wordmark(text: "VITALIS PRO", size: 64)
                        Text("Everything Vitalis measures, with nothing held back.")
                            .font(.serif(19)).foregroundColor(.ncPrimary).lineSpacing(3)
                    }
                    .padding(.top, 24)

                    RawCard(title: "Included", index: "01") {
                        VStack(spacing: 0) {
                            OnboardingFeatureRow(icon: "A", tint: .ncPrimary, tintBg: .clear,
                                                 label: "Food scanner", sub: "Barcode and AI photo logging")
                            OnboardingFeatureRow(icon: "B", tint: .ncPrimary, tintBg: .clear,
                                                 label: "Raw-food safety", sub: "Risk score, freezer log, recalls")
                            OnboardingFeatureRow(icon: "C", tint: .ncPrimary, tintBg: .clear,
                                                 label: "Full nutrient tracking", sub: "Liver budget, gaps, biomarkers")
                            OnboardingFeatureRow(icon: "D", tint: .ncPrimary, tintBg: .clear,
                                                 label: "Apple Health sync", sub: "Activity, daylight, body measures")
                        }
                    }

                    RawCard(title: "Plan", index: "02") {
                        VStack(spacing: 0) {
                            ForEach(SubscriptionManager.Plan.allCases.reversed()) { plan in
                                PlanRow(plan: plan,
                                        price: subManager.priceLabel(for: plan),
                                        detail: subManager.detail(for: plan),
                                        savings: plan == .annual ? subManager.annualSavingsPercent : nil,
                                        isSelected: selectedPlan == plan) { selectedPlan = plan }
                            }
                        }
                    }

                    VStack(spacing: 16) {
                        Button {
                            Task { await subManager.subscribe(to: selectedPlan) }
                        } label: {
                            ZStack {
                                let price = subManager.priceLabel(for: selectedPlan)
                                if subManager.isWorking { ProgressView().tint(.ncOnPrimary) }
                                else { Text(price.isEmpty ? "Continue" : "Continue · \(price)") }
                            }
                        }
                        .buttonStyle(.vitalis)
                        .disabled(subManager.isWorking || subManager.products.isEmpty)

                        if let error = subManager.errorMessage {
                            Text(error).font(.ui(size: 13)).foregroundColor(.ncError).multilineTextAlignment(.center)
                        }

                        HStack(spacing: 28) {
                            Button("Restore") { Task { await subManager.restorePurchases() } }
                            // A guest has no account to sign out of; this takes them to the login screen.
                            Button(authManager.isGuest ? "Log in" : "Sign out") { Task { await authManager.signOut() } }
                        }
                        .spacedCaps(11)
                        .foregroundColor(.ncPrimary.opacity(0.8))
                        .disabled(subManager.isWorking)

                        // Apple requires this disclosure next to an auto-renewing subscription.
                        Text("Payment is charged to your Apple ID when you confirm. The subscription renews automatically at the same price unless you cancel at least 24 hours before the end of the current period. Manage or cancel in your Apple ID settings.")
                            .font(.serif(12)).italic().foregroundColor(.ncSecondary)
                            .multilineTextAlignment(.center)

                        LegalLinks()

                        #if DEBUG
                        Button("DEBUG: skip paywall") { subManager.debugUnlock() }
                            .font(.ui(size: 12)).foregroundColor(.ncSecondary.opacity(0.6))
                        #endif
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, 32)
            }
        }
        // Same place and style as Skip on the login screen, so guests can always see the way past it.
        // A top inset rather than an overlay, so the paywall never slides underneath it at large text sizes.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let onNotNow {
                HStack {
                    Spacer()
                    Button(action: onNotNow) {
                        Text("Not now")
                            .font(.ui(size: 15)).foregroundColor(.ncPrimary.opacity(0.8))
                            .padding(.horizontal, 20)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(subManager.isWorking)
                }
            }
        }
        .task { if subManager.products.isEmpty { await subManager.loadProducts() } }
    }
}

private struct PlanRow: View {
    let plan: SubscriptionManager.Plan
    let price: String
    let detail: String
    let savings: Int?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Rectangle()
                        .fill(isSelected ? Color.ncPrimary : Color.clear)
                        .frame(width: 16, height: 16)
                        .overlay(Rectangle().stroke(Color.ncPrimary.opacity(isSelected ? 1 : 0.4), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(plan.title).font(.serif(21)).foregroundColor(.ncPrimary)
                            if let savings { Tag(text: "Save \(savings)%", color: .ncPrimary) }
                        }
                        Text(detail).font(.ui(size: 13)).foregroundColor(.ncSecondary)
                    }
                    Spacer()
                    if price.isEmpty {
                        VitalisSpinner(size: 22)
                    } else {
                        Text(price).font(.metric(15)).foregroundColor(.ncPrimary)
                    }
                }
                .padding(.vertical, 18)
                Hairline(opacity: 0.12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PaywallFeatureRow: View {
    let icon: String
    let tint: Color
    let tintBg: Color
    let label: String
    let sub: String
    var body: some View {
        OnboardingFeatureRow(icon: icon, tint: tint, tintBg: tintBg, label: label, sub: sub)
    }
}
