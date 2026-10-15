import SwiftUI

struct SettingsView: View {
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    @AppStorage("isWhiteTheme") private var isWhiteTheme = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subManager = SubscriptionManager.shared

    var body: some View {
        ZStack {
            Color.ncSurfaceContLowest.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {

                    // ── Header ───────────────────────────────────────────────
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.ncPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.ncSurfaceContHigh)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        .smoothButton()
                        VStack(alignment: .leading, spacing: 1) {
                            Text("SYSTEM CONFIG")
                                .font(.system(size: 18, weight: .semibold))
                                .tracking(2).foregroundColor(.ncPrimary)
                            Text("PRIMAL // SETTINGS")
                                .font(.ncLabelMonoReg).tracking(2).foregroundColor(.ncSecondary)
                        }
                        .padding(.leading, 8)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 56)
                    .padding(.bottom, 4)

                    // ── Haptics ──────────────────────────────────────────────
                    SettingsSection(title: "HAPTIC TELEMETRY") {
                        StitchToggleRow(
                            icon: "waveform.path",
                            title: "HAPTIC FEEDBACK",
                            subtitle: "Satisfying buzz on food log events",
                            isOn: $isHapticsEnabled
                        )
                    }

                    // ── Appearance ───────────────────────────────────────────
                    SettingsSection(title: "DISPLAY PARAMETERS") {
                        StitchToggleRow(
                            icon: "sun.max",
                            title: "LIGHT MODE",
                            subtitle: "Switch from dark void to light surface",
                            isOn: $isWhiteTheme
                        )
                    }

                    // ── Subscription ─────────────────────────────────────────
                    SettingsSection(title: "SUBSCRIPTION") {
                        SettingsLinkRow(icon: "creditcard", title: "MANAGE SUBSCRIPTION",
                                        subtitle: subManager.isSubscribed ? "Update card, cancel, view invoices" : "No active subscription") {
                            Task { await subManager.openBillingPortal() }
                        }
                        .disabled(!subManager.isSubscribed || subManager.isWorking)
                        if let error = subManager.errorMessage {
                            Text(error).font(.ncBodySm).foregroundColor(.ncError)
                                .padding(.horizontal, 14).padding(.bottom, 10)
                        }
                    }

                    // ── Privacy ──────────────────────────────────────────────
                    SettingsSection(title: "LEGAL & COMPLIANCE") {
                        SettingsLinkRow(icon: "lock.shield", title: "PRIVACY POLICY", subtitle: "Data handling & retention") {
                            openURL("https://primal.app/privacy")
                        }
                        Divider().background(Color.white.opacity(0.06))
                        SettingsLinkRow(icon: "doc.text", title: "TERMS OF SERVICE", subtitle: "Usage agreement") {
                            openURL("https://primal.app/terms")
                        }
                        Divider().background(Color.white.opacity(0.06))
                        SettingsLinkRow(icon: "questionmark.circle", title: "SUPPORT", subtitle: "Report issues & feedback") {
                            openURL("mailto:support@primal.app")
                        }
                    }

                    // ── Data ─────────────────────────────────────────────────
                    SettingsSection(title: "DATA OPERATIONS") {
                        SettingsActionRow(icon: "arrow.counterclockwise", title: "RESET ONBOARDING", subtitle: "Re-run initial setup flow", isDestructive: false) {
                            hasCompletedOnboarding = false
                        }
                    }

                    // ── App Info ─────────────────────────────────────────────
                    VStack(spacing: 4) {
                        Text("PRIMAL // ANCESTRAL NUTRITION OS")
                            .font(.ncLabelMonoBold).tracking(2).foregroundColor(.ncSecondary)
                        Text("VERSION \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.ncLabelMonoReg).tracking(1).foregroundColor(.ncSecondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func openURL(_ str: String) {
        guard let url = URL(string: str) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.ncLabelMonoBold).tracking(2)
                .foregroundColor(.ncSecondary)
                .padding(.horizontal, 16).padding(.bottom, 6)
            VStack(spacing: 0) { content }
                .background(Color.ncSurfaceCont)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Toggle Row
struct StitchToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(.ncSecondary)
                .frame(width: 32, height: 32)
                .background(Color.ncSurfaceContHigh)
                .cornerRadius(6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ncLabelMonoBold).tracking(1.5).foregroundColor(.ncPrimary)
                Text(subtitle).font(.ncBodySm).foregroundColor(.ncSecondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .ncPrimary))
                .labelsHidden()
                .scaleEffect(0.85)
        }
        .padding(14)
    }
}

// MARK: - Link Row
struct SettingsLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(.ncSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.ncSurfaceContHigh)
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ncLabelMonoBold).tracking(1.5).foregroundColor(.ncPrimary)
                    Text(subtitle).font(.ncBodySm).foregroundColor(.ncSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11)).foregroundColor(.ncSecondary)
            }
            .padding(14)
        }
        .smoothButton()
    }
}

// MARK: - Action Row
struct SettingsActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isDestructive: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(isDestructive ? .ncError : .ncSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.ncSurfaceContHigh)
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ncLabelMonoBold).tracking(1.5)
                        .foregroundColor(isDestructive ? .ncError : .ncPrimary)
                    Text(subtitle).font(.ncBodySm).foregroundColor(.ncSecondary)
                }
                Spacer()
            }
            .padding(14)
        }
        .smoothButton()
    }
}
