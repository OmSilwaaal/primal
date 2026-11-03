import SwiftUI
import StoreKit
import SwiftData

struct SettingsView: View {
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    @AppStorage(BrandSound.enabledKey) private var isSoundEnabled = false
    @State private var eveningReminder = Reminders.isOn(.eveningLog)
    @State private var morningReminder = Reminders.isOn(.morningSun)
    @State private var reminderDenied = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var legalDocument: LegalDocument?
    @State private var showManageSubscriptions = false
    @State private var showPaywall = false
    @State private var showPayment = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var subManager = SubscriptionManager.shared
    @StateObject private var social = SocialService.shared
    @StateObject private var auth = AuthManager.shared

    @State private var showEmailAlert = false
    @State private var newEmail = ""
    @State private var emailMessage: String?
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    // ── Subscription ────────────────────────────────────────
                    SettingsSection(title: "Subscription") {
                        if subManager.isSubscribed {
                            SettingsRow(icon: "checkmark.seal", title: "Vitalis Pro",
                                        subtitle: "Active · change plan or cancel", showsChevron: true,
                                        enabled: !subManager.isWorking) {
                                showManageSubscriptions = true
                            }
                        } else {
                            // An explicit button + destination: the older NavigationLink(destination:) could fire on
                            // its own inside this pushed screen and jump straight to Payment.
                            SettingsRow(icon: "creditcard", title: "Get Vitalis Pro", subtitle: "Plans and payment",
                                        showsChevron: true) {
                                showPayment = true
                            }
                        }
                        SettingsDivider()
                        SettingsRow(icon: "arrow.clockwise", title: "Restore purchases",
                                    subtitle: "Bought Pro on another device or Apple Account",
                                    enabled: !subManager.isWorking) {
                            Task { await subManager.restorePurchases() }
                        }
                        if let error = subManager.errorMessage {
                            Text(error).font(.ui(size: 13)).foregroundColor(.ncEmber)
                                .padding(.bottom, 12)
                        }
                    }

                    // ── Account ─────────────────────────────────────────────
                    SettingsSection(title: "Account") {
                        if let profile = social.myProfile {
                            NavigationLink(destination: EditProfileView()) {
                                HStack(spacing: 16) {
                                    AvatarView(url: profile.avatarUrl, name: profile.name, size: 52)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(profile.name).font(.ui(size: 17, weight: .semibold)).foregroundColor(Mono.text)
                                        Text("@\(profile.username)").font(.ui(size: 13)).foregroundColor(Mono.label)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.ui(size: 12, weight: .semibold)).foregroundColor(Mono.label)
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(SmoothButtonStyle())
                            SettingsDivider()
                        }
                        SettingsRow(icon: "envelope", title: "Email", subtitle: auth.currentEmail ?? "Not signed in") {
                            newEmail = auth.currentEmail ?? ""
                            showEmailAlert = true
                        }
                        if let emailMessage {
                            Text(emailMessage).font(.ui(size: 13)).foregroundColor(.ncSecondary)
                                .padding(.bottom, 12)
                        }
                        SettingsDivider()
                        NavigationLink(destination: BodyGoalsView()) {
                            SettingsRowLabel(icon: "figure.stand", title: "Body & goals", subtitle: "Weight, height, activity", showsChevron: true)
                        }
                        .buttonStyle(SmoothButtonStyle())
                    }

                    // ── Privacy ─────────────────────────────────────────────
                    if let profile = social.myProfile {
                        SettingsSection(title: "Privacy", footer: privacyFooter(profile)) {
                            SettingsToggleRow(icon: "lock", title: "Private profile",
                                              subtitle: "Only friends can see your bio and activity",
                                              isOn: Binding(get: { profile.isPrivate },
                                                            set: { update(profile, isPrivate: $0) }))
                            SettingsDivider()
                            HStack(spacing: 12) {
                                SettingsIcon(name: "fork.knife")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Who can see my meals").font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                                    Text("Calories and what you ate").font(.ui(size: 12)).foregroundColor(Mono.label)
                                }
                                Spacer()
                                Menu {
                                    Picker("Meals visible to", selection: Binding(get: { profile.mealVisibility },
                                                                                  set: { update(profile, visibility: $0) })) {
                                        ForEach(MealVisibility.allCases) { Text($0.title).tag($0) }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(profile.mealVisibility.title)
                                        Image(systemName: "chevron.up.chevron.down").font(.ui(size: 11))
                                    }
                                    .font(.ui(size: 14, weight: .medium))
                                    .foregroundColor(.ncSecondary)
                                }
                            }
                            .padding(.vertical, 12)
                        }
                    }

