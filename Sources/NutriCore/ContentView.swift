import SwiftUI

enum AppTab: Int, Hashable, Comparable {
    case home, map, scan, data, profile
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Screens that used to be tabs. They're pushed onto the Home or Profile navigation stack, so they get the
/// system back button (named after the screen they came from) and swipe-from-the-edge to go back.
enum SecondaryScreen: Hashable { case raw, sun, friends }

extension SecondaryScreen {
    @ViewBuilder var destination: some View {
        switch self {
        case .raw: RawHubView().pushedScreen()
        case .sun: SunView().pushedScreen()
        case .friends: FriendsView().pushedScreen()
        }
    }
}

extension View {
    /// The root of a tab's NavigationStack: lets ContentView's still backdrop show through (iOS 18+). iOS 17 can't
    /// clear the stack's background, so there the tab draws its own copy, which moves with the tab transition.
    @ViewBuilder func sharedBackdropRoot() -> some View {
        if #available(iOS 18.0, *) {
            containerBackground(.clear, for: .navigation)
        } else {
            background { AppBackdrop() }
        }
    }

    /// A screen pushed onto a stack: the system navigation bar with only its back button, no background,
    /// so the screen's own header and the backdrop show through.
    func pushedScreen() -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

struct ContentView: View {
    @State private var tab: AppTab
    /// Which way the last tab change went, so screens glide in from the side of the tab that was tapped.
    @State private var forward = true
    @State private var showSearch = false
    @State private var childHidesTabBar = false

    init(initialTab: AppTab = .home) { _tab = State(initialValue: initialTab) }

    var body: some View {
        ZStack(alignment: .bottom) {
            // One backdrop for every tab, outside the transition, so only the content glides when the tab changes
            // and the photo never slides or zooms. Pushed screens and sheets still draw their own.
            AppBackdrop()

            Group {
                switch tab {
                case .home: DashboardView(onSearch: { showSearch = true }, onOpenProfile: { select(.profile) })
                case .map: PlacesMapView()
                case .scan: CameraView(onClose: { select(.home) })
                case .data: MicronutrientsView()
                case .profile: ProfileView()
                }
            }
            .id(tab)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: forward ? 36 : -36)).combined(with: .scale(scale: 0.985)),
                removal: .opacity.combined(with: .offset(x: forward ? -36 : 36))
            ))
            .ignoresSafeArea(edges: .bottom)

            if !childHidesTabBar {
                VitalisTabBar(selected: tab) { select($0) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(35)
            }

            ToastOverlay().zIndex(60)
        }
        .onPreferenceChange(HidesTabBarKey.self) { hidden in
            withAnimation(.easeOut(duration: 0.2)) { childHidesTabBar = hidden }
        }
        // A standard sheet: swipe down to dismiss, like any iOS search or compose screen.
        .sheet(isPresented: $showSearch) {
            SearchView(onClose: { showSearch = false })
                .presentationBackground(Color.ncBg)
        }
        .tint(.ncPrimary)
        .background(Color.ncBg.ignoresSafeArea())
    }

    private func select(_ new: AppTab) {
        guard new != tab else { return }
        Haptics.selection()
        // Set the direction first, then change tab on the next pass, so the outgoing screen's removal
        // transition already knows which way to go.
        forward = new > tab
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.38)) { tab = new }
        }
    }
}

// MARK: - Tab bar
/// Floating glass island 14 pt from the edges: Liquid Glass on iOS 26, blurred material before that.
/// Five equal tabs, each an SF Symbol over its label; the selected one fills its symbol and sits on a soft
/// translucent highlight that slides between tabs. Scan, in the middle, is a moss-green tile.
///
/// Like the system Liquid Glass tab bar, it can be scrubbed: press anywhere on it and a clear glass lens appears
/// under your finger, the island swells slightly, and the tab under the lens grows. Slide along the bar to move the
/// lens (a tick as it crosses each tab) and let go to switch. The gesture only covers the island itself, so it never
/// takes drags from content above it (the map's filter wheel).
struct VitalisTabBar: View {
    let selected: AppTab
    let onSelect: (AppTab) -> Void
    @Namespace private var indicator
    /// The finger's x along the bar while pressing or scrubbing; nil when not touching.
    @State private var touchX: CGFloat?
    @State private var hovered: AppTab?
    @State private var barWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let inset: CGFloat = 5
    private let tabs: [(tab: AppTab, label: String, icon: String, selectedIcon: String)] = [
        (.home, "Home", "house", "house.fill"),
        (.map, "Map", "map", "map.fill"),
        (.scan, "Scan", "viewfinder", "viewfinder"),
        (.data, "Data", "chart.bar", "chart.bar.fill"),
        (.profile, "Profile", "person", "person.fill"),
    ]

