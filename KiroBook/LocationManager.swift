import Combine
import CoreLocation
import MapKit
import SwiftUI

final class LocationManager: NSObject, ObservableObject {

    static let shared = LocationManager()

    @Published var city: String = ""
    @Published var country: String = ""
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocating: Bool = false

    private let manager = CLLocationManager()
    private var locateTimeout: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocation() {
        print("📍 requestLocation called, status: \(manager.authorizationStatus.rawValue)")
        city = ""
        country = ""
        isLocating = true
        locateTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isLocating {
                print("📍 Location request timed out")
                self.isLocating = false
            }
        }
        locateTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            print("📍 Location denied")
            isLocating = false
            locateTimeout?.cancel()
        @unknown default:
            isLocating = false
            locateTimeout?.cancel()
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        locateTimeout?.cancel()
        guard let location = locations
            .filter({ $0.horizontalAccuracy >= 0 })
            .min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) ?? locations.last
        else { return }

        let adjustedCoordinate = CoordinateTransform.wgs84ToGcj02IfNeeded(location.coordinate)
        let adjustedLocation = CLLocation(
            coordinate: adjustedCoordinate,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: location.timestamp
        )
        print("📍 Got location: \(location.coordinate), adjusted: \(adjustedCoordinate), accuracy: \(location.horizontalAccuracy)m")

        CLGeocoder().reverseGeocodeLocation(adjustedLocation) { [weak self] placemarks, error in
            if let self, let placemark = placemarks?.first {
                DispatchQueue.main.async {
                    self.city = placemark.locality ?? ""
                    self.country = placemark.country ?? ""
                    self.coordinate = adjustedCoordinate
                    self.isLocating = false
                    print("📍 City: \(self.city), Country: \(self.country)")
                }
            } else {
                print("📍 CLGeocoder failed: \(error?.localizedDescription ?? "nil"), trying MKLocalSearch")
                self?.fallbackReverseGeocode(adjustedLocation)
            }
        }
    }

    private func fallbackReverseGeocode(_ location: CLLocation) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(location.coordinate.latitude), \(location.coordinate.longitude)"
        MKLocalSearch(request: request).start { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self, let item = response?.mapItems.first else {
                    print("📍 MKLocalSearch also failed: \(error?.localizedDescription ?? "nil")")
                    self?.isLocating = false
                    return
                }
                self.city = item.placemark.locality ?? ""
                self.country = item.placemark.country ?? ""
                self.coordinate = location.coordinate
                self.isLocating = false
                print("📍 MKLocalSearch City: \(self.city), Country: \(self.country)")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        print("📍 Location error: \(error.localizedDescription)")
        locateTimeout?.cancel()
        DispatchQueue.main.async { self.isLocating = false }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("📍 Auth changed: \(manager.authorizationStatus.rawValue)")
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

private enum CoordinateTransform {
    private static let pi = 3.1415926535897932384626
    private static let earthSemiMajorAxis = 6378245.0
    private static let eccentricitySquared = 0.00669342162296594323

    static func wgs84ToGcj02IfNeeded(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !isOutOfChina(latitude: coordinate.latitude, longitude: coordinate.longitude) else {
            return coordinate
        }

        var deltaLatitude = transformLatitude(
            x: coordinate.longitude - 105.0,
            y: coordinate.latitude - 35.0
        )
        var deltaLongitude = transformLongitude(
            x: coordinate.longitude - 105.0,
            y: coordinate.latitude - 35.0
        )
        let radLatitude = coordinate.latitude / 180.0 * pi
        var magic = sin(radLatitude)
        magic = 1 - eccentricitySquared * magic * magic
        let sqrtMagic = sqrt(magic)
        deltaLatitude = (deltaLatitude * 180.0) /
            ((earthSemiMajorAxis * (1 - eccentricitySquared)) / (magic * sqrtMagic) * pi)
        deltaLongitude = (deltaLongitude * 180.0) /
            (earthSemiMajorAxis / sqrtMagic * cos(radLatitude) * pi)

        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + deltaLatitude,
            longitude: coordinate.longitude + deltaLongitude
        )
    }

    private static func isOutOfChina(latitude: Double, longitude: Double) -> Bool {
        longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        result += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        result += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0)) * 2.0 / 3.0
        return result
    }
}
