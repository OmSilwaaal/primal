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
                    case .home: DashboardView(onSearch: { open(search: true) }, onRaw: { secondary = .raw })
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
/// Floating tinted-glass capsule, 14 pt from the edges. Text-only tabs; the active one is a solid Paper pill.
/// Scan sits in the middle as a raised Paper disc.
struct VitalisTabBar: View {
    let selected: AppTab
    let onSelect: (AppTab) -> Void
    @Namespace private var indicator

    private let tabs: [(AppTab, String)] = [(.home, "HOME"), (.map, "MAP"), (.scan, "SCAN"), (.data, "DATA"), (.profile, "PROFILE")]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.0) { tab, label in
                if tab == .scan {
                    scanButton
                } else {
                    let on = selected == tab
                    Button { onSelect(tab) } label: {
                        Text(label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(on ? .ncOnPrimary : .ncPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background {
                                if on {
                                    Capsule().fill(Color.ncPrimary)
                                        .matchedGeometryEffect(id: "tab", in: indicator)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(TabButtonStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selected)
                }
            }
        }
        .padding(6)
        .frame(height: 62)
        .glass(.tinted, in: Capsule())
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var scanButton: some View {
        Button { onSelect(.scan) } label: {
            VStack(spacing: 5) {
                ScanGlyph().frame(width: 26, height: 22)
                Text("SCAN").font(.system(size: 10, weight: .heavy)).tracking(1.2)
            }
            .foregroundColor(.ncOnPrimary)
            .frame(width: 64, height: 64)
            .background(Circle().fill(Color.ncPrimary))
            .overlay(Circle().strokeBorder(Color.ncOnPrimary, lineWidth: 3))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
        }
        .buttonStyle(TabButtonStyle())
        .padding(.horizontal, 4)
        .offset(y: -8)
        .accessibilityLabel("Scan")
        .accessibilityAddTraits(selected == .scan ? .isSelected : [])
    }
}

/// Four viewfinder corners and a scan line.
struct ScanGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, l: CGFloat = 8, t: CGFloat = 3
            var p = Path()
            p.move(to: .init(x: t / 2, y: l)); p.addLine(to: .init(x: t / 2, y: t / 2)); p.addLine(to: .init(x: l, y: t / 2))
            p.move(to: .init(x: w - l, y: t / 2)); p.addLine(to: .init(x: w - t / 2, y: t / 2)); p.addLine(to: .init(x: w - t / 2, y: l))
            p.move(to: .init(x: t / 2, y: h - l)); p.addLine(to: .init(x: t / 2, y: h - t / 2)); p.addLine(to: .init(x: l, y: h - t / 2))
            p.move(to: .init(x: w - l, y: h - t / 2)); p.addLine(to: .init(x: w - t / 2, y: h - t / 2)); p.addLine(to: .init(x: w - t / 2, y: h - l))
            ctx.stroke(p, with: .foreground, style: StrokeStyle(lineWidth: t, lineCap: .butt, lineJoin: .miter))
            ctx.fill(Path(CGRect(x: 5, y: h / 2 - 1, width: w - 10, height: 2)), with: .foreground)
        }
    }
}

/// Tab items only dip slightly on press.
private struct TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
