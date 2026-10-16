import SwiftUI
import MapKit

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
            
            if locationManager.authorizationStatus == .notDetermined {
                VStack(spacing: 24) {
                    Image(systemName: "location.circle")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundColor(.white)
                    
                    Text("Find sources nearby")
                        .font(.serif(26))
                        .foregroundColor(.white)
                    
                    Text("We need your location to find high-quality primal food sources near you.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button("Enable location") {
                        locationManager.requestPermission()
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 48, radius: 3))
                    .frame(maxWidth: 220)
                    .padding(.top, 12)
                }
            } else if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                VStack(spacing: 24) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundColor(.gray)
                    
                    Text("Location off")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Please enable location in Settings to use the map.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 48, radius: 3))
                    .frame(maxWidth: 220)
                }
            } else {
                // Map View
                ZStack(alignment: .bottom) {
                    Map(position: $position, selection: $selectedItem) {
                        UserAnnotation()
                        ForEach(searchResults, id: \.self) { item in
                            Marker(item.name ?? "Place", systemImage: "mappin", coordinate: item.placemark.coordinate)
                                .tint(.white) // stark monochrome marker
                                .tag(item as MKMapItem?)
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .ignoresSafeArea(edges: .top)
                    
                    // Controls Overlay
                    VStack(spacing: 16) {
                        if let searchError {
                            Text(searchError)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(8)
                        }

                        if isSearching {
                            ProgressView()
                                .tint(.white)
                                .padding(12)
                                .background(Color.ncSurfaceContHigh, in: Rectangle())
                        }
                        
                        if let item = selectedItem {
                            PlaceDetailCard(item: item) {
                                selectedItem = nil
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(queries, id: \.self) { query in
                                    let isSelected = selectedQuery == query
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            selectedQuery = query
                                            selectedItem = nil
                                        }
                                        searchPlaces()
                                    } label: {
                                        Text(query)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(isSelected ? .ncOnPrimary : .ncPrimary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 9)
                                            .background(isSelected ? Color.ncPrimary : Color.ncSurfaceContHigh, in: Rectangle())
                                            .overlay(Rectangle().stroke(Color.white.opacity(isSelected ? 0 : 0.1), lineWidth: 1))
                                    }
                                    .smoothButton()
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 100)
                        .padding(.top, 40)
                    }
                    .background(
                        LinearGradient(colors: [Color.ncBg, Color.ncBg.opacity(0)], startPoint: .bottom, endPoint: .top)
                    )
                    .animation(.spring(), value: selectedItem)
                }
                .preferredColorScheme(.dark)
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
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.name ?? "Unknown place")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                }
            }
            
            if let address = item.placemark.title {
                HStack(alignment: .top) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.gray)
                    Text(address)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
            }
            
            if let phone = item.phoneNumber {
                HStack {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.gray)
                    Text(phone)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                }
            }
            
            Button("Open in Maps") {
                item.openInMaps(launchOptions: nil)
            }
            .buttonStyle(PrimaryButtonStyle(height: 46, radius: 3))
            .padding(.top, 8)
        }
        .padding()
        .background(Color.ncSurfaceContLowest)
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .padding(.horizontal)
    }
}
