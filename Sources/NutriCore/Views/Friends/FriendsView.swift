import SwiftUI

struct FriendsView: View {
    @StateObject private var social = SocialService.shared
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                if social.myId == nil {
                    EmptyState(icon: "person.2.slash", title: "Sign in to add friends",
                               message: "Friends need an account so you can share what you eat.")
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
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
                                Text(error).font(.system(size: 12)).foregroundColor(.ncError)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 110)
                    }
                    .refreshable { await social.refreshFriends() }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: BasicProfile.self) { FriendProfileView(profile: $0) }
            .sheet(isPresented: $showAdd) { AddFriendView() }
            .task { if social.myId != nil { await social.refreshFriends() } }
        }
        .animation(.smooth, value: social.friends)
        .animation(.smooth, value: social.incoming.count)
    }

    private var header: some View {
        HStack {
            Text("Friends")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.ncPrimary)
            Spacer()
            Button { showAdd = true } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.ncPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.ncSurfaceContHigh, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .smoothButton()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundColor(.ncSecondary)
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
                Text(friend.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                Text("@\(friend.username)").font(.system(size: 12)).foregroundColor(.ncSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(calories.map { "\(Int($0))" } ?? "—")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundColor(.ncPrimary)
                Text("kcal today").font(.system(size: 11)).foregroundColor(.ncSecondary)
            }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundColor(.ncOutline)
        }
        .padding(12)
        .glassCard(radius: 16)
    }
}

private struct RequestRow: View {
    let request: FriendRequest
    @StateObject private var social = SocialService.shared

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: request.profile.avatarUrl, name: request.profile.name, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.profile.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                Text("@\(request.profile.username)").font(.system(size: 12)).foregroundColor(.ncSecondary)
            }
            Spacer()
            Button { Task { await social.removeFriendship(request.friendship) } } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                    .foregroundColor(.ncSecondary)
                    .frame(width: 36, height: 36)
                    .background(Color.ncSurfaceContHigh, in: Circle())
            }
            .smoothButton()
            Button { Task { await social.accept(request.friendship) } } label: {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    .foregroundColor(.ncOnPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.ncPrimary, in: Circle())
            }
            .smoothButton()
        }
        .padding(12)
        .glassCard(radius: 16)
    }
}

private struct SentRow: View {
    let request: FriendRequest
    @StateObject private var social = SocialService.shared

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: request.profile.avatarUrl, name: request.profile.name, size: 36)
            Text(request.profile.name).font(.system(size: 14, weight: .medium)).foregroundColor(.ncPrimary)
            Spacer()
            Button("Cancel") { Task { await social.removeFriendship(request.friendship) } }
                .font(.system(size: 13, weight: .medium))
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
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: compact ? 24 : 40, weight: .light)).foregroundColor(.ncOutline)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
            Text(message).font(.system(size: 13)).foregroundColor(.ncSecondary).multilineTextAlignment(.center)
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
