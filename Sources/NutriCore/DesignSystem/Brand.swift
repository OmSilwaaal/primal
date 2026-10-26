import SwiftUI
import AVFoundation

// MARK: - Brand moments built on the ᛉ mark (AlgizMark)

/// Loading indicator for waits that aren't inside a button: a faint ᛉ with light sweeping up through it.
/// Buttons keep the system spinner, which people recognise as "pressed, working".
struct VitalisSpinner: View {
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        ZStack {
            AlgizMark().fill(Color.ncPrimary.opacity(0.22))
            AlgizMark().fill(Color.ncPrimary)
                .mask {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white, .clear], startPoint: .bottom, endPoint: .top)
                            .frame(height: geo.size.height * 0.7)
                            .offset(y: phase ? -geo.size.height * 0.7 : geo.size.height)
                    }
                }
                .opacity(reduceMotion ? (phase ? 0.9 : 0.3) : 1)
        }
        .frame(width: size * 0.78, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: reduceMotion ? 1.2 : 1.1).repeatForever(autoreverses: reduceMotion)) { phase = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

/// Nothing-here state: a large faint ᛉ behind one line of guidance and an optional action.
struct BrandEmptyState: View {
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text(message).font(.ui(size: 15)).foregroundColor(.ncSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(.vertical, 12)
        .background {
            AlgizMark().fill(Color.ncPrimary.opacity(0.06)).frame(width: 96, height: 124)
                .accessibilityHidden(true)
        }
    }
}

/// The opening animation. The launch screen shows the ᛉ upside down on ink; this takes over on the first frame
/// in exactly that state, flips the rune upright, then lifts it away as the ink dissolves into the app.
/// About 1.2 s, once per launch. With Reduce Motion it's a short cross-fade with no flip or scaling.
struct LaunchHandoff: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var upright = false
    @State private var leaving = false
    @State private var gone = false
    /// Only once per process: returning from the background doesn't replay it.
    private static var played = false

    var body: some View {
        if !gone && !Self.played {
            ZStack {
                Color(red: 10 / 255, green: 11 / 255, blue: 10 / 255)
                    .opacity(leaving ? 0 : 1)
                    .ignoresSafeArea()
                AlgizMark().fill(Color.ncPrimary)
                    .frame(width: 48, height: 62)
                    // Upside down = half a turn about the horizontal axis (the rune is left-right symmetric).
                    .rotation3DEffect(.degrees(upright || reduceMotion ? 0 : 180), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
                    .scaleEffect(leaving && !reduceMotion ? 1.6 : 1)
                    .blur(radius: leaving && !reduceMotion ? 6 : 0)
                    .opacity(leaving ? 0 : 1)
            }
            .allowsHitTesting(!leaving)
            .accessibilityHidden(true)
            .task { await play() }
        }
    }

    private func play() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(280))
        } else {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { upright = true }
            try? await Task.sleep(for: .milliseconds(560))
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.5)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(520))
        }
        Self.played = true
        gone = true
    }
}

/// The rune drawing itself in from the stem up: used for the login wordmark on first appearance.
struct RuneReveal: View {
    var width: CGFloat = 40
    var height: CGFloat = 52
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        AlgizMark().fill(Color.ncPrimary)
            .mask(alignment: .bottom) {
                Rectangle().frame(height: shown || reduceMotion ? height : 0)
            }
            .frame(width: width, height: height)
            .onAppear { withAnimation(.easeOut(duration: 0.7).delay(0.15)) { shown = true } }
            .accessibilityHidden(true)
    }
}

/// The optional ᛉ sound: a short low knock for positive moments. Off by default (Settings → Sounds); it uses the
/// ambient audio category, so it never plays over the silent switch or interrupts other audio.
enum BrandSound {
    static let enabledKey = "brandSoundEnabled"
    private static var player: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "knock", withExtension: "wav") else { return nil }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.volume = 0.6
        p?.prepareToPlay()
        return p
    }()

    static func play() {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return }
        player?.currentTime = 0
        player?.play()
    }
}
