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
            Group {
                switch tab {
                case .home: DashboardView(onSearch: { showSearch = true })
                case .map: PlacesMapView()
                case .scan: CameraView()
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
/// translucent highlight that slides between tabs.
struct VitalisTabBar: View {
    let selected: AppTab
    let onSelect: (AppTab) -> Void
    @Namespace private var indicator

    private let tabs: [(tab: AppTab, label: String, icon: String, selectedIcon: String)] = [
        (.home, "Home", "house", "house.fill"),
        (.map, "Map", "map", "map.fill"),
        (.scan, "Scan", "viewfinder", "viewfinder"),
        (.data, "Data", "chart.bar", "chart.bar.fill"),
        (.profile, "Profile", "person", "person.fill"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.tab) { item in
                let on = selected == item.tab
                Button { onSelect(item.tab) } label: {
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
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if on {
                            Capsule().fill(Color.white.opacity(0.16))
                                .overlay(ChromaticEdge(shape: Capsule(), strength: 0.7))
                                .matchedGeometryEffect(id: "tab", in: indicator)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(TabButtonStyle())
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(on ? .isSelected : [])
                // Labels stay at standard size (like the system tab bar); long-press shows them enlarged.
                .accessibilityShowsLargeContentViewer {
                    Image(systemName: item.selectedIcon)
                    Text(item.label)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selected)
        .padding(5)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .modifier(GlassIsland())
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
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
            content
                .glassEffect(.regular, in: Capsule())
                .overlay(ChromaticEdge(shape: Capsule()))
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .overlay(ChromaticEdge(shape: Capsule()))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        }
    }
}

/// Chromatic aberration at a glass edge: light splits into a warm fringe on the upper-left rim and a cool one on
/// the lower-right, each nudged a fraction of a point apart, plus a thin specular highlight. Screen-blended so it
/// only ever brightens what's behind it. Off when Reduce Transparency or Increase Contrast is on.
struct ChromaticEdge<S: InsettableShape>: View {
    let shape: S
    var strength: Double = 1
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if !reduceTransparency && contrast != .increased {
            ZStack {
                shape.strokeBorder(
                    LinearGradient(colors: [Color(red: 1, green: 0.28, blue: 0.42).opacity(0.65 * strength), .clear],
                                   startPoint: .topLeading, endPoint: .init(x: 0.6, y: 0.9)),
                    lineWidth: 1.5)
                    .offset(x: -0.9, y: -0.6)
                shape.strokeBorder(
                    LinearGradient(colors: [.clear, Color(red: 0.25, green: 0.7, blue: 1).opacity(0.65 * strength)],
                                   startPoint: .init(x: 0.4, y: 0.1), endPoint: .bottomTrailing),
                    lineWidth: 1.5)
                    .offset(x: 0.9, y: 0.6)
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.38 * strength), .white.opacity(0.04), .white.opacity(0.16 * strength)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            }
            .blur(radius: 0.5)
            .blendMode(.screen)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Tab items only dip slightly on press.
private struct TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
