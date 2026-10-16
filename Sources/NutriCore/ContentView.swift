import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    init() {
        // Hide native tab bar - replaced by PrimalLightTabBar
        let transparent = UITabBarAppearance()
        transparent.configureWithTransparentBackground()
        transparent.backgroundColor = .clear
        transparent.shadowColor = .clear
        UITabBar.appearance().standardAppearance = transparent
        UITabBar.appearance().scrollEdgeAppearance = transparent
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                DashboardView(onProfile: { selectedTab = 5 }, onRaw: { selectedTab = 2 }).tag(0)
                CameraView().tag(1)
                RawHubView().tag(2)
                SunView().tag(3)
                FriendsView().tag(4)
                ProfileView().tag(5)
            }
            .ignoresSafeArea(edges: .bottom)

            PrimalLightTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color.ncBg.ignoresSafeArea())
    }
}

// MARK: - Tab Bar
struct PrimalLightTabBar: View {
    @Binding var selectedTab: Int
    @Namespace private var indicator

    private let tabs: [(icon: String, activeIcon: String, label: String)] = [
        ("sparkles",             "sparkles",                "Today"),
        ("camera.viewfinder",    "camera.viewfinder",       "AI Scan"),
        ("flame",               "flame.fill",              "Raw"),
        ("sun.max",              "sun.max.fill",            "Sun"),
        ("person.2",             "person.2.fill",           "Friends"),
        ("person",               "person.fill",             "Profile"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                let isSelected = selectedTab == index
                Button {
                    guard selectedTab != index else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { selectedTab = index }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                            .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                            .symbolEffect(.bounce, value: isSelected)
                        Text(tab.label)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    }
                    .foregroundColor(isSelected ? .ncPrimary : .ncSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .matchedGeometryEffect(id: "tabIndicator", in: indicator)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(TabButtonStyle())
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 26) // home indicator
        .background(
            Color.ncBg.opacity(0.82)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1), alignment: .top)
    }
}

/// Tab items only dip slightly on press; selection feedback is handled by the indicator.
private struct TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Legacy Logo Mark stub for other views
struct PrimalLogoMark: View {
    var body: some View {
        Circle().fill(Color.ncPrimary).frame(width: 48, height: 48)
            .overlay(Image(systemName: "p.circle.fill").font(.system(size: 24)).foregroundColor(.ncOnPrimary))
    }
}
