import SwiftUI

struct PaywallView: View {
    @StateObject private var subManager = SubscriptionManager.shared
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedPlan: SubscriptionManager.Plan = .annual

    var body: some View {
        ZStack {
            AppBackdrop()

            Circle()
                .fill(Color.ncIndigo.opacity(0.12))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(y: -250)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // ── Brand ─────────────────────────────────────────────
                    VStack(spacing: 12) {
                        Image(systemName: "hexagon")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(.ncIndigo)
                            .frame(width: 68, height: 68)
                            .glassCard(radius: 20)
                        Text("Primal Pro")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.ncPrimary)
                        Text("Unlock the full system")
                            .font(.system(size: 15))
                            .foregroundColor(.ncSecondary)
                    }
                    .padding(.top, 48)

                    // ── Features ──────────────────────────────────────────
                    VStack(spacing: 0) {
                        PaywallFeatureRow(icon: "barcode.viewfinder", tint: .ncIndigo, tintBg: .ncIndigoLight,
                                          label: "Food scanner", sub: "Barcode and AI photo logging")
                        Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 62)
                        PaywallFeatureRow(icon: "heart.text.square.fill", tint: .ncError, tintBg: Color.ncError.opacity(0.1),
                                          label: "Apple Health sync", sub: "Steps, activity and nutrition")
                        Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 62)
                        PaywallFeatureRow(icon: "chart.bar.xaxis", tint: .ncGreen, tintBg: .ncGreenLight,
                                          label: "Full nutrient tracking", sub: "Macros, vitamins and minerals")
                    }
                    .glassCard(radius: 3)

                    // ── Plans ─────────────────────────────────────────────
                    VStack(spacing: 10) {
                        ForEach(SubscriptionManager.Plan.allCases.reversed()) { plan in
                            PlanCard(plan: plan, isSelected: selectedPlan == plan) { selectedPlan = plan }
                        }
                    }

                    // ── CTA ───────────────────────────────────────────────
                    VStack(spacing: 12) {
                        Button {
                            Task { await subManager.subscribe(to: selectedPlan) }
                        } label: {
                            ZStack {
                                if subManager.isWorking {
                                    ProgressView().tint(.ncOnPrimary)
                                } else {
                                    Text("Subscribe · \(selectedPlan.priceLabel)")
                                }
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(height: 54))
                        .disabled(subManager.isWorking)

                        if let error = subManager.errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(.ncError)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: 20) {
                            Button("Restore") { Task { await subManager.restorePurchases() } }
                            Button("Sign out") { Task { await authManager.signOut() } }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.ncSecondary)
                        .disabled(subManager.isWorking)

                        Text("Payments are processed securely by Stripe. Your subscription renews automatically until you cancel in Settings.")
                            .font(.system(size: 12))
                            .foregroundColor(.ncSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)

                        #if DEBUG
                        Button("DEBUG: skip paywall") { subManager.debugUnlock() }
                            .font(.system(size: 12))
                            .foregroundColor(.ncSecondary.opacity(0.6))
                        #endif
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct PlanCard: View {
    let plan: SubscriptionManager.Plan
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .ncIndigo : .ncOutline)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plan.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.ncPrimary)
                        if plan == .annual {
                            Text("SAVE 40%")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.ncGreen)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.ncGreenLight)
                                .cornerRadius(4)
                        }
                    }
                    Text(plan.detail).font(.ncBodySm).foregroundColor(.ncSecondary)
                }
                Spacer()
                Text(plan.priceLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ncPrimary)
            }
            .padding(14)
            .background(Color.ncSurfaceContLowest)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? Color.ncIndigo : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(SmoothButtonStyle())
        .animation(.easeOut(duration: 0.2), value: isSelected)
    }
}

struct PaywallFeatureRow: View {
    let icon: String
    let tint: Color
    let tintBg: Color
    let label: String
    let sub: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .background(tintBg)
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 14, weight: .semibold)).foregroundColor(.ncPrimary)
                Text(sub).font(.ncBodySm).foregroundColor(.ncSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
