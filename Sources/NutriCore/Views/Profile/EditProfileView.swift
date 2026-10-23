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
        RawScreen(title: "Edit profile", subtitle: "Public profile") {
                    avatarBlock

                    VStack(spacing: 28) {
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
                        Text(message).font(.ui(size: 13)).foregroundColor(.ncError).multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView().tint(.ncOnPrimary) } else { Text("Save changes") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving || isUploading)
        }
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private var avatarBlock: some View {
        HStack(spacing: 20) {
            ZStack {
                AvatarView(url: social.myProfile?.avatarUrl, name: displayName.isEmpty ? username : displayName, size: 96)
                    .opacity(isUploading ? 0.4 : 1)
                if isUploading { ProgressView() }
            }
            VStack(alignment: .leading, spacing: 12) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text(social.myProfile?.avatarUrl == nil ? "Add photo" : "Change photo")
                        .spacedCaps(12).fontWeight(.bold).foregroundColor(.ncPrimary)
                }
                if social.myProfile?.avatarUrl != nil {
                    Button("Remove") { Task { await social.removeAvatar() } }
                        .font(.ui(size: 14, weight: .medium)).foregroundColor(.ncSecondary)
                }
            }
            Spacer()
        }
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
            FieldLabel(text: label)
            content
                .font(.ui(size: 17))
                .foregroundColor(.ncPrimary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Hairline(opacity: 0.22) }
            if let footer {
                Text(footer).font(.ui(size: 12)).foregroundColor(.ncSecondary).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
