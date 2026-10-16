import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // A native TabView folds tabs beyond the fifth into a "More" list (which adds a back button),
            // so the selected screen is switched manually.
            Group {
                switch selectedTab {
                case 0: DashboardView(onProfile: { selectedTab = 5 }, onRaw: { selectedTab = 2 })
                case 1: CameraView()
                case 2: RawHubView()
                case 3: SunView()
                case 4: FriendsView()
                default: ProfileView()
                }
            }
            .transition(.opacity)
            .id(selectedTab)
            .ignoresSafeArea(edges: .bottom)

            PrimalLightTabBar(selectedTab: $selectedTab)
        }
        .background(Color.ncBg.ignoresSafeArea())
    }
}

// MARK: - Tab Bar
/// Floating island: Liquid Glass on iOS 26, blurred material before that. Only the selected tab shows its name.
struct PrimalLightTabBar: View {
    @Binding var selectedTab: Int
    @Namespace private var indicator

    private let tabs: [(icon: String, activeIcon: String, label: String)] = [
        ("sparkles",             "sparkles",                "Today"),
        ("camera.viewfinder",    "camera.viewfinder",       "Scan"),
        ("flame",                "flame.fill",              "Raw"),
        ("sun.max",              "sun.max.fill",            "Sun"),
        ("person.2",             "person.2.fill",           "Friends"),
        ("person",               "person.fill",             "Profile"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                let isSelected = selectedTab == index
                Button {
                    guard selectedTab != index else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { selectedTab = index }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                            .symbolEffect(.bounce, value: isSelected)
                        if isSelected {
                            Text(tab.label).font(.system(size: 11, weight: .heavy)).tracking(1.2).textCase(.uppercase)
                                .lineLimit(1).fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                        }
                    }
                    .foregroundColor(isSelected ? .ncPrimary : .ncPrimary.opacity(0.55))
                    .padding(.horizontal, isSelected ? 14 : 12)
                    .frame(height: 44)
                    .frame(maxWidth: isSelected ? nil : .infinity)
                    .background {
                        if isSelected {
                            Capsule().fill(Color.white.opacity(0.16))
                                .matchedGeometryEffect(id: "tabIndicator", in: indicator)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(TabButtonStyle())
            }
        }
        .padding(6)
        .modifier(GlassIsland())
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }
}

private struct GlassIsland: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        }
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
