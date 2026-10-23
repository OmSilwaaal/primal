import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus
    
    /// Continuous: keeps updating while authorized (map, sun). One-shot: a single coarse fix, enough for
    /// weather, so the GPS isn't kept running while Home is on screen.
    private let continuous: Bool

    init(continuous: Bool = true) {
        self.continuous = continuous
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = continuous ? kCLLocationAccuracyBest : kCLLocationAccuracyKilometer
    }

    /// One coarse location fix (one-shot mode).
    func requestOnce() {
        manager.requestLocation()
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startUpdating() {
        manager.startUpdatingLocation()
    }
    
    func stopUpdating() {
        manager.stopUpdatingLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
            if continuous { self.startUpdating() } else { manager.requestLocation() }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.location = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager failed with error: \(error.localizedDescription)")
    }
}
