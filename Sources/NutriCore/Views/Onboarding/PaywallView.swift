import SwiftUI

/// Vitalis Pro, in the app's glass: what's included, the two plans as glass capsules, how payment works, and the
/// subscribe button. Payment goes through the App Store, so it uses whatever the Apple Account pays with — Apple
/// Card, Apple Pay cards, any credit or debit card, PayPal or carrier billing where offered, or Apple Account balance.
struct PaywallView: View {
    @StateObject private var subManager = SubscriptionManager.shared
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedPlan: SubscriptionManager.Plan = .annual
    /// Dismisses the paywall: "Not now" for guests at launch, "Close" when opened from inside the app.
    var onNotNow: (() -> Void)? = nil
    /// Sign out / Log in under the button; off when the paywall is opened from inside the app.
    var showsAccountButton = true

    var body: some View {
        ZStack {
            AppBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Bento.gap) {
                    // Title
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            AlgizMark().fill(Mono.text).frame(width: 13, height: 17).accessibilityHidden(true)
                            Text("Membership").font(.bentoLabel).foregroundColor(Mono.label)
                        }
                        Text("Vitalis Pro").font(.display(40)).foregroundColor(Mono.text)
                            .accessibilityAddTraits(.isHeader)
                        Text("Everything Vitalis measures, with nothing held back.")
                            .font(.bentoBody).foregroundColor(Mono.label)
                    }
                    .padding(.top, 20).padding(.bottom, 6)

                    // Included
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Included").font(.bentoLabel).foregroundColor(Mono.label).padding(.bottom, 4)
                        feature("barcode.viewfinder", "Food scanner", "Barcode and AI photo logging", first: true)
                        feature("shield.lefthalf.filled", "Raw-food safety", "Risk score, freezer log, recalls")
                        feature("chart.bar", "Full nutrient tracking", "Liver budget, gaps, biomarkers")
                        feature("heart", "Apple Health sync", "Activity, daylight, body measures")
                        feature("app.badge", "App icons", "Nine icons for your Home Screen")
                    }
                    .bentoTile(padding: 18, art: .leaf)

                    // Plans
                    VStack(spacing: 10) {
                        ForEach(SubscriptionManager.Plan.allCases.reversed()) { plan in
                            PlanRow(plan: plan,
                                    price: subManager.priceLabel(for: plan),
                                    detail: subManager.detail(for: plan),
                                    savings: plan == .annual ? subManager.annualSavingsPercent : nil,
                                    isSelected: selectedPlan == plan) {
                                Haptics.selection()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { selectedPlan = plan }
                            }
                        }
                    }

                    // Payment
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "creditcard").font(.ui(size: 15, weight: .medium)).foregroundColor(Mono.text)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Pay in the app with your Apple Account").font(.ui(size: 14, weight: .semibold))
                                .foregroundColor(Mono.text)
                            Text("Apple Card, any credit or debit card, PayPal where available, or your Apple Account balance. Confirm with Face ID; Vitalis never sees your card.")
                                .font(.ui(size: 12)).foregroundColor(Mono.label)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .bentoTile(padding: 16)
                    .accessibilityElement(children: .combine)

                    VStack(spacing: 14) {
                        Button {
                            Task { await subManager.subscribe(to: selectedPlan) }
                        } label: {
                            ZStack {
                                let price = subManager.priceLabel(for: selectedPlan)
                                if subManager.isWorking { ProgressView().tint(Mono.onWhite) }
                                else { Text(price.isEmpty ? "Continue" : "Continue · \(price)") }
                            }
                        }
                        .buttonStyle(.bentoPrimary)
                        .disabled(subManager.isWorking || subManager.products.isEmpty)

                        if let error = subManager.errorMessage {
                            Text(error).font(.ui(size: 13)).foregroundColor(.ncEmber).multilineTextAlignment(.center)
                        }

                        HStack(spacing: 10) {
                            Button("Restore purchases") { Task { await subManager.restorePurchases() } }
                                .buttonStyle(BentoCapsuleButtonStyle(solid: false, height: 40))
                            if showsAccountButton {
                                // A guest has no account to sign out of; this takes them to the login screen.
                                Button(authManager.isGuest ? "Log in" : "Sign out") { Task { await authManager.signOut() } }
                                    .buttonStyle(BentoCapsuleButtonStyle(solid: false, height: 40))
                            }
                        }
                        .disabled(subManager.isWorking)

                        // Apple requires this disclosure next to an auto-renewing subscription.
                        Text("Payment is charged to your Apple Account when you confirm. The subscription renews automatically at the same price unless you cancel at least 24 hours before the end of the current period. Manage or cancel in your Apple Account settings.")
                            .font(.ui(size: 11)).foregroundColor(Mono.label)
                            .multilineTextAlignment(.center)

                        LegalLinks()

                        #if DEBUG
                        Button("DEBUG: skip paywall") { subManager.debugUnlock() }
                            .font(.ui(size: 12)).foregroundColor(Mono.label.opacity(0.6))
                        #endif
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
                .padding(.horizontal, Bento.margin)
                .padding(.bottom, 32)
            }
            .glassLightFollowsScroll()
        }
        // Same place as Skip on the login screen, so guests can always see the way past it. A top inset rather than
        // an overlay, so the paywall never slides underneath it at large text sizes.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let onNotNow {
                HStack {
                    Spacer()
                    Button(showsAccountButton ? "Not now" : "Close", action: onNotNow)
                        .buttonStyle(BentoCapsuleButtonStyle(solid: false, height: 40))
                        .fixedSize()
                        .padding(.horizontal, Bento.margin).padding(.top, 6)
                        .disabled(subManager.isWorking)
                }
            }
        }
        .task { if subManager.products.isEmpty { await subManager.loadProducts() } }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String, first: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.ui(size: 14, weight: .medium)).foregroundColor(Mono.text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                Text(detail).font(.ui(size: 12)).foregroundColor(Mono.label)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 54)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A plan as a glass capsule card: a radio dot, the name and its detail, the price; the selected one gets a solid
/// rim and a filled dot.
private struct PlanRow: View {
    let plan: SubscriptionManager.Plan
    let price: String
    let detail: String
    let savings: Int?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                Circle()
                    .strokeBorder(Mono.text.opacity(isSelected ? 1 : 0.4), lineWidth: 1.5)
                    .background(Circle().fill(Mono.text).padding(5).opacity(isSelected ? 1 : 0))
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title).font(.ui(size: 17, weight: .semibold)).foregroundColor(Mono.text)
                        if let savings {
                            Text("Save \(savings)%").font(.mono(10, .semibold)).textCase(.uppercase)
                                .foregroundColor(Mono.onWhite)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Color.ncMoss))
                        }
                    }
                    Text(detail).font(.ui(size: 12)).foregroundColor(Mono.label)
                }
                Spacer(minLength: 8)
                if price.isEmpty {
                    ProgressView().tint(Mono.text)
                } else {
                    Text(price).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text).fixedSize()
                }
            }
            .padding(.horizontal, 18).frame(minHeight: 72)
            .liquidGlassPanel(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Mono.text.opacity(isSelected ? 0.85 : 0), lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
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