                    // ── Preferences ─────────────────────────────────────────
                    SettingsSection(title: "Preferences") {
                        SettingsToggleRow(icon: "waveform.path", title: "Haptic feedback",
                                          subtitle: "Taps and confirmations", isOn: $isHapticsEnabled)
                        SettingsDivider()
                        SettingsToggleRow(icon: "speaker.wave.1", title: "Sounds",
                                          subtitle: "A soft knock when you log or hit a goal", isOn: $isSoundEnabled)
                    }

                    SettingsSection(title: "App icon",
                                    footer: subManager.isSubscribed ? nil : "App icons come with Vitalis Pro.") {
                        AppIconPicker(locked: !subManager.isSubscribed) { showPaywall = true }
                    }

                    SettingsSection(title: "Reminders",
                                    footer: reminderDenied ? "Notifications are off for Vitalis. Turn them on in iOS Settings to use reminders." : nil) {
                        SettingsToggleRow(icon: "fork.knife", title: "Evening log",
                                          subtitle: "8 pm · log today's meals and water", isOn: $eveningReminder)
                        SettingsDivider()
                        SettingsToggleRow(icon: "sun.horizon", title: "Morning light",
                                          subtitle: "8 am · a nudge to get outside", isOn: $morningReminder)
                    }
                    .onChange(of: eveningReminder) { _, on in
                        Task { if !(await Reminders.set(.eveningLog, on: on)) { eveningReminder = false; reminderDenied = true } }
                    }
                    .onChange(of: morningReminder) { _, on in
                        Task { if !(await Reminders.set(.morningSun, on: on)) { morningReminder = false; reminderDenied = true } }
                    }

                    // ── Legal ───────────────────────────────────────────────
                    SettingsSection(title: "About") {
                        SettingsRow(icon: "lock.shield", title: "Privacy policy", subtitle: "How your data is handled") {
                            legalDocument = .privacy
                        }
                        SettingsDivider()
                        SettingsRow(icon: "doc.text", title: "Terms of service", subtitle: "Usage agreement") {
                            legalDocument = .terms
                        }
                        SettingsDivider()
                        SettingsRow(icon: "cross.case", title: "Health & safety policy", subtitle: "Not medical advice; use at your own risk") {
                            legalDocument = .safety
                        }
                        SettingsDivider()
                        SettingsRow(icon: "questionmark.circle", title: "Support", subtitle: "Report issues and feedback") {
                            open("mailto:support@vitalis.app")
                        }
                    }

