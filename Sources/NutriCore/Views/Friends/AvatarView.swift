import SwiftUI

/// Circular profile picture with an initials fallback.
struct AvatarView: View {
    let url: String?
    let name: String
    var size: CGFloat = 44

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        let text = String(letters).uppercased()
        return text.isEmpty ? String(name.drop(while: { !$0.isLetter }).prefix(1)).uppercased() : text
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.ncSurfaceContHigh)
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var placeholder: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundColor(.ncSecondary)
    }
}
