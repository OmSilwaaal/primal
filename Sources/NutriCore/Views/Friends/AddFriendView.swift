import SwiftUI

struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var social = SocialService.shared
    @State private var query = ""
    @State private var results: [BasicProfile] = []
    @State private var isSearching = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundColor(.ncSecondary)
                        TextField("", text: $query, prompt: Text("Search by name or username").foregroundColor(.ncSecondary))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .foregroundColor(.ncPrimary)
                        if isSearching { ProgressView().controlSize(.small) }
                    }
                    .padding(.horizontal, 14).frame(height: 46)
                    .background(Color.ncSurfaceContHigh, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(16)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(results) { profile in
                                NavigationLink(value: profile) { SearchRow(profile: profile) }
                                    .buttonStyle(SmoothButtonStyle())
                            }
                            if results.isEmpty && query.trimmingCharacters(in: .whitespaces).count >= 2 && !isSearching {
                                EmptyState(icon: "person.fill.questionmark", title: "No one found",
                                           message: "Check the spelling or ask your friend for their username.", compact: true)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("Add friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .navigationDestination(for: BasicProfile.self) { FriendProfileView(profile: $0) }
            .onAppear { focused = true }
        }
        .preferredColorScheme(.dark)
        // Re-runs (and cancels the previous run) on every keystroke; the sleep is the debounce.
        .task(id: query) {
            isSearching = false
            guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = await social.search(query)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }
}

private struct SearchRow: View {
    let profile: BasicProfile
    @StateObject private var social = SocialService.shared

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: profile.avatarUrl, name: profile.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.ncPrimary)
                    if profile.isPrivate {
                        Image(systemName: "lock.fill").font(.system(size: 10)).foregroundColor(.ncSecondary)
                    }
                }
                Text("@\(profile.username)").font(.system(size: 12)).foregroundColor(.ncSecondary)
            }
            Spacer()
            FriendActionButton(profile: profile)
        }
        .padding(12)
        .glassCard(radius: 16)
    }
}

/// Add / Requested / Accept / Friends, depending on the current relationship.
struct FriendActionButton: View {
    let profile: BasicProfile
    @StateObject private var social = SocialService.shared

    var body: some View {
        switch social.relation(to: profile.userId) {
        case .none:
            pill("Add", filled: true) { Task { await social.sendRequest(to: profile.userId) } }
        case .requestSent:
            pill("Requested", filled: false, action: nil)
        case .requestReceived(let friendship):
            pill("Accept", filled: true) { Task { await social.accept(friendship) } }
        case .friend:
            pill("Friends", filled: false, action: nil)
        }
    }

    private func pill(_ title: String, filled: Bool, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(filled ? .ncOnPrimary : .ncSecondary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(filled ? Color.ncPrimary : Color.ncSurfaceContHigh, in: Rectangle())
        }
        .smoothButton()
        .disabled(action == nil)
    }
}
