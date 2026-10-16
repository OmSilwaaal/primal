import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
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
                VStack(spacing: 28) {
                    header

                    // ── Account ─────────────────────────────────────────────
                    SettingsSection(title: "Account") {
                        if let profile = social.myProfile {
                            NavigationLink(destination: EditProfileView()) {
                                HStack(spacing: 14) {
                                    AvatarView(url: profile.avatarUrl, name: profile.name, size: 52)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.name).font(.system(size: 16, weight: .semibold)).foregroundColor(.ncPrimary)
                                        Text("@\(profile.username)").font(.system(size: 13)).foregroundColor(.ncSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.ncOutline)
                                }
                                .padding(14)
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
                                .padding(.horizontal, 14).padding(.bottom, 12)
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
                                    subtitle: subManager.isSubscribed ? "Update card, cancel, view invoices" : "No active subscription",
                                    enabled: subManager.isSubscribed && !subManager.isWorking) {
                            Task { await subManager.openBillingPortal() }
                        }
                        if let error = subManager.errorMessage {
                            Text(error).font(.system(size: 13)).foregroundColor(.ncError)
                                .padding(.horizontal, 14).padding(.bottom, 12)
                        }
                    }

                    // ── Legal ───────────────────────────────────────────────
                    SettingsSection(title: "About") {
                        SettingsRow(icon: "lock.shield", title: "Privacy policy", subtitle: "How your data is handled") {
                            open("https://primal.app/privacy")
                        }
                        SettingsDivider()
                        SettingsRow(icon: "doc.text", title: "Terms of service", subtitle: "Usage agreement") {
                            open("https://primal.app/terms")
                        }
                        SettingsDivider()
                        SettingsRow(icon: "questionmark.circle", title: "Support", subtitle: "Report issues and feedback") {
                            open("mailto:support@primal.app")
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
                                .padding(.horizontal, 14).padding(.bottom, 12)
                        }
                    }

                    Text("Primal · Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
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
        .confirmationDialog("Sign out of Primal?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
        }
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete forever", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This permanently erases your profile, friends, shared meals and cancels your subscription. It can't be undone.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ncPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.ncSurfaceContHigh, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .smoothButton()
            Text("Settings").font(.system(size: 28, weight: .bold)).foregroundColor(.ncPrimary)
            Spacer()
        }
    }

    private func privacyFooter(_ profile: PublicProfile) -> String {
        switch profile.mealVisibility {
        case .nobody: return "Friends can see your profile but none of your meals."
        case .friends: return "Your friends can see the calories and meals you log."
        case .everyone: return profile.isPrivate
            ? "Only friends see your meals while your profile is private."
            : "Anyone on Primal can see the calories and meals you log."
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(1)
                .foregroundColor(.ncSecondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .glassCard(radius: 16)
            if let footer {
                Text(footer).font(.system(size: 13)).foregroundColor(.ncSecondary).padding(.horizontal, 4)
            }
        }
    }
}

private struct SettingsDivider: View {
    var body: some View { Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 60) }
}

private struct SettingsIcon: View {
    let name: String
    var destructive = false
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(destructive ? .ncError : .ncSecondary)
            .frame(width: 32, height: 32)
            .background(Color.ncSurfaceContHigh, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

private struct SettingsRowLabel: View {
    let icon: String
    let title: String
    let subtitle: String?
    var destructive = false
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(name: icon, destructive: destructive)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundColor(destructive ? .ncError : .ncPrimary)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundColor(.ncSecondary) }
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.ncOutline)
            }
        }
        .padding(14)
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
        HStack(spacing: 12) {
            SettingsIcon(name: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundColor(.ncPrimary)
                Text(subtitle).font(.system(size: 13)).foregroundColor(.ncSecondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(.ncIndigo)
        }
        .padding(14)
    }
}
