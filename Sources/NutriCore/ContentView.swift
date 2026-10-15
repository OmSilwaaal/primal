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
                DashboardView(onScan: { selectedTab = 1 }, onProfile: { selectedTab = 4 }).tag(0)
                CameraView().tag(1)
                SearchView().tag(2)
                PlacesMapView().tag(3)
                ProfileView().tag(4)
            }
            .ignoresSafeArea(edges: .bottom)

            PrimalLightTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.light) // Force light mode for the AI theme
    }
}

// MARK: - Primal Light Tab Bar (AI Theme)
struct PrimalLightTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(icon: String, activeIcon: String, label: String)] = [
        ("sparkles",             "sparkles",                "Today"),
        ("camera.viewfinder",    "camera.viewfinder",       "AI Scan"),
        ("magnifyingglass",      "magnifyingglass",         "Search"),
        ("map",                  "map.fill",                "Places"),
        ("person",               "person.fill",             "Profile"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = index
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selectedTab == index ? tab.activeIcon : tab.icon)
                            .font(.system(size: 24, weight: selectedTab == index ? .semibold : .regular))
                            .foregroundColor(selectedTab == index ? .ncPrimary : .ncSecondary)

                        Text(tab.label)
                            .font(.system(size: 11, weight: selectedTab == index ? .semibold : .regular))
                            .foregroundColor(selectedTab == index ? .ncPrimary : .ncSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 28) // safe area padding
                }
                .smoothButton()
            }
        }
        .background(
            Color.ncBg.opacity(0.9)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .light)
        )
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.04))
                .frame(height: 1),
            alignment: .top
        )
    }
}

// MARK: - Legacy Logo Mark stub for other views
struct PrimalLogoMark: View {
    var body: some View {
        Circle().fill(Color.ncPrimary).frame(width: 48, height: 48)
            .overlay(Image(systemName: "p.circle.fill").font(.system(size: 24)).foregroundColor(.white))
    }
}
