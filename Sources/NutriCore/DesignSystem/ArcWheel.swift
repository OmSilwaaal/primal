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

// MARK: - Drum

extension View {
    /// Places a wheel item on a drum seen from the front, for a horizontal scroll row centred at `centerX` (global).
    /// Distance from the centre is arc length on the drum, so items bunch up, turn away and fade as they roll
    /// round the edge, rather than tilting.
    func drumEffect(centerX: CGFloat, radius: CGFloat) -> some View {
        visualEffect { content, proxy in
            let s = proxy.frame(in: .global).midX - centerX
            let angle = max(-1.4, min(1.4, s / radius))   // stop just short of edge-on
            let depth = cos(angle)                         // 1 facing us, ~0 at the rim
            return content
                .rotation3DEffect(.radians(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .scaleEffect(0.78 + 0.22 * depth)
                .offset(x: radius * sin(angle) - s)
                .opacity(abs(s / radius) > 1.4 ? 0 : pow(depth, 1.6))
        }
    }

    /// Fades a wheel's left and right rims so items melt away rather than stop at a hard edge.
    func drumRimFade() -> some View {
        mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                   .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .padding(.vertical, -20)
        }
    }
}
