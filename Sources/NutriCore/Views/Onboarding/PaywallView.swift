import SwiftUI
import CoreMotion

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
                        VitalisCard(name: SocialService.shared.myProfile?.name ?? "Your card", isPro: subManager.isSubscribed)
                            .padding(.vertical, 10)
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

// MARK: - Vitalis card

/// The phone's tilt for the card: roll and pitch from gravity, eased, as −1…1 (0 held upright, facing you).
@MainActor
final class CardTilt: ObservableObject {
    @Published private(set) var roll: Double = 0
    @Published private(set) var pitch: Double = 0
    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive, !UIAccessibility.isReduceMotionEnabled else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let g = data?.gravity else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let r = max(-1, min(1, g.x * 1.6))
                let p = max(-1, min(1, (g.y + 0.72) * 1.8))
                // Ease so the card glides rather than shakes.
                self.roll += (r - self.roll) * 0.14
                self.pitch += (p - self.pitch) * 0.14
            }
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}

/// A transparent glass membership card that says VITALIS, with light refracting inside it and an iridescent rim.
/// It turns in 3D with the phone: tilt it and the card rotates, its sheen slides across and the colours inside shift.
/// Still under Reduce Motion.
struct VitalisCard: View {
    let name: String
    let isPro: Bool
    /// Bottom-right action label ("See plans", "Manage").
    var action: String? = nil
    @StateObject private var tilt = CardTilt()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let roll = reduceMotion ? 0 : tilt.roll, pitch = reduceMotion ? 0 : tilt.pitch
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        ZStack {
            // Glass body.
            if reduceTransparency {
                shape.fill(Color(hex: "#141614"))
            } else {
                shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                shape.fill(Color(hex: "#0A0B0A").opacity(0.28))
                // Light refracting inside the glass: soft warm and cool blooms that drift against the tilt.
                ZStack {
                    Ellipse().fill(Color(hex: "#F37E61").opacity(0.55)).frame(width: 190, height: 120)
                        .offset(x: 90 - roll * 60, y: -30 + pitch * 30)
                    Ellipse().fill(Color(hex: "#5FB7C4").opacity(0.45)).frame(width: 200, height: 110)
                        .offset(x: -100 - roll * 40, y: 60 + pitch * 24)
                    Ellipse().fill(Color(hex: "#D7F25A").opacity(0.28)).frame(width: 140, height: 80)
                        .offset(x: -10 + roll * 50, y: -70 - pitch * 20)
                }
                // Fill the whole card before blurring, so the blooms fade out softly instead of in a box.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: 40)
                .compositingGroup()
                .opacity(0.9)
                .clipShape(shape)
                // Specular band that slides across as the card turns.
                LinearGradient(stops: [.init(color: .clear, location: 0.25 + roll * 0.2),
                                       .init(color: .white.opacity(0.22), location: 0.45 + roll * 0.2),
                                       .init(color: .clear, location: 0.62 + roll * 0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(shape)
                    .blendMode(.plusLighter)
            }

            content.padding(22)
        }
        .aspectRatio(1.586, contentMode: .fit)
        .overlay {
            // Iridescent rim, its colours turning with the tilt.
            shape.strokeBorder(AngularGradient(colors: [.white.opacity(0.7), Color(hex: "#F37E61").opacity(0.6),
                                                        Color(hex: "#D7F25A").opacity(0.5), Color(hex: "#5FB7C4").opacity(0.6),
                                                        Color(hex: "#9B7BE0").opacity(0.5), .white.opacity(0.7)],
                                               center: .center, angle: .degrees(roll * 90 + pitch * 40)),
                               lineWidth: 1.2)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, x: -roll * 10, y: 18 + pitch * 6)
        .rotation3DEffect(.degrees(pitch * -12), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
        .rotation3DEffect(.degrees(roll * 16), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPro ? "Vitalis Pro membership card, \(name)" : "Vitalis Pro, \(name)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(name).font(.ui(size: 17, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                Spacer()
                HStack(spacing: 6) {
                    AlgizMark().fill(Color.white).frame(width: 12, height: 16)
                    Text("VITALIS").font(.display(22)).tracking(-0.4).foregroundColor(.white)
                }
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Pro").font(.display(44)).foregroundColor(.white)
                Text(isPro ? "Member" : "Membership").font(.ui(size: 15, weight: .semibold)).foregroundColor(.white.opacity(0.8))
            }
            Text("Scanner · full nutrients · Health sync").font(.ui(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.7))
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            HStack {
                Text(isPro ? "ACTIVE" : "MEMBER " + String(Calendar.current.component(.year, from: .now)))
                    .font(.mono(12, .semibold)).tracking(1.2).foregroundColor(.white.opacity(0.85))
                Spacer()
                if let action {
                    HStack(spacing: 6) {
                        Text(action).font(.ui(size: 15, weight: .semibold))
                        Image(systemName: "arrow.up.right").font(.ui(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}