                    // ── Session & data ──────────────────────────────────────
                    SettingsSection(title: "Session") {
                        SettingsRow(icon: "arrow.counterclockwise", title: "Redo setup", subtitle: "Run the profile setup again") {
                            hasCompletedOnboarding = false
                        }
                        SettingsDivider()
                        SettingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign out", subtitle: nil) {
                            showSignOutConfirm = true
                        }
                        SettingsDivider()
                        SettingsRow(icon: "trash", title: "Delete account", subtitle: "Permanently erase your account and data",
                                    destructive: true, enabled: !isDeleting) {
                            showDeleteConfirm = true
                        }
                        if let deleteError {
                            Text(deleteError).font(.ui(size: 13)).foregroundColor(.ncEmber)
                                .padding(.bottom, 12)
                        }
                    }

                    Text("Vitalis · Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.ui(size: 12)).foregroundColor(Mono.label)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 100)
                }
                .padding(.horizontal, Bento.margin)
                .padding(.top, 8)
            }
            .glassLightFollowsScroll()
        }
        .navigationBarHidden(true)
        .alert("Change email", isPresented: $showEmailAlert) {
            TextField("New email", text: $newEmail).textInputAutocapitalization(.never).keyboardType(.emailAddress)
            Button("Cancel", role: .cancel) {}
            Button("Send confirmation") {
                Task {
                    emailMessage = await auth.updateEmail(newEmail) ?? "Check \(newEmail) to confirm the change."
                }
            }
        } message: {
            Text("We'll email a confirmation link to the new address.")
        }
        .sheet(item: $legalDocument) { LegalView(document: $0) }
        .navigationDestination(isPresented: $showPayment) { PaymentView().pushedScreen() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onNotNow: { showPaywall = false }, showsAccountButton: false)
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .onChange(of: showManageSubscriptions) { _, shown in
            if !shown { Task { await subManager.refreshEntitlement() } }
        }
        .confirmationDialog("Sign out of Vitalis?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
        }
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete forever", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This permanently erases your profile, friends and shared meals. It can't be undone. An App Store subscription isn't cancelled by this; cancel it in your Apple ID settings.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.bentoRound)
                .accessibilityLabel("Back")
            Text("Settings").font(.bentoTitle).foregroundColor(Mono.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
    }

    private func privacyFooter(_ profile: PublicProfile) -> String {
        switch profile.mealVisibility {
        case .nobody: return "Friends can see your profile but none of your meals."
        case .friends: return "Your friends can see the calories and meals you log."
        case .everyone: return profile.isPrivate
            ? "Only friends see your meals while your profile is private."
            : "Anyone on Vitalis can see the calories and meals you log."
        }
    }

    private func update(_ profile: PublicProfile, isPrivate: Bool? = nil, visibility: MealVisibility? = nil) {
        Haptics.selection()
        Task {
            await social.saveProfile(.init(
                displayName: profile.displayName, username: profile.username, bio: profile.bio,
                isPrivate: isPrivate ?? profile.isPrivate, mealVisibility: visibility ?? profile.mealVisibility))
        }
    }

    private func open(_ str: String) {
        guard let url = URL(string: str) else { return }
        UIApplication.shared.open(url)
    }

    private func deleteAccount() async {
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }
        if let error = await auth.deleteAccount() {
            deleteError = error
            return
        }
        // Wipe on-device data too.
        try? modelContext.delete(model: MealEntry.self)
        try? modelContext.delete(model: DailyHydration.self)
        try? modelContext.delete(model: UserProfile.self)
        try? modelContext.save()
    }
}

// MARK: - Building blocks

