import SwiftUI
import PhotosUI

/// Edit the public profile: photo, name, username, bio.
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var social = SocialService.shared

    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var didLoad = false

    var body: some View {
        ZStack {
            Color.ncBg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    avatarBlock

                    VStack(spacing: 12) {
                        FieldRow(label: "Name") {
                            TextField("", text: $displayName, prompt: Text("Your name").foregroundColor(.ncOutline))
                                .textContentType(.name)
                        }
                        FieldRow(label: "Username") {
                            HStack(spacing: 2) {
                                Text("@").foregroundColor(.ncSecondary)
                                TextField("", text: $username, prompt: Text("username").foregroundColor(.ncOutline))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }
                        FieldRow(label: "Bio", footer: "\(bio.count)/160") {
                            TextField("", text: $bio, prompt: Text("A line about you").foregroundColor(.ncOutline), axis: .vertical)
                                .lineLimit(1...4)
                                .onChange(of: bio) { _, new in if new.count > 160 { bio = String(new.prefix(160)) } }
                        }
                    }

                    if let message {
                        Text(message).font(.system(size: 13)).foregroundColor(.ncError).multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView().tint(.ncOnPrimary) } else { Text("Save changes") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving || isUploading)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private var avatarBlock: some View {
        VStack(spacing: 12) {
            ZStack {
                AvatarView(url: social.myProfile?.avatarUrl, name: displayName.isEmpty ? username : displayName, size: 104)
                    .opacity(isUploading ? 0.4 : 1)
                if isUploading { ProgressView() }
            }
            HStack(spacing: 18) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text(social.myProfile?.avatarUrl == nil ? "Add photo" : "Change photo")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.ncPrimary)
                }
                if social.myProfile?.avatarUrl != nil {
                    Button("Remove") { Task { await social.removeAvatar() } }
                        .font(.system(size: 14, weight: .medium)).foregroundColor(.ncSecondary)
                }
            }
        }
        .padding(.top, 8)
    }

    private func load() {
        guard !didLoad, let p = social.myProfile else { return }
        displayName = p.displayName
        username = p.username
        bio = p.bio
        didLoad = true
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        message = nil
        defer { isUploading = false; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            message = "Couldn't read that photo."
            return
        }
        message = await social.uploadAvatar(image)
        if message == nil { Haptics.success() }
    }

    private func save() async {
        guard let current = social.myProfile else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }
        let error = await social.saveProfile(.init(
            displayName: displayName, username: username, bio: bio,
            isPrivate: current.isPrivate, mealVisibility: current.mealVisibility))
        if let error {
            message = error
        } else {
            Haptics.success()
            dismiss()
        }
    }
}

private struct FieldRow<Content: View>: View {
    let label: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1).foregroundColor(.ncSecondary)
            content
                .font(.system(size: 16))
                .foregroundColor(.ncPrimary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(radius: 3)
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundColor(.ncSecondary).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
