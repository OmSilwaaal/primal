import SwiftUI

struct PaywallView: View {
    @StateObject private var subManager = SubscriptionManager.shared
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedPlan: SubscriptionManager.Plan = .annual

    var body: some View {
        ZStack {
            AppBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.section) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Membership").serifCaps(11).foregroundColor(.ncPrimary.opacity(0.8))
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
                                PlanRow(plan: plan, isSelected: selectedPlan == plan) { selectedPlan = plan }
                            }
                        }
                    }

                    VStack(spacing: 16) {
                        Button {
                            Task { await subManager.subscribe(to: selectedPlan) }
                        } label: {
                            ZStack {
                                if subManager.isWorking { ProgressView().tint(.ncOnPrimary) }
                                else { Text("Continue · \(selectedPlan.priceLabel)") }
                            }
                        }
                        .buttonStyle(.vitalis)
                        .disabled(subManager.isWorking)

                        if let error = subManager.errorMessage {
                            Text(error).font(.system(size: 13)).foregroundColor(.ncError).multilineTextAlignment(.center)
                        }

                        HStack(spacing: 28) {
                            Button("Restore") { Task { await subManager.restorePurchases() } }
                            Button("Sign out") { Task { await authManager.signOut() } }
                        }
                        .spacedCaps(11)
                        .foregroundColor(.ncPrimary.opacity(0.8))
                        .disabled(subManager.isWorking)

                        Text("Payments are processed securely by Stripe. Your subscription renews automatically until you cancel in Settings.")
                            .font(.serif(12)).italic().foregroundColor(.ncSecondary)
                            .multilineTextAlignment(.center)

                        LegalLinks()

                        #if DEBUG
                        Button("DEBUG: skip paywall") { subManager.debugUnlock() }
                            .font(.system(size: 12)).foregroundColor(.ncSecondary.opacity(0.6))
                        #endif
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct PlanRow: View {
    let plan: SubscriptionManager.Plan
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
                            if plan == .annual { Tag(text: "Save 40%", color: .ncPrimary) }
                        }
                        Text(plan.detail).font(.system(size: 13)).foregroundColor(.ncSecondary)
                    }
                    Spacer()
                    Text(plan.priceLabel).font(.metric(15)).foregroundColor(.ncPrimary)
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
