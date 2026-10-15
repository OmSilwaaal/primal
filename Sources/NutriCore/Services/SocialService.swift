import Foundation
import Supabase
import UIKit

/// Profile, friends and shared meals, backed by Supabase (see supabase/migrations/*_social.sql).
@MainActor
final class SocialService: ObservableObject {
    static let shared = SocialService()
    private init() {}

    @Published private(set) var myProfile: PublicProfile?
    @Published private(set) var friends: [BasicProfile] = []
    @Published private(set) var incoming: [FriendRequest] = []
    @Published private(set) var outgoing: [FriendRequest] = []
    @Published private(set) var friendCalories: [UUID: Double] = [:] // today, per friend
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var friendships: [Friendship] = []

    var myId: UUID? { supabase.auth.currentUser?.id }

    // MARK: - Bootstrap

    /// Loads (or creates) the signed-in user's profile and their friend graph.
    func bootstrap() async {
        guard myId != nil else { reset(); return }
        await loadMyProfile()
        await refreshFriends()
    }

    func reset() {
        myProfile = nil
        friends = []
        incoming = []
        outgoing = []
        friendCalories = [:]
        friendships = []
    }

    private func loadMyProfile() async {
        guard let me = myId else { return }
        do {
            let rows: [PublicProfile] = try await supabase.from("public_profiles")
                .select().eq("user_id", value: me.uuidString).limit(1).execute().value
            if let existing = rows.first {
                myProfile = existing
            } else {
                myProfile = try await createProfile(for: me)
            }
            syncLocalName()
        } catch {
            errorMessage = "Couldn't load your profile."
            print("loadMyProfile: \(error)")
        }
    }

    private func createProfile(for me: UUID) async throws -> PublicProfile {
        let user = supabase.auth.currentUser
        let meta = user?.userMetadata
        let fullName = meta?["full_name"]?.stringValue ?? meta?["name"]?.stringValue ?? ""
        let seed = fullName.isEmpty ? (user?.email?.split(separator: "@").first.map(String.init) ?? "user") : fullName
        let base = String(seed.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(14))
        let stem = base.count >= 3 ? base : "user"

        // Usernames are unique; retry with a different suffix on collision.
        for _ in 0..<5 {
            let candidate = PublicProfile(
                userId: me, username: "\(stem)\(Int.random(in: 1000...9999))", displayName: fullName,
                bio: "", avatarUrl: nil, isPrivate: false, mealVisibility: .friends)
            do {
                try await supabase.from("public_profiles").insert(candidate).execute()
                return candidate
            } catch {
                if !Self.isUniqueViolation(error) { throw error }
            }
        }
        throw NSError(domain: "Social", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't pick a username."])
    }

    /// Keeps the on-device profile name in step with the account name.
    private func syncLocalName() {
        UserDefaults.standard.set(myProfile?.displayName ?? "", forKey: "accountDisplayName")
    }

    // MARK: - Editing my profile

    struct ProfileEdit {
        var displayName: String
        var username: String
        var bio: String
        var isPrivate: Bool
        var mealVisibility: MealVisibility
    }

    /// Returns an error message, or nil on success.
    @discardableResult
    func saveProfile(_ edit: ProfileEdit) async -> String? {
        guard var profile = myProfile else { return "Profile not loaded." }
        let username = edit.username.lowercased().trimmingCharacters(in: .whitespaces)
        guard username.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            return "Username must be 3–20 letters, numbers or underscores."
        }
        let previousVisibility = profile.mealVisibility
        profile.username = username
        profile.displayName = edit.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.bio = String(edit.bio.prefix(160))
        profile.isPrivate = edit.isPrivate
        profile.mealVisibility = edit.mealVisibility

        do {
            try await supabase.from("public_profiles").update(profile).eq("user_id", value: profile.userId.uuidString).execute()
            myProfile = profile
            syncLocalName()
            if edit.mealVisibility == .nobody && previousVisibility != .nobody {
                await purgeSharedMeals()
            }
            return nil
        } catch {
            return Self.isUniqueViolation(error) ? "That username is taken." : "Couldn't save changes. Try again."
        }
    }

