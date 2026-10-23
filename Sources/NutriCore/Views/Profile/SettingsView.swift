import SwiftUI
import StoreKit
import SwiftData

struct SettingsView: View {
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var legalDocument: LegalDocument?
    @State private var showManageSubscriptions = false
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
                VStack(alignment: .leading, spacing: Space.section) {
                    header

                    // ── Account ─────────────────────────────────────────────
                    SettingsSection(title: "Account") {
                        if let profile = social.myProfile {
                            NavigationLink(destination: EditProfileView()) {
                                HStack(spacing: 16) {
                                    AvatarView(url: profile.avatarUrl, name: profile.name, size: 52)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name).font(.serif(20)).foregroundColor(.ncPrimary)
                                        Text("@\(profile.username)").font(.system(size: 13)).foregroundColor(.ncSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundColor(.ncSecondary)
                                }
                                .padding(.vertical, 16)
                            }
                            .buttonStyle(SmoothButtonStyle())
                            SettingsDivider()
                        }
                        SettingsRow(icon: "envelope", title: "Email", subtitle: auth.currentEmail ?? "Not signed in") {
                            newEmail = auth.currentEmail ?? ""
                            showEmailAlert = true
                        }
                        if let emailMessage {
                            Text(emailMessage).font(.system(size: 13)).foregroundColor(.ncSecondary)
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
                                    Text("Who can see my meals").font(.system(size: 15, weight: .medium)).foregroundColor(.ncPrimary)
                                    Text("Calories and what you ate").font(.system(size: 13)).foregroundColor(.ncSecondary)
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
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.ncSecondary)
                                }
                            }
                            .padding(14)
                        }
                    }

                    // ── Preferences ─────────────────────────────────────────
                    SettingsSection(title: "Preferences") {
                        SettingsToggleRow(icon: "waveform.path", title: "Haptic feedback",
                                          subtitle: "Taps and confirmations", isOn: $isHapticsEnabled)
                    }

                    // ── Subscription ────────────────────────────────────────
                    SettingsSection(title: "Subscription") {
                        SettingsRow(icon: "creditcard", title: "Manage subscription",
                                    subtitle: subManager.isSubscribed ? "Change plan or cancel" : "No active subscription",
                                    enabled: subManager.isSubscribed && !subManager.isWorking) {
                            showManageSubscriptions = true
                        }
                        if let error = subManager.errorMessage {
                            Text(error).font(.system(size: 13)).foregroundColor(.ncError)
                                .padding(.bottom, 12)
                        }
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
                            Text(deleteError).font(.system(size: 13)).foregroundColor(.ncError)
                                .padding(.bottom, 12)
                        }
                    }

                    Text("Vitalis · Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.system(size: 13)).foregroundColor(.ncSecondary)
                        .padding(.bottom, 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
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
        VStack(alignment: .leading, spacing: 20) {
            HeaderIconButton(systemName: "arrow.left", label: "Back") { dismiss() }
            PageHeader(title: "Settings", caption: "Account · privacy · app")
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

struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: title)
            VStack(spacing: 0) { content }
            if let footer {
                Text(footer).font(.system(size: 13)).foregroundColor(.ncSecondary).lineSpacing(2).padding(.top, 8)
            }
        }
    }
}

private struct SettingsDivider: View {
    var body: some View { Hairline(opacity: 0.1) }
}

private struct SettingsIcon: View {
    let name: String
    var destructive = false
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(destructive ? .ncError : .ncPrimary)
            .frame(width: 24)
    }
}

private struct SettingsRowLabel: View {
    let icon: String
    let title: String
    let subtitle: String?
    var destructive = false
    var showsChevron = false

    var body: some View {
        HStack(spacing: 16) {
            SettingsIcon(name: icon, destructive: destructive)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17, weight: .medium)).foregroundColor(destructive ? .ncError : .ncPrimary)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundColor(.ncSecondary) }
            }
            Spacer()
            if showsChevron {
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundColor(.ncSecondary)
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    var destructive = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(icon: icon, title: title, subtitle: subtitle, destructive: destructive)
        }
        .buttonStyle(SmoothButtonStyle())
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
        HStack(spacing: 16) {
            SettingsIcon(name: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17, weight: .medium)).foregroundColor(.ncPrimary)
                Text(subtitle).font(.system(size: 13)).foregroundColor(.ncSecondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(.ncPrimary.opacity(0.85))
        }
        .padding(.vertical, 16)
    }
}
