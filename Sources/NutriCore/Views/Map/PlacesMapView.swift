import SwiftUI
import MapKit

struct PlacesMapView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var searchResults: [MKMapItem] = []
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedQuery = "Butcher"
    @State private var isSearching = false
    
    @State private var selectedItem: MKMapItem?
    
    let queries = ["Butcher", "Raw Meat", "Farm", "Organic Food"]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if locationManager.authorizationStatus == .notDetermined {
                VStack(spacing: 24) {
                    Image(systemName: "location.circle")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundColor(.white)
                    
                    Text("LOCATION REQUIRED")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white)
                    
                    Text("We need your location to find high-quality primal food sources near you.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button("ENABLE LOCATION") {
                        locationManager.requestPermission()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.black)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(8)
                    .padding(.top, 20)
                }
            } else if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                VStack(spacing: 24) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundColor(.gray)
                    
                    Text("ACCESS DENIED")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.white)
                    
                    Text("Please enable location in Settings to use the map.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
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
                        if isSearching {
                            ProgressView()
                                .tint(.white)
                                .padding()
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(8)
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
                                    Button(action: {
                                        selectedQuery = query
                                        selectedItem = nil
                                        searchPlaces()
                                    }) {
                                        Text(query.uppercased())
                                            .font(.system(size: 12, weight: .bold))
                                            .tracking(1)
                                            .foregroundColor(selectedQuery == query ? .black : .white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(selectedQuery == query ? Color.white : Color.black)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                            )
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.bottom, 20)
                        .padding(.top, 40)
                    }
                    .background(
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .bottom, endPoint: .top)
                    )
                    .animation(.spring(), value: selectedItem)
                }
                .preferredColorScheme(.dark)
            }
        }
        .onAppear {
            if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                searchPlaces()
            }
        }
        .onChange(of: locationManager.location) { _, _ in
            if searchResults.isEmpty && !isSearching {
                searchPlaces()
            }
        }
    }
    
    private func searchPlaces() {
        guard let location = locationManager.location else { return }
        
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = selectedQuery
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 20000, longitudinalMeters: 20000)
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            guard let response = response else { return }
            self.searchResults = response.mapItems
        }
    }
}

struct PlaceDetailCard: View {
    let item: MKMapItem
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.name?.uppercased() ?? "UNKNOWN")
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
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            if let phone = item.phoneNumber {
                HStack {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.gray)
                    Text(phone)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
            }
            
            Button("OPEN IN MAPS") {
                item.openInMaps(launchOptions: nil)
            }
            .font(.system(size: 12, weight: .bold))
            .tracking(1)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white)
            .cornerRadius(8)
            .padding(.top, 8)
        }
        .padding()
        .background(Color.black.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