    func uploadAvatar(_ image: UIImage) async -> String? {
        guard let me = myId, var profile = myProfile else { return "Not signed in." }
        // Square-crop and shrink: avatars are shown small, so don't store a 12 MP photo.
        guard let data = Self.avatarJPEG(from: image) else { return "Couldn't read that image." }
        let path = "\(me.uuidString)/avatar.jpg"
        do {
            try await supabase.storage.from("avatars")
                .upload(path, data: data, options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true))
            let base = try supabase.storage.from("avatars").getPublicURL(path: path)
            // Query string busts AsyncImage/URLCache so the new picture shows immediately.
            profile.avatarUrl = "\(base.absoluteString)?v=\(Int(Date().timeIntervalSince1970))"
            try await supabase.from("public_profiles").update(profile).eq("user_id", value: me.uuidString).execute()
            myProfile = profile
            return nil
        } catch {
            print("uploadAvatar: \(error)")
            return "Couldn't upload your photo."
        }
    }

    func removeAvatar() async {
        guard let me = myId, var profile = myProfile else { return }
        _ = try? await supabase.storage.from("avatars").remove(paths: ["\(me.uuidString)/avatar.jpg"])
        profile.avatarUrl = nil
        if (try? await supabase.from("public_profiles").update(profile).eq("user_id", value: me.uuidString).execute()) != nil {
            myProfile = profile
        }
    }

    private static func avatarJPEG(from image: UIImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        let target = CGSize(width: 512, height: 512)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let scale = target.width / side
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(x: (target.width - drawSize.width) / 2,
                                  y: (target.height - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }

    // MARK: - Friends

    func refreshFriends() async {
        guard let me = myId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [Friendship] = try await supabase.from("friendships")
                .select().or("requester_id.eq.\(me.uuidString),addressee_id.eq.\(me.uuidString)")
                .execute().value
            friendships = rows

            let otherIds = rows.map { $0.other(than: me) }
            let cards = try await basicProfiles(otherIds)
            let byId = Dictionary(uniqueKeysWithValues: cards.map { ($0.userId, $0) })

            friends = rows.filter { $0.status == "accepted" }
                .compactMap { byId[$0.other(than: me)] }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            incoming = rows.filter { $0.status == "pending" && $0.addresseeId == me }
                .compactMap { f in byId[f.requesterId].map { FriendRequest(friendship: f, profile: $0) } }
            outgoing = rows.filter { $0.status == "pending" && $0.requesterId == me }
                .compactMap { f in byId[f.addresseeId].map { FriendRequest(friendship: f, profile: $0) } }

            await loadFriendCalories()
        } catch {
            errorMessage = "Couldn't load friends."
            print("refreshFriends: \(error)")
        }
    }

    private func basicProfiles(_ ids: [UUID]) async throws -> [BasicProfile] {
        guard !ids.isEmpty else { return [] }
        return try await supabase.rpc("profiles_basic", params: ["ids": ids.map(\.uuidString)]).execute().value
    }

    private func loadFriendCalories() async {
        guard !friends.isEmpty else { friendCalories = [:]; return }
        let start = Calendar.current.startOfDay(for: .now)
        do {
            let meals: [SharedMeal] = try await supabase.from("shared_meals")
                .select().in("user_id", values: friends.map(\.userId.uuidString))
                .gte("eaten_at", value: start).execute().value
            friendCalories = Dictionary(grouping: meals, by: \.userId).mapValues { $0.reduce(0) { $0 + $1.calories } }
        } catch {
            print("loadFriendCalories: \(error)")
        }
    }

    func search(_ query: String) async -> [BasicProfile] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        do {
            return try await supabase.rpc("search_profiles", params: ["q": q]).execute().value
        } catch {
            print("search: \(error)")
            return []
        }
    }

    enum Relation { case none, friend, requestSent, requestReceived(Friendship) }

    func relation(to userId: UUID) -> Relation {
        guard let me = myId, let f = friendships.first(where: { $0.other(than: me) == userId }) else { return .none }
        if f.status == "accepted" { return .friend }
        return f.requesterId == me ? .requestSent : .requestReceived(f)
    }

    func sendRequest(to userId: UUID) async {
        guard let me = myId else { return }
        struct NewRequest: Encodable { let requester_id: UUID; let addressee_id: UUID }
        do {
            try await supabase.from("friendships").insert(NewRequest(requester_id: me, addressee_id: userId)).execute()
            await refreshFriends()
        } catch {
            errorMessage = Self.isUniqueViolation(error) ? "A request already exists." : "Couldn't send request."
        }
    }

    func accept(_ friendship: Friendship) async {
        struct Accept: Encodable { let status = "accepted" }
        do {
            try await supabase.from("friendships").update(Accept()).eq("id", value: friendship.id.uuidString).execute()
            await refreshFriends()
        } catch { errorMessage = "Couldn't accept request." }
    }

    /// Declines a request, cancels one you sent, or removes a friend.
    func removeFriendship(_ friendship: Friendship) async {
        do {
            try await supabase.from("friendships").delete().eq("id", value: friendship.id.uuidString).execute()
            await refreshFriends()
        } catch { errorMessage = "Couldn't update friendship." }
    }

    func removeFriendship(with userId: UUID) async {
        guard let me = myId, let f = friendships.first(where: { $0.other(than: me) == userId }) else { return }
        await removeFriendship(f)
    }

    // MARK: - A friend's profile and meals

    func fullProfile(_ userId: UUID) async -> PublicProfile? {
        let rows: [PublicProfile]? = try? await supabase.from("public_profiles")
            .select().eq("user_id", value: userId.uuidString).limit(1).execute().value
        return rows?.first
    }

    func meals(for userId: UUID, on day: Date) async -> [SharedMeal] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let rows: [SharedMeal]? = try? await supabase.from("shared_meals")
            .select().eq("user_id", value: userId.uuidString)
            .gte("eaten_at", value: start).lt("eaten_at", value: end)
            .order("eaten_at", ascending: true).execute().value
        return rows ?? []
    }

    // MARK: - Publishing my meals

    private var sharingEnabled: Bool { myProfile.map { $0.mealVisibility != .nobody } ?? false }

    func publish(_ meal: MealEntry) {
        guard sharingEnabled, let me = myId else { return }
        let row = SharedMeal(meal, userId: me)
        Task { _ = try? await supabase.from("shared_meals").upsert(row).execute() }
    }

    func unpublish(mealId: UUID) {
        guard myId != nil else { return }
        Task { _ = try? await supabase.from("shared_meals").delete().eq("id", value: mealId.uuidString).execute() }
    }

    /// Re-sends the last week so meals logged offline (or before sharing was enabled) catch up.
    func backfill(_ meals: [MealEntry]) async {
        guard sharingEnabled, let me = myId, !meals.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let rows = meals.filter { $0.date >= cutoff }.map { SharedMeal($0, userId: me) }
        guard !rows.isEmpty else { return }
        _ = try? await supabase.from("shared_meals").upsert(rows).execute()
    }

    private func purgeSharedMeals() async {
        guard let me = myId else { return }
        _ = try? await supabase.from("shared_meals").delete().eq("user_id", value: me.uuidString).execute()
    }

    // MARK: - Helpers

    private static func isUniqueViolation(_ error: Error) -> Bool {
        (error as? PostgrestError)?.code == "23505"
    }
}