    private var itemWidth: CGFloat { max(1, (barWidth - inset * 2) / CGFloat(tabs.count)) }

    private func tab(at x: CGFloat) -> AppTab {
        let i = Int(((x - inset) / itemWidth).rounded(.down))
        return tabs[min(tabs.count - 1, max(0, i))].tab
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.tab) { item in
                let on = selected == item.tab
                let lifted = hovered == item.tab
                // Buttons stay for VoiceOver, Switch Control and keyboards; touch goes through the scrub gesture.
                Button { onSelect(item.tab) } label: {
                    Group {
                        if item.tab == .scan { scanTile } else { tabLabel(item, on: on) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .scaleEffect(lifted && !reduceMotion ? 1.22 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.62), value: lifted)
                    .background {
                        if on && touchX == nil && item.tab != .scan {
                            Capsule().fill(Color.white.opacity(0.16))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                                .matchedGeometryEffect(id: "tab", in: indicator)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(on ? .isSelected : [])
                // Labels stay at standard size (like the system tab bar); long-press shows them enlarged.
                .accessibilityShowsLargeContentViewer {
                    Image(systemName: item.selectedIcon)
                    Text(item.label)
                }
            }
        }
        .padding(inset)
        .background { lens }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selected)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: touchX == nil)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .modifier(GlassIsland())
        .scaleEffect(touchX != nil && !reduceMotion ? 1.025 : 1)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        .highPriorityGesture(scrub)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func tabLabel(_ item: (tab: AppTab, label: String, icon: String, selectedIcon: String), on: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: on ? item.selectedIcon : item.icon)
                .font(.system(size: 19, weight: on ? .semibold : .regular))
                .symbolEffect(.bounce, value: on)
                .frame(height: 24)
            Text(item.label.uppercased())
                .font(.system(size: 10, weight: on ? .bold : .semibold)).tracking(0.6)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundColor(on ? .ncPrimary : .ncPrimary.opacity(0.6))
    }

    /// Scan: a clean moss tile with a soft glow of its own colour, so the camera reads as the bar's main action.
    private var scanTile: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        return Image(systemName: "viewfinder")
            .font(.system(size: 19, weight: .semibold))
            .foregroundColor(.ncOnPrimary)
            .frame(width: 48, height: 46)
            .background {
                shape.fill(LinearGradient(colors: [Color.ncMoss, Color(hex: "#6F9A5C")],
                                          startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
            }
            .shadow(color: Color.ncMoss.opacity(0.5), radius: 12, y: 2)
    }

    /// The clear glass bubble that follows the finger, a little taller than the island like the system's.
    @ViewBuilder private var lens: some View {
        if let touchX {
            let w = itemWidth + 14
            let x = min(max(touchX, inset + itemWidth / 2), barWidth - inset - itemWidth / 2)
            LensBubble()
                .frame(width: w, height: 66)
                .position(x: x, y: 31)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = value.location.x
                if touchX == nil { Haptics.tap() }
                touchX = x
                let t = tab(at: x)
                if t != hovered {
                    if hovered != nil { Haptics.selection() }
                    hovered = t
                }
            }
            .onEnded { value in
                let t = tab(at: value.location.x)
                touchX = nil
                hovered = nil
                onSelect(t)
            }
    }
}

/// The scrub lens: clear Liquid Glass on iOS 26 (it bends what's under it), a bright-edged clear capsule before that.
private struct LensBubble: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassSheen(in: Capsule(), strength: 1)
                .glassEffect(.clear, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        } else {
            Capsule().fill(Color.white.opacity(0.1))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .glassSheen(in: Capsule(), strength: 1)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .environment(\.colorScheme, .dark)
        }
    }
}

/// Liquid Glass where available; otherwise a thin blurred material with a hairline edge and soft shadow.
private struct GlassIsland: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            // Accessibility settings: an opaque island with a clear edge.
            content
                .background(Color.ncSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(contrast == .increased ? 0.5 : 0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        } else if #available(iOS 26.0, *) {
            // Not .interactive(): interactive glass catches drags ~24 pt beyond its edge and scrubs between tabs,
            // which stole horizontal drags from content just above the bar (the map's filter wheel).
            content.glassSheen(in: Capsule(), strength: 0.7).glassEffect(.regular, in: Capsule())
        } else {
            content
                .glassSheen(in: Capsule(), strength: 0.7)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        }
    }
}

