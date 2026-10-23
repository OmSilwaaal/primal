import SwiftUI

enum AppTab: Hashable { case home, map, scan, data, profile }

/// Screens that used to be tabs. They open over the current tab with a BACK bar.
enum SecondaryScreen: Hashable { case raw, sun, friends }

struct ContentView: View {
    @State private var tab: AppTab
    @State private var secondary: SecondaryScreen?
    @State private var showSearch = false
    @State private var childHidesTabBar = false

    init(initialTab: AppTab = .home) { _tab = State(initialValue: initialTab) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let secondary {
                    secondaryView(secondary)
                } else {
                    switch tab {
                    case .home: DashboardView(onSearch: { open(search: true) }, onRaw: { secondary = .raw }, onSun: { secondary = .sun })
                    case .map: PlacesMapView()
                    case .scan: CameraView()
                    case .data: MicronutrientsView()
                    case .profile: ProfileView(onOpen: { secondary = $0 })
                    }
                }
            }
            .id(secondary.map { "\($0)" } ?? "\(tab)")
            .transaction { $0.animation = nil }
            .ignoresSafeArea(edges: .bottom)

            if showSearch {
                SearchView(onClose: { open(search: false) })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
            }

            if !showSearch && !childHidesTabBar {
                VitalisTabBar(selected: tab) { select($0) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(35)
            }

            ToastOverlay().zIndex(60)
        }
        .onPreferenceChange(HidesTabBarKey.self) { hidden in
            withAnimation(.easeOut(duration: 0.2)) { childHidesTabBar = hidden }
        }
        .background(Color.ncBg.ignoresSafeArea())
    }

    private func select(_ new: AppTab) {
        guard new != tab || secondary != nil else { return }
        Haptics.selection()
        secondary = nil
        tab = new
    }

    private func open(search: Bool) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { showSearch = search }
    }

    @ViewBuilder
    private func secondaryView(_ screen: SecondaryScreen) -> some View {
        Group {
            switch screen {
            case .raw: RawHubView()
            case .sun: SunView()
            case .friends: FriendsView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button("Back") { secondary = nil }.buttonStyle(.glass)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
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
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
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
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
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
