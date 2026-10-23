import SwiftUI

struct FriendsView: View {
    @StateObject private var social = SocialService.shared
    @State private var showAdd = false

    var body: some View {
        Group {
            ZStack {
                AppBackdrop()

                if social.myId == nil {
                    VStack(alignment: .leading, spacing: 0) {
                        PageHeader(title: "Friends", caption: "Eat together")
                        Spacer()
                        EmptyState(icon: "person.2", title: "Sign in to add friends",
                                   message: "Friends need an account so you can share what you eat.")
                        Spacer()
                        Spacer()
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.top, 12)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: Space.section) {
                            header

                            if !social.incoming.isEmpty {
                                section("Requests") {
                                    ForEach(social.incoming) { request in
                                        RequestRow(request: request)
                                    }
                                }
                            }

                            section("Friends") {
                                if social.friends.isEmpty {
                                    EmptyState(icon: "person.2", title: "No friends yet",
                                               message: "Search by username to add someone.", compact: true)
                                } else {
                                    ForEach(social.friends) { friend in
                                        NavigationLink(value: friend) {
                                            FriendRow(friend: friend, calories: social.friendCalories[friend.userId])
                                        }
                                        .buttonStyle(SmoothButtonStyle())
                                    }
                                }
                            }

                            if !social.outgoing.isEmpty {
                                section("Sent") {
                                    ForEach(social.outgoing) { request in
                                        SentRow(request: request)
                                    }
                                }
                            }

                            if let error = social.errorMessage {
                                Text(error).font(.ui(size: 13)).foregroundColor(.ncError)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 110)
                    }
                    .refreshable { await social.refreshFriends() }
                }
            }
            .navigationDestination(for: BasicProfile.self) { FriendProfileView(profile: $0) }
            .sheet(isPresented: $showAdd) { AddFriendView() }
            .task { if social.myId != nil { await social.refreshFriends() } }
        }
        .animation(.smooth, value: social.friends)
        .animation(.smooth, value: social.incoming.count)
    }

    private var header: some View {
        PageHeader(title: "Friends", caption: social.friends.isEmpty ? "Eat together" : "\(social.friends.count) connected") {
            HeaderIconButton(systemName: "person.badge.plus", label: "Add friend") { showAdd = true }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: title)
            content()
        }
    }
}

// MARK: - Rows

private struct FriendRow: View {
    let friend: BasicProfile
    let calories: Double?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: friend.avatarUrl, name: friend.name, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name).font(.ui(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                Text("@\(friend.username)").font(.ui(size: 13)).foregroundColor(.ncSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(calories.map { "\(Int($0))" } ?? "—")
                    .font(.ui(size: 15, weight: .bold).monospacedDigit())
                    .foregroundColor(.ncPrimary)
                Text("kcal today").font(.ui(size: 12)).foregroundColor(.ncSecondary)
            }
            Image(systemName: "chevron.right").font(.ui(size: 12, weight: .semibold)).foregroundColor(.ncOutline)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
    }
}

private struct RequestRow: View {
    let request: FriendRequest
    @StateObject private var social = SocialService.shared

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: request.profile.avatarUrl, name: request.profile.name, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.profile.name).font(.ui(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                Text("@\(request.profile.username)").font(.ui(size: 13)).foregroundColor(.ncSecondary)
            }
            Spacer()
            Button { Task { await social.removeFriendship(request.friendship) } } label: {
                Image(systemName: "xmark").font(.ui(size: 13, weight: .bold))
                    .foregroundColor(.ncSecondary)
                    .frame(width: 44, height: 44)
                    .overlay(Rectangle().stroke(Color.ncPrimary.opacity(0.3), lineWidth: 1))
            }
            .smoothButton()
            .accessibilityLabel("Decline request from \(request.profile.name)")
            Button { Task { await social.accept(request.friendship) } } label: {
                Image(systemName: "checkmark").font(.ui(size: 13, weight: .bold))
                    .foregroundColor(.ncOnPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.ncPrimary)
            }
            .smoothButton()
            .accessibilityLabel("Accept request from \(request.profile.name)")
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
    }
}

private struct SentRow: View {
    let request: FriendRequest
    @StateObject private var social = SocialService.shared

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: request.profile.avatarUrl, name: request.profile.name, size: 36)
            Text(request.profile.name).font(.ui(size: 14, weight: .medium)).foregroundColor(.ncPrimary)
            Spacer()
            Button("Cancel") { Task { await social.removeFriendship(request.friendship) } }
                .font(.ui(size: 13, weight: .medium))
                .foregroundColor(.ncSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var compact = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.ui(size: compact ? 22 : 34, weight: .ultraLight)).foregroundColor(.ncSecondary)
            Text(title).font(.serif(compact ? 20 : 26)).foregroundColor(.ncPrimary).multilineTextAlignment(.center)
            Text(message).font(.ui(size: 14)).foregroundColor(.ncSecondary).multilineTextAlignment(.center).lineSpacing(2)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, compact ? 24 : 0)
        .frame(maxWidth: .infinity)
        .modifier(OptionalCard(enabled: compact))
    }
}

private struct OptionalCard: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.glassCard(radius: 16) } else { content }
    }
}