/// A group of settings: a label, then its rows in one glass tile, and an optional note under it.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.bentoLabel).foregroundColor(Mono.label).padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .bentoTile(padding: 16)
            if let footer {
                Text(footer).font(.ui(size: 12)).foregroundColor(Mono.label).lineSpacing(2)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct SettingsDivider: View {
    var body: some View { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
}

/// The row's icon in a small glass circle.
private struct SettingsIcon: View {
    let name: String
    var destructive = false
    var body: some View {
        Group {
            if name.hasPrefix("asset:") {
                // A drawn icon from the asset catalog (e.g. Raw's steak).
                Image(String(name.dropFirst(6))).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 17, height: 17)
            } else {
                Image(systemName: name).font(.ui(size: 14, weight: .medium))
            }
        }
            .foregroundColor(destructive ? .ncEmber : Mono.text)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.white.opacity(0.06)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

private struct SettingsRowLabel: View {
    let icon: String
    let title: String
    let subtitle: String?
    var destructive = false
    var showsChevron = false

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(name: icon, destructive: destructive)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(size: 15, weight: .semibold)).foregroundColor(destructive ? .ncEmber : Mono.text)
                if let subtitle {
                    Text(subtitle).font(.ui(size: 12)).foregroundColor(Mono.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right").font(.ui(size: 12, weight: .semibold)).foregroundColor(Mono.label)
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    var destructive = false
    var showsChevron = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(icon: icon, title: title, subtitle: subtitle, destructive: destructive,
                             showsChevron: showsChevron)
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(name: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                Text(subtitle).font(.ui(size: 12)).foregroundColor(Mono.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn).labelsHidden().tint(.ncMoss)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 56)
    }
}

// MARK: - Payment

/// The payment page, opened from Settings › Subscription: the Vitalis card centred on the app's backdrop, with
/// its valid-through date. Without Pro: choose a plan and how to pay — the card shows the chosen method's mark — and
/// subscribe through the App Store. With Pro: the card reads Active and the button manages the subscription.
/// The back button sits bottom left in Liquid Glass.
struct PaymentView: View {
    @StateObject private var subManager = SubscriptionManager.shared
    @StateObject private var social = SocialService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var plan: SubscriptionManager.Plan = .annual
    @AppStorage("preferredPaymentMethod") private var methodRaw = PaymentMethod.applePay.rawValue
    @State private var showManage = false

    private var method: PaymentMethod { PaymentMethod(rawValue: methodRaw) ?? .applePay }

    /// With Pro, when the current period ends; without, when the selected plan would run until if started today.
    private var expires: Date? {
        if subManager.isSubscribed { return subManager.expirationDate }
        return Calendar.current.date(byAdding: plan == .annual ? .year : .month, value: 1, to: .now)
    }

    private var expiryLine: String {
        guard let expires else { return "Active" }
        let date = expires.formatted(date: .long, time: .omitted)
        return subManager.isSubscribed ? "Renews or expires on \(date)" : "Starting today, valid through \(date)"
    }

    var body: some View {
        ZStack {
            AppBackdrop()

            VStack(spacing: 18) {
                Text(subManager.isSubscribed ? "Your membership" : "Vitalis Pro")
                    .font(.ui(size: 17, weight: .semibold)).foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                VitalisCard(name: social.myProfile?.name ?? "Vitalis Member", isPro: subManager.isSubscribed,
                            method: subManager.isSubscribed ? nil : method, expires: expires)
                    .padding(.horizontal, 6)
                Text(expiryLine).font(.ui(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.85))
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
                if subManager.isSubscribed { manage } else { checkout }
                bottomBar
            }
            .padding(.horizontal, Bento.margin)
        }
        .navigationBarHidden(true)
        .hidesTabBar(true)
        .manageSubscriptionsSheet(isPresented: $showManage)
        .onChange(of: showManage) { _, shown in if !shown { Task { await subManager.refreshEntitlement() } } }
        .task { if subManager.products.isEmpty { await subManager.loadProducts() } }
    }

    // MARK: Checkout

    private var checkout: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Plan.
            HStack(spacing: 8) {
                ForEach(SubscriptionManager.Plan.allCases.reversed()) { p in
                    let on = plan == p
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { plan = p }
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 6) {
                                Text(p.title).font(.ui(size: 15, weight: .semibold))
                                if p == .annual, let save = subManager.annualSavingsPercent {
                                    Text("-\(save)%").font(.mono(10, .semibold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.ncMoss)).foregroundColor(Mono.onWhite)
                                }
                            }
                            Text(subManager.priceLabel(for: p).isEmpty ? "—" : subManager.priceLabel(for: p))
                                .font(.ui(size: 12)).opacity(0.8)
                        }
                        .foregroundColor(on ? Mono.onWhite : .white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background { if on { Capsule().fill(Color.white) } }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(4)
            .glass(.clear, in: Capsule())

            // How to pay.
            Text("Pay with").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(.white.opacity(0.85))
                .padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PaymentMethod.allCases) { m in
                        let on = m == method
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { methodRaw = m.rawValue }
                        } label: {
                            Label(m.short, systemImage: m.icon).font(.ui(size: 14, weight: .semibold))
                                .foregroundColor(on ? Mono.onWhite : .white)
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .background { if on { Capsule().fill(Color.white) } }
                                .glass(.clear, in: Capsule(), interactive: !on)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(m.title)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }

            Button {
                Task { await subManager.subscribe(to: plan) }
            } label: {
                ZStack {
                    if subManager.isWorking { ProgressView().tint(Mono.onWhite) }
                    else {
                        let price = subManager.priceLabel(for: plan)
                        Text(price.isEmpty ? "Continue with \(method.short)" : "Subscribe · \(price)")
                    }
                }
            }
            .buttonStyle(.bentoPrimary)
            .disabled(subManager.isWorking || subManager.products.isEmpty)

            if let error = subManager.errorMessage {
                Text(error).font(.ui(size: 12)).foregroundColor(.ncEmber)
            }
            Text("Charged to your Apple Account with \(method.title) when you confirm in Apple's payment sheet; you can change the method there. Renews automatically unless cancelled 24 hours before the period ends.")
                .font(.ui(size: 11)).foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glass(.tinted, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var manage: some View {
        Button("Manage subscription") { showManage = true }
            .buttonStyle(.bentoPrimary)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.ui(size: 18, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .glass(.clear, in: Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
            if !subManager.isSubscribed {
                Button("Restore") { Task { await subManager.restorePurchases() } }
                    .font(.ui(size: 15, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 20).frame(height: 52)
                    .glass(.clear, in: Capsule(), interactive: true)
                    .disabled(subManager.isWorking)
            }
        }
        .padding(.bottom, 4)
    }
}

#if DEBUG
#Preview("Payment") {
    NavigationStack { PaymentView() }
        .preferredColorScheme(.dark)
}
#endif
