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

/// The card's tilt, −1…1 on each axis (0 = facing you). Follows the phone's tilt from Core Motion, or a finger /
/// pointer dragged across the card while it's held. Eased every frame by one display link, so both feel smooth.
@MainActor
final class CardTilt: ObservableObject {
    @Published private(set) var roll: Double = 0
    @Published private(set) var pitch: Double = 0
    private var target = (roll: 0.0, pitch: 0.0)
    private var dragTarget: (roll: Double, pitch: Double)?
    private let motion = CMMotionManager()
    private var link: CADisplayLink?

    func start() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        if motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive {
            motion.deviceMotionUpdateInterval = 1.0 / 60
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let g = data?.gravity else { return }
                MainActor.assumeIsolated {
                    self?.target = (max(-1, min(1, g.x * 1.6)), max(-1, min(1, (g.y + 0.72) * 1.8)))
                }
            }
        }
        guard link == nil else { return }
        let link = CADisplayLink(target: CardTiltProxy(self), selector: #selector(CardTiltProxy.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        link?.invalidate()
        link = nil
    }

    /// A point over the card in unit space (0…1); nil when the finger lifts.
    func drag(to unit: CGPoint?) {
        dragTarget = unit.map { (Double($0.x - 0.5) * 2, Double($0.y - 0.5) * 2) }
    }

    fileprivate func tick() {
        let t = dragTarget ?? target
        // Critically damped easing: quick to follow, no wobble. A held finger follows a little tighter.
        let k = dragTarget == nil ? 0.10 : 0.2
        let r = roll + (t.roll - roll) * k, p = pitch + (t.pitch - pitch) * k
        guard abs(r - roll) > 0.0003 || abs(p - pitch) > 0.0003 else { return }
        roll = r; pitch = p
    }
}

private final class CardTiltProxy {
    weak var tilt: CardTilt?
    init(_ tilt: CardTilt) { self.tilt = tilt }
    @objc func tick() { MainActor.assumeIsolated { tilt?.tick() } }
}

/// How a member pays. All of them go through the App Store (Apple's payment sheet confirms the purchase), so the
/// choice here is shown on the card and named on the button; the charge goes to whatever the Apple Account uses.
enum PaymentMethod: String, CaseIterable, Identifiable {
    case applePay, card, paypal, balance
    var id: Self { self }

    var title: String {
        switch self {
        case .applePay: "Apple Pay"
        case .card: "Credit or debit card"
        case .paypal: "PayPal"
        case .balance: "Apple Account balance"
        }
    }
    var short: String {
        switch self {
        case .applePay: "Apple Pay"
        case .card: "Card"
        case .paypal: "PayPal"
        case .balance: "Balance"
        }
    }
    var icon: String {
        switch self {
        case .applePay: "apple.logo"
        case .card: "creditcard"
        case .paypal: "p.circle"
        case .balance: "giftcard"
        }
    }
}

/// The mark printed bottom right on the card for the chosen payment method.
private struct PaymentMark: View {
    let method: PaymentMethod

    var body: some View {
        Group {
            switch method {
            case .applePay:
                HStack(spacing: 2) {
                    Image(systemName: "apple.logo").font(.system(size: 17, weight: .semibold))
                    Text("Pay").font(.system(size: 19, weight: .semibold))
                }
            case .card:
                // A VISA-style wordmark (set in type; Visa's own artwork isn't bundled).
                Text("VISA").font(.system(size: 22, weight: .black)).italic().tracking(-0.5)
            case .paypal:
                Text("PayPal").font(.system(size: 19, weight: .heavy)).italic()
            case .balance:
                HStack(spacing: 6) {
                    Image(systemName: "giftcard.fill").font(.system(size: 16, weight: .semibold))
                    Text("BALANCE").font(.mono(11, .semibold)).tracking(0.8)
                }
            }
        }
        .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.75)], startPoint: .top, endPoint: .bottom))
        .shadow(color: .black.opacity(0.25), radius: 0.6, y: 0.6)
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.85)), removal: .opacity))
        .id(method)
    }
}

/// The Vitalis card, after the Apple Card: a clean, clear frosted-glass slab with a debossed rune top left, a metal
/// chip, the member's name in quiet grey-white and the payment mark bottom right. It turns in 3D with the phone, or
/// with a finger or the pointer dragged across it, light refracting through it. Still under Reduce Motion.
struct VitalisCard: View {
    let name: String
    let isPro: Bool
    var method: PaymentMethod? = nil
    /// Printed as VALID THRU MM/YY: when the membership runs until.
    var expires: Date? = nil
    @StateObject private var tilt = CardTilt()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let roll = reduceMotion ? 0 : tilt.roll, pitch = reduceMotion ? 0 : tilt.pitch
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        GeometryReader { geo in
            ZStack {
                // A card is under 1 mm thick: the faintest edge on the side turning away.
                shape.fill(Color.white.opacity(0.3))
                    .offset(x: -roll * 1.4, y: -pitch * 1.1)
                    .opacity(reduceTransparency ? 0 : 0.6)

                if reduceTransparency {
                    shape.fill(Color(hex: "#2A2C2A"))
                } else {
                    // Clear frosted glass: very light blur, a touch of white like the Apple Card's titanium white.
                    shape.fill(.ultraThinMaterial).opacity(0.35).environment(\.colorScheme, .light)
                    shape.fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.05)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    // Light passing through: a soft warm-to-cool refraction that slides as the card turns.
                    ZStack {
                        Ellipse().fill(Color(hex: "#FFE7B8").opacity(0.35)).frame(width: 220, height: 120)
                            .offset(x: 70 - roll * 80, y: -40 + pitch * 40)
                        Ellipse().fill(Color(hex: "#BDE6FF").opacity(0.3)).frame(width: 220, height: 120)
                            .offset(x: -90 - roll * 60, y: 60 + pitch * 30)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: 40)
                    .compositingGroup()
                    .clipShape(shape)
                    .blendMode(.plusLighter)
                    // A thin prismatic streak where the light splits at the glass.
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.34 + roll * 0.25),
                        .init(color: Color(hex: "#FFB199").opacity(0.18), location: 0.40 + roll * 0.25),
                        .init(color: Color(hex: "#E9FF9E").opacity(0.15), location: 0.43 + roll * 0.25),
                        .init(color: Color(hex: "#9EE3FF").opacity(0.18), location: 0.46 + roll * 0.25),
                        .init(color: .clear, location: 0.52 + roll * 0.25),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(shape).blendMode(.plusLighter)
                    // The sheen sweeping across, like light on the Apple Card's surface.
                    LinearGradient(stops: [.init(color: .clear, location: 0.1 + roll * 0.3),
                                           .init(color: .white.opacity(0.3), location: 0.28 + roll * 0.3),
                                           .init(color: .clear, location: 0.46 + roll * 0.3)],
                                   startPoint: .top, endPoint: .bottom)
                        .clipShape(shape).blendMode(.plusLighter)
                }

