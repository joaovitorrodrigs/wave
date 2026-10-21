import Foundation
import MapKit
import Observation

/// Driving time between home and work with live traffic, from Apple Maps. Home → work before noon, back after.
@Observable final class Commute {
    var minutes: Int?
    var kilometers: Double?
    var via: String?
    var fetched: Date?
    var error: String?
    var toWork = Calendar.current.component(.hour, from: .now) < 12
    private var cache: [String: CLLocationCoordinate2D] = [:]

    var hasAddresses: Bool { !home.isEmpty && !work.isEmpty }
    private var home: String { UserDefaults.standard.string(forKey: "homeAddress") ?? "" }
    private var work: String { UserDefaults.standard.string(forKey: "workAddress") ?? "" }

    func flip() {
        toWork.toggle()
        Task { await refresh() }
    }

    func refresh() async {
        guard hasAddresses else { return }
        do {
            let from = try await coordinate(toWork ? home : work)
            let to = try await coordinate(toWork ? work : home)
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
            request.transportType = .automobile
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { throw CommuteError.noRoute }
            minutes = Int((route.expectedTravelTime / 60).rounded())
            kilometers = route.distance / 1000
            via = route.name.isEmpty ? nil : route.name
            fetched = .now
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func coordinate(_ address: String) async throws -> CLLocationCoordinate2D {
        if let cached = cache[address] { return cached }
        guard let location = try await CLGeocoder().geocodeAddressString(address).first?.location else { throw CommuteError.noAddress(address) }
        cache[address] = location.coordinate
        return location.coordinate
    }

    enum CommuteError: LocalizedError {
        case noRoute, noAddress(String)
        var errorDescription: String? {
            switch self {
            case .noRoute: "Apple Maps found no driving route."
            case .noAddress(let a): "Could not find “\(a)”."
            }
        }
    }
}
