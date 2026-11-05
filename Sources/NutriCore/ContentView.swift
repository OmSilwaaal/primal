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
    /// The kept-alive tabs opened so far.
    @State private var visited: Set<AppTab> = []
    /// A screen is pushed on Home's or Profile's stack (Settings, Goals): page swiping steps aside for its back-swipe.
    @State private var showsPushedScreen = false

    init(initialTab: AppTab = .home) { _tab = State(initialValue: initialTab) }

    var body: some View {
        ZStack(alignment: .bottom) {
            // One backdrop for every tab, outside the transition, so only the content glides when the tab changes
            // and the photo never slides or zooms. Pushed screens and sheets still draw their own.
            // On Data it becomes the centred card's scene, crossfading as the wheel turns.
            AppBackdrop(followsScenes: true)

            // Home, Data and Profile stay alive once opened: switching back is an instant cross-fade with nothing
            // rebuilt, reloaded or re-laid-out mid-animation (that rebuild was what made tabs stutter and shift).
            // Map and Scan are built fresh each time, so the camera and location stop when you leave them.
            ZStack {
                ForEach([AppTab.home, .data, .profile], id: \.self) { t in
                    if visited.contains(t) || tab == t {
                        page(t)
                            .opacity(tab == t ? 1 : 0)
                            .allowsHitTesting(tab == t)
                            .accessibilityHidden(tab != t)
                    }
                }
                if tab == .map { PlacesMapView().transition(.opacity) }
                if tab == .scan { CameraView(onClose: { select(.home) }).transition(.opacity) }
            }
            .ignoresSafeArea(edges: .bottom)
            // Swipe in from either edge to move to the next or previous page, like turning pages. Only the edges, so
            // it never fights the Data wheel, Home's date wheel or the map, which all swipe sideways themselves.
            .overlay {
                if !childHidesTabBar && !showsPushedScreen {
                    PageSwipeEdges { step($0) }
                }
            }

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
        .onPreferenceChange(ShowsPushedScreenKey.self) { showsPushedScreen = $0 }
        // A standard sheet: swipe down to dismiss, like any iOS search or compose screen.
        .sheet(isPresented: $showSearch) {
            SearchView(onClose: { showSearch = false })
                .presentationBackground(Color.ncBg)
        }
        .tint(Mono.text)
        .background(Color.ncBg.ignoresSafeArea())
        .onAppear {
            Backdrop.prewarm()
            SceneMixer.shared.active = tab == .data
        }
    }

    @ViewBuilder private func page(_ t: AppTab) -> some View {
        switch t {
        case .home: DashboardView(onSearch: { showSearch = true })
        case .data: MicronutrientsView()
        case .profile: ProfileView()
        default: EmptyView()
        }
    }

    /// The page `by` steps along the tab bar's order (Home, Map, Scan, Data, Profile), stopping at the ends.
    private func step(_ by: Int) {
        let order: [AppTab] = [.home, .map, .scan, .data, .profile]
        guard let i = order.firstIndex(of: tab), order.indices.contains(i + by) else { return }
        select(order[i + by])
    }

    private func select(_ new: AppTab) {
        guard new != tab else { return }
        Haptics.selection()
        // Set the direction first, then change tab on the next pass, so the outgoing screen's removal
        // transition already knows which way to go.
        forward = new > tab
        visited.insert(tab)
        visited.insert(new)
        withAnimation(.easeInOut(duration: 0.2)) { tab = new }
        // Data's scenes fade in and out a little slower than the content, so the photo change reads as one move.
        withAnimation(.smooth(duration: 0.6)) { SceneMixer.shared.active = new == .data }
    }
}

// MARK: - Page swiping

/// Set by Home and Profile while a screen is pushed on their stack.
struct ShowsPushedScreenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Two thin strips along the screen's sides that catch a sideways swipe starting there: in from the right edge is
/// the next page, in from the left the previous one. A flick counts, or a drag of about a fifth of the screen.
private struct PageSwipeEdges: View {
    let onStep: (Int) -> Void
    private let width: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            strip(direction: -1)
            Spacer(minLength: 0).allowsHitTesting(false)
            strip(direction: 1)
        }
        .ignoresSafeArea(edges: .horizontal)
        .accessibilityHidden(true)   // VoiceOver uses the tab bar
    }

    private func strip(direction: Int) -> some View {
        Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 14, coordinateSpace: .global)
                    .onEnded { value in
                        let dx = value.translation.width, dy = value.translation.height
                        let thrown = value.predictedEndTranslation.width
                        // Inwards from this edge: leftwards from the right edge, rightwards from the left.
                        let inward = direction > 0 ? -dx : dx
                        let inwardThrow = direction > 0 ? -thrown : thrown
                        guard abs(dx) > abs(dy) * 1.5, inward > 40 || inwardThrow > 140 else { return }
                        onStep(direction)
                    }
            )
    }
}

// MARK: - Tab bar
/// Floating glass island 14 pt from the edges: Liquid Glass on iOS 26, blurred material before that.
/// Five equal tabs, each an SF Symbol over an 11 pt label; the selected one is a solid white pill with dark text and
/// icon that slides between tabs. Monochrome.
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
                    tabLabel(item, on: on)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .scaleEffect(lifted && !reduceMotion ? 1.22 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.62), value: lifted)
                    .background {
                        if on && touchX == nil {
                            Capsule().fill(Mono.text)
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
        // The active pill hides while scrubbing (the lens takes over), so its dark ink switches back to white too.
        let solid = on && touchX == nil
        return VStack(spacing: 3) {
            Image(systemName: on ? item.selectedIcon : item.icon)
                .font(.system(size: 19, weight: on ? .semibold : .regular))
                .symbolEffect(.bounce, value: on)
                .frame(height: 24)
            Text(item.label)
                .font(.system(size: 11, weight: on ? .semibold : .medium))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundColor(solid ? Mono.onWhite : on ? Mono.text : Mono.label)
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
            // .clear with a light ink tint: as see-through as the rest of the app, labels still legible.
            content.glassSheen(in: Capsule(), strength: 0.7).glassEffect(.clear.tint(Mono.ink.opacity(0.18)), in: Capsule())
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