                content(size: geo.size)
                    .padding(geo.size.width * 0.07)
                    .offset(x: roll * 2.5, y: pitch * 2)
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.2), .white.opacity(0.5)],
                                                  startPoint: UnitPoint(x: 0.2 - roll * 0.3, y: 0),
                                                  endPoint: UnitPoint(x: 0.8 - roll * 0.3, y: 1)),
                                   lineWidth: 1)
            }
            .contentShape(shape)
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    tilt.drag(to: CGPoint(x: value.location.x / max(1, geo.size.width),
                                          y: value.location.y / max(1, geo.size.height)))
                }
                .onEnded { _ in tilt.drag(to: nil) })
        }
        .aspectRatio(1.586, contentMode: .fit)
        .shadow(color: .black.opacity(0.3), radius: 18, x: -roll * 10, y: 14 + pitch * 6)
        .rotation3DEffect(.degrees(pitch * -16), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(roll * 20), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: method)
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vitalis \(isPro ? "Pro member card" : "card"), \(name)\(method.map { ", paying with \($0.title)" } ?? "")\(expires.map { ", valid through \($0.formatted(.dateTime.month(.wide).year()))" } ?? "")")
    }

    private func content(size: CGSize) -> some View {
        let w = size.width
        return ZStack(alignment: .topLeading) {
            // Debossed rune, like the Apple Card's logo: a lit lower edge and a shadowed upper one.
            ZStack {
                AlgizMark().fill(Color.black.opacity(0.18)).offset(y: -0.8)
                AlgizMark().fill(Color.white.opacity(0.55)).offset(y: 0.8)
                AlgizMark().fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.7)],
                                                startPoint: .top, endPoint: .bottom))
            }
            .frame(width: w * 0.075, height: w * 0.098)

            // Metal chip, right of centre.
            CardChip()
                .frame(width: w * 0.13, height: w * 0.1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(y: -w * 0.04)

            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                if let expires {
                    HStack(alignment: .center, spacing: 6) {
                        Text("VALID\nTHRU").font(.mono(7, .semibold)).lineSpacing(-1).multilineTextAlignment(.trailing)
                            .foregroundColor(.white.opacity(0.75))
                        Text(expires.formatted(.dateTime.month(.twoDigits).year(.twoDigits)))
                            .font(.mono(15, .semibold)).foregroundColor(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.3), radius: 0.8, y: 0.6)
                            .contentTransition(.numericText())
                    }
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
                }
                Text(name).font(.system(size: w * 0.05, weight: .medium)).foregroundColor(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.3), radius: 0.8, y: 0.6)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(alignment: .lastTextBaseline) {
                    Text(isPro ? "VITALIS PRO · ACTIVE" : "VITALIS PRO").font(.mono(10, .semibold)).tracking(1.4)
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                    if let method { PaymentMark(method: method) }
                }
            }
        }
    }
}

/// A brushed-metal EMV chip.
private struct CardChip: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(hex: "#D9D9D6"), Color(hex: "#9C9D99"), Color(hex: "#CFCFCB")],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            GeometryReader { g in
                Path { p in
                    let w = g.size.width, h = g.size.height
                    p.move(to: CGPoint(x: w * 0.5, y: 0)); p.addLine(to: CGPoint(x: w * 0.5, y: h))
                    p.move(to: CGPoint(x: 0, y: h * 0.34)); p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.34))
                    p.move(to: CGPoint(x: w * 0.64, y: h * 0.34)); p.addLine(to: CGPoint(x: w, y: h * 0.34))
                    p.move(to: CGPoint(x: 0, y: h * 0.66)); p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.66))
                    p.move(to: CGPoint(x: w * 0.64, y: h * 0.66)); p.addLine(to: CGPoint(x: w, y: h * 0.66))
                    p.addRoundedRect(in: CGRect(x: w * 0.36, y: h * 0.2, width: w * 0.28, height: h * 0.6),
                                     cornerSize: CGSize(width: 3, height: 3))
                }
                .stroke(Color.black.opacity(0.25), lineWidth: 0.8)
            }
            shape.stroke(Color.white.opacity(0.6), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
    }
}
