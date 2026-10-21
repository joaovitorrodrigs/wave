import Foundation
import CoreLocation
import Observation

/// Current weather from Open-Meteo for where the Mac is; a city typed in Settings when location is off.
@Observable final class Weather: NSObject, CLLocationManagerDelegate {
    var forecast: Forecast?
    var place = ""
    var error: String?
    private var coordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation?, Never>?

    func refresh() async {
        if coordinate == nil { await locate() }
        guard let coordinate else { error = "Allow location, or type a city in Settings."; return }
        do {
            forecast = try await Forecast.fetch(latitude: coordinate.latitude, longitude: coordinate.longitude)
            error = nil
            WidgetBridge.writeLocation(LocationSnapshot(latitude: coordinate.latitude, longitude: coordinate.longitude, place: place))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func locate() async {
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        let location = await withCheckedContinuation { (k: CheckedContinuation<CLLocation?, Never>) in
            waiting = k
            manager.requestLocation()
            Task { try? await Task.sleep(for: .seconds(8)); waiting?.resume(returning: nil); waiting = nil }
        }
        if let location {
            coordinate = location.coordinate
            let marks = try? await CLGeocoder().reverseGeocodeLocation(location)
            place = marks?.first?.locality ?? marks?.first?.name ?? ""
            return
        }
        let city = UserDefaults.standard.string(forKey: "weatherCity") ?? ""
        guard !city.isEmpty, let mark = try? await CLGeocoder().geocodeAddressString(city).first, let loc = mark.location else { return }
        coordinate = loc.coordinate
        place = mark.locality ?? city
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        waiting?.resume(returning: locations.last)
        waiting = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        waiting?.resume(returning: nil)
        waiting = nil
    }
}
