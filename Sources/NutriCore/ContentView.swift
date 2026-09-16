import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.ncSurface)
        appearance.shadowColor = .clear
        
        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor(Color.ncSecondary)
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(Color.ncSecondary),
            .font: UIFont.systemFont(ofSize: 10, weight: .bold)
        ]
        itemAppearance.selected.iconColor = UIColor(Color.ncPrimary)
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(Color.ncPrimary),
            .font: UIFont.systemFont(ofSize: 10, weight: .bold)
        ]
        
        appearance.stackedLayoutAppearance = itemAppearance
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("HOME", systemImage: "house")
                }
                .tag(0)

            CameraView()
                .tabItem {
                    Label("SCAN", systemImage: "barcode.viewfinder")
                }
                .tag(1)

            PlacesMapView()
                .tabItem {
                    Label("MAP", systemImage: "map")
                }
                .tag(2)

            MicronutrientsView()
                .tabItem {
                    Label("DATA", systemImage: "chart.bar")
                }
                .tag(3)

            ProfileView()
                .tabItem {
                    Label("PROFILE", systemImage: "person")
                }
                .tag(4)
        }
        .tint(.ncPrimary)
    }
}
