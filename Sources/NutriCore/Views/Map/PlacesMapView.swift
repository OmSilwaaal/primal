import SwiftUI
import MapKit

/// Real food sources within 20 km: distance tags on a dark map, category chips, thick-glass place detail.
struct PlacesMapView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var searchResults: [MKMapItem] = []
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedQuery = "Butcher"
    @State private var isSearching = false

    @State private var selectedItem: MKMapItem?
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var hasAutoSearched = false

    let queries = ["Butcher", "Raw Meat", "Farm", "Organic Food"]

    var body: some View {
        ZStack {
            AppBackdrop()

            switch locationManager.authorizationStatus {
            case .notDetermined:
                permissionPrompt(label: "Find sources nearby",
                                 text: "Allow location to find butchers, farms and raw-food suppliers within 20 km.",
                                 button: "Enable location") { locationManager.requestPermission() }
            case .denied, .restricted:
                permissionPrompt(label: "Location off", text: "Turn on location in Settings to use the map.",
                                 button: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            default:
                mapContent
            }
        }
        .onAppear {
            if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                locationManager.startUpdating()
                if locationManager.location != nil { searchPlaces() }
            }
        }
        .onDisappear {
            locationManager.stopUpdating()
            searchTask?.cancel()
        }
        .onChange(of: locationManager.location) { _, location in
            // First fix after the tab opens triggers the initial search; later GPS jitter doesn't.
            if location != nil, !hasAutoSearched {
                hasAutoSearched = true
                searchPlaces()
            }
        }
    }

    private var mapContent: some View {
        ZStack {
            Map(position: $position) {
                UserAnnotation {
                    Circle().fill(Color.ncMoss).frame(width: 16, height: 16)
                        .padding(8)
                        .background(Circle().fill(Color.ncMoss.opacity(0.18)))
                }
                ForEach(searchResults, id: \.self) { item in
                    Annotation(item.name ?? "Place", coordinate: item.placemark.coordinate, anchor: .bottom) {
                        let on = selectedItem == item
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selectedItem = item }
                        } label: {
                            Text(distance(to: item) ?? "•")
                                .font(.mono(10, .semibold)).tracking(0.6)
                                .foregroundColor(on ? .ncOnPrimary : .ncPrimary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(minHeight: 32)
                                .background(on ? Color.ncPrimary : Color.ncBg)
                                .overlay(Rectangle().strokeBorder(Color.ncPrimary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { }
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                Spacer()
                if let searchError { StatusPill(text: searchError) }
                if let item = selectedItem {
                    PlaceDetailCard(item: item, distance: distance(to: item)) {
                        withAnimation(.easeOut(duration: 0.2)) { selectedItem = nil }
                    }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(queries, id: \.self) { query in
                            OptionChip(label: query, selected: selectedQuery == query, glassy: true) {
                                selectedQuery = query
                                selectedItem = nil
                                searchPlaces()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 100)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Real food sources").font(.mono(10)).tracking(1.6).textCase(.uppercase).foregroundColor(.ncSecondary)
                Text(isSearching ? "SEARCHING \(selectedQuery.uppercased())…"
                                 : "\(searchResults.count) × \(selectedQuery.uppercased()) WITHIN 20 KM")
                    .font(.ui(size: 15, weight: .bold)).foregroundColor(.ncPrimary)
                    .lineLimit(3).minimumScaleFactor(0.8)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .glass(.tinted, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func permissionPrompt(label: String, text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(label).monoLabel()
            Text(text).font(.ui(size: 15)).foregroundColor(.ncPrimary)
            Button(button, action: action).buttonStyle(.vitalis).padding(.top, 6)
        }
        .padding(.horizontal, Space.margin)
    }

    /// "0.8 km" under 10 km, whole kilometres beyond.
    private func distance(to item: MKMapItem) -> String? {
        guard let here = locationManager.location, let there = item.placemark.location else { return nil }
        let km = here.distance(from: there) / 1000
        return km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"
    }

    private func searchPlaces() {
        guard let location = locationManager.location else { return }
        searchTask?.cancel()
        isSearching = true
        searchError = nil
        let query = selectedQuery

        searchTask = Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 20000, longitudinalMeters: 20000)
            request.resultTypes = .pointOfInterest

            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                searchResults = response.mapItems
                if response.mapItems.isEmpty { searchError = "No \(query.lowercased()) found nearby" }
            } catch {
                guard !Task.isCancelled else { return }
                searchResults = []
                searchError = "Search failed. Check your connection."
            }
            isSearching = false
        }
    }
}

struct PlaceDetailCard: View {
    let item: MKMapItem
    var distance: String? = nil
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Unknown place").font(.ui(size: 18, weight: .bold)).foregroundColor(.ncPrimary)
                    if let distance {
                        Text("\(distance) away".uppercased()).font(.mono(12)).foregroundColor(.ncSecondary)
                    }
                }
                Spacer()
                Button(action: onClose) {
                    Text("CLOSE").font(.mono(11, .semibold)).foregroundColor(.ncPrimary)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Color.white.opacity(0.12))
                }
                .buttonStyle(.plain)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 6) {
                if let address = item.placemark.title {
                    GridRow {
                        Text("ADDRESS").font(.mono(11)).foregroundColor(.ncSecondary).frame(width: 72, alignment: .leading)
                        Text(address).font(.ui(size: 14)).foregroundColor(.ncPrimary)
                    }
                }
                if let phone = item.phoneNumber {
                    GridRow {
                        Text("PHONE").font(.mono(11)).foregroundColor(.ncSecondary).frame(width: 72, alignment: .leading)
                        Text(phone).font(.ui(size: 14)).foregroundColor(.ncPrimary)
                    }
                }
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Hairline(opacity: 0.14) }

            Button("Open in Maps") { item.openInMaps(launchOptions: nil) }
                .buttonStyle(PrimaryButtonStyle(height: 52))
        }
        .padding(20)
        .glass(.thick)
    }
}
