import SwiftUI

/// Alternate app icons: the ᛉ on each backdrop and on solid colours. iOS confirms the change with its own alert.
/// Locked without Vitalis Pro: the icons show dimmed with a lock, and tapping one calls `onLocked` (the plans).
struct AppIconPicker: View {
    var locked = false
    var onLocked: () -> Void = {}

    /// nil is the primary icon (forest).
    private let options: [(name: String?, label: String, preview: String)] = [
        (nil, "Forest", "IconPreview-Forest"),
        ("AppIcon-Ink", "Ink", "IconPreview-Ink"),
        ("AppIcon-Paper", "Paper", "IconPreview-Paper"),
        ("AppIcon-Ember", "Ember", "IconPreview-Ember"),
        ("AppIcon-Moss", "Moss", "IconPreview-Moss"),
        ("AppIcon-Desert", "Desert", "IconPreview-Desert"),
        ("AppIcon-Ocean", "Ocean", "IconPreview-Ocean"),
        ("AppIcon-Fog", "Fog", "IconPreview-Fog"),
        ("AppIcon-Night", "Night", "IconPreview-Night"),
    ]
    @State private var current = UIApplication.shared.alternateIconName
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 14)], spacing: 16) {
                ForEach(options, id: \.label) { option in
                    let selected = option.name == current
                    Button {
                        if locked { Haptics.tap(); onLocked(); return }
                        guard !selected else { return }
                        UIApplication.shared.setAlternateIconName(option.name) { err in
                            Task { @MainActor in
                                if let err { error = err.localizedDescription } else { current = option.name; Haptics.success() }
                            }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(option.preview).resizable().scaledToFit()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 13.5, style: .continuous)
                                    .strokeBorder(Mono.text, lineWidth: selected ? 2 : 0).padding(-4))
                                .opacity(locked && !selected ? 0.4 : 1)
                                .overlay(alignment: .bottomTrailing) {
                                    if locked && !selected {
                                        Image(systemName: "lock.fill").font(.ui(size: 10, weight: .bold))
                                            .foregroundColor(Mono.onWhite)
                                            .frame(width: 22, height: 22)
                                            .background(Circle().fill(Mono.text))
                                            .offset(x: 6, y: 6)
                                    }
                                }
                            Text(option.label).font(.mono(11)).foregroundColor(selected ? Mono.text : Mono.label)
                        }
                        .frame(minWidth: 72, minHeight: 88)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.label) icon")
                    .accessibilityHint(locked && !selected ? "Requires Vitalis Pro" : "")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if let error { Text(error).font(.ui(size: 13)).foregroundColor(.ncEmber) }
        }
        .padding(.vertical, 6)
    }
}
