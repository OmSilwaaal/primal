import SwiftUI

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
