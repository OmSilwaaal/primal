import SwiftUI

struct FriendProfileView: View {
    let profile: BasicProfile
    @StateObject private var social = SocialService.shared
    @State private var full: PublicProfile?
    @State private var meals: [SharedMeal] = []
    @State private var dayOffset = 0 // 0 = today, -1 = yesterday...
    @State private var isLoading = true
    @State private var confirmRemove = false

    private var day: Date { Calendar.current.date(byAdding: .day, value: dayOffset, to: .now) ?? .now }
    private var summary: DaySummary { DaySummary(meals: meals) }
    private var isFriend: Bool { if case .friend = social.relation(to: profile.userId) { return true } else { return false } }

    var body: some View {
        ZStack {
            Color.ncBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    header
                    actions
                    if let full {
                        if full.mealVisibility == .nobody {
                            note(icon: "eye.slash", text: "\(profile.name) keeps their meals private.")
                        } else {
                            daySection
                        }
                    } else if !isLoading {
                        note(icon: "lock.fill", text: "This profile is private. Become friends to see their activity.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: dayOffset) { _, _ in Task { await loadMeals() } }
        .onChange(of: social.friends) { _, _ in Task { await load() } }
        .confirmationDialog("Remove \(profile.name) from your friends?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) { Task { await social.removeFriendship(with: profile.userId) } }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            AvatarView(url: full?.avatarUrl ?? profile.avatarUrl, name: profile.name, size: 92)
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.name).font(.system(size: 22, weight: .bold)).foregroundColor(.ncPrimary)
                    if profile.isPrivate {
                        Image(systemName: "lock.fill").font(.system(size: 12)).foregroundColor(.ncSecondary)
                    }
                }
                Text("@\(profile.username)").font(.system(size: 13)).foregroundColor(.ncSecondary)
            }
            if let bio = full?.bio, !bio.isEmpty {
                Text(bio).font(.system(size: 14)).foregroundColor(.ncSecondary).multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var actions: some View {
        switch social.relation(to: profile.userId) {
        case .none:
            Button("Add friend") { Task { await social.sendRequest(to: profile.userId) } }
                .buttonStyle(PrimaryButtonStyle(height: 46, radius: 12))
        case .requestSent:
            Button("Cancel request") { Task { await social.removeFriendship(with: profile.userId) } }
                .buttonStyle(SecondaryButtonStyle(height: 46))
        case .requestReceived(let friendship):
            HStack(spacing: 10) {
                Button("Decline") { Task { await social.removeFriendship(friendship) } }
                    .buttonStyle(SecondaryButtonStyle(height: 46))
                Button("Accept") { Task { await social.accept(friendship) } }
                    .buttonStyle(PrimaryButtonStyle(height: 46, radius: 12))
            }
        case .friend:
            Button { confirmRemove = true } label: {
                Label("Friends", systemImage: "checkmark")
            }
            .buttonStyle(SecondaryButtonStyle(height: 46))
        }
    }

    private var daySection: some View {
        VStack(spacing: 14) {
            HStack {
                Button { withAnimation(.snappy) { dayOffset -= 1 } } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                Spacer()
                Text(dayLabel).font(.system(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                    .contentTransition(.opacity)
                Spacer()
                Button { withAnimation(.snappy) { dayOffset += 1 } } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
                .disabled(dayOffset >= 0)
                .opacity(dayOffset >= 0 ? 0.3 : 1)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.ncPrimary)

            VStack(spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(Int(summary.calories))")
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundColor(.ncPrimary)
                        .contentTransition(.numericText())
                    Text("kcal").font(.system(size: 14)).foregroundColor(.ncSecondary)
                    Spacer()
                }
                HStack(spacing: 8) {
                    MacroChip(label: "Protein", value: summary.protein, tint: .ncPrimary)
                    MacroChip(label: "Carbs", value: summary.carbs, tint: .ncGreen)
                    MacroChip(label: "Fat", value: summary.fat, tint: .ncOrange)
                }
            }
            .padding(16)
            .glassCard(radius: 18)
            .animation(.smooth, value: summary.calories)

            if meals.isEmpty {
                Text(isLoading ? "Loading…" : "Nothing logged this day")
                    .font(.system(size: 13)).foregroundColor(.ncSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(meals) { MealLine(meal: $0) }
                }
            }
        }
    }

    private func note(icon: String, text: String) -> some View {
        EmptyState(icon: icon, title: text, message: "", compact: true)
    }

    private var dayLabel: String {
        if dayOffset == 0 { return "Today" }
        if dayOffset == -1 { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        full = await social.fullProfile(profile.userId)
        await loadMeals()
        isLoading = false
    }

    private func loadMeals() async {
        guard let full, full.mealVisibility != .nobody else { meals = []; return }
        meals = await social.meals(for: profile.userId, on: day)
    }
}

private struct MacroChip: View {
    let label: String
    let value: Double
    let tint: Color
    var body: some View {
        VStack(spacing: 3) {
            Text("\(Int(value))g").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundColor(.ncPrimary)
            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(label).font(.system(size: 11)).foregroundColor(.ncSecondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color.ncSurfaceContLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MealLine: View {
    let meal: SharedMeal
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.foodName.capitalized).font(.system(size: 14, weight: .semibold)).foregroundColor(.ncPrimary).lineLimit(1)
                Text("\(meal.eatenAt.formatted(date: .omitted, time: .shortened)) · P \(Int(meal.protein))g · C \(Int(meal.carbohydrates))g · F \(Int(meal.totalFat))g")
                    .font(.system(size: 11)).foregroundColor(.ncSecondary)
            }
            Spacer()
            Text("\(Int(meal.calories)) kcal").font(.system(size: 13, weight: .bold)).foregroundColor(.ncPrimary)
        }
        .padding(14)
        .glassCard(radius: 14)
    }
}
