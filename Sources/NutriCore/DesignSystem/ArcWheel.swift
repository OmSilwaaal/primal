import SwiftUI

/// Items on a dial: scroll sideways and the one that snaps to the centre is selected. Items further from the
/// centre drop, tilt, shrink and fade along an arc. Used for picking a water amount.
struct ArcWheel<Item: Hashable, Label: View>: View {
    let items: [Item]
    @Binding var selection: Item
    var itemWidth: CGFloat = 104
    var height: CGFloat = 64
    /// Called when the already-centred item is tapped.
    var onTapSelected: (() -> Void)? = nil
    @ViewBuilder let label: (Item, Bool) -> Label

    @State private var centered: Item?

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items, id: \.self) { item in
                        Button {
                            if item == selection { onTapSelected?() } else { withAnimation(.smooth) { centered = item } }
                        } label: {
                            label(item, item == selection).frame(width: itemWidth)
                        }
                        .buttonStyle(.plain)
                        .visualEffect { content, proxy in
                            // -1 at the left edge of the wheel, 0 in the centre, 1 at the right edge.
                            let width = proxy.bounds(of: .scrollView)?.width ?? 1
                            let d = max(-1, min(1, (proxy.frame(in: .scrollView).midX - width / 2) / (width / 2)))
                            return content
                                .rotationEffect(.degrees(d * 16), anchor: .center)
                                .offset(y: d * d * 22)
                                .scaleEffect(1 - abs(d) * 0.18)
                                .opacity(1 - abs(d) * 0.55)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .safeAreaPadding(.horizontal, max(0, (geo.size.width - itemWidth) / 2))
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered, anchor: .center)
            .scrollClipDisabled()
        }
        .frame(height: height)
        .onAppear { centered = selection }
        .onChange(of: centered) { _, new in
            guard let new, new != selection else { return }
            Haptics.selection()
            selection = new
        }
        .onChange(of: selection) { _, new in
            if centered != new { withAnimation(.smooth) { centered = new } }
        }
    }
}
