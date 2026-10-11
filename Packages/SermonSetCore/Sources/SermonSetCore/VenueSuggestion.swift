import Foundation
import CoreLocation
import MapKit
import Observation

public struct VenueCandidate: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var churchName: String
    public var city: String?
    public var region: String?
    public var country: String?
    // These are the searched public venue, never the listener's GPS fix.
    public var publicLatitude: Double
    public var publicLongitude: Double
    public init(id: UUID = UUID(),churchName: String,city: String? = nil,region: String? = nil,country: String? = nil,publicLatitude: Double,publicLongitude: Double) {
        self.id = id; self.churchName = churchName; self.city = city; self.region = region; self.country = country
        self.publicLatitude = publicLatitude; self.publicLongitude = publicLongitude
    }
    public func venue(precision: LocationPrecision) -> Venue {
        let named = precision == .venue
        return Venue(id: id,churchName: named ? churchName : nil,city: precision == .privateLocation ? nil : city,region: precision == .privateLocation ? nil : region,country: precision == .privateLocation ? nil : country,latitude: named ? (publicLatitude*100).rounded()/100 : nil,longitude: named ? (publicLongitude*100).rounded()/100 : nil,precision: precision)
    }
}
@MainActor @Observable public final class VenueSuggestionController: NSObject, CLLocationManagerDelegate {
    public private(set) var state: JobState = .idle
    public private(set) var candidates: [VenueCandidate] = []
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var search: MKLocalSearch?
    public override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer }
    /// UI calls only on an explicit foreground suggestion action.
    public func suggest() {
        if case .running = state { return }
        state = .running(progress: nil); candidates = []
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: state = .unavailable(reason: "Location is disabled. Type the church or city instead.")
        @unknown default: state = .unavailable(reason: "Type the church or city instead.")
        }
    }
    public func cancel() { search?.cancel(); search = nil; manager.stopUpdatingLocation(); state = .idle; candidates = [] }
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, case .running = self.state else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.state = .unavailable(reason: "Location is disabled. Type the church or city instead.")
            default: break
            }
        }
    }
    nonisolated public func locationManager(_ manager: CLLocationManager,didFailWithError error: any Error) {
        Task { @MainActor [weak self] in self?.state = .failed(message: "Nearby churches could not be found. Type the church or city instead.") }
    }
    nonisolated public func locationManager(_ manager: CLLocationManager,didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor [weak self] in
            guard let self, case .running = self.state else { return }
            self.manager.stopUpdatingLocation()
            let request = MKLocalSearch.Request(); request.naturalLanguageQuery = "church"
            request.region = MKCoordinateRegion(center: coordinate,latitudinalMeters: 5000,longitudinalMeters: 5000)
            let search = MKLocalSearch(request: request); self.search = search
            do {
                let result = try await search.start()
                guard self.search === search else { return }
                self.candidates = result.mapItems.prefix(15).map { item in
                    VenueCandidate(churchName: item.name ?? "Church",city: item.addressRepresentations?.cityName,region: nil,country: item.addressRepresentations?.regionName,publicLatitude: item.location.coordinate.latitude,publicLongitude: item.location.coordinate.longitude)
                }
                self.search = nil; self.state = .done
            } catch { if self.search === search { self.search = nil; self.state = .failed(message: "Nearby churches could not be found. Type the church or city instead.") } }
        }
    }
}
extension SermonStore {
    /// Drop listener-supplied precise coordinates at the persistence boundary.
    static func privacySafeVenue(_ venue: Venue?) -> Venue? {
        guard var venue else { return nil }
        switch venue.precision {
        case .venue:
            venue.latitude = venue.latitude.map { ($0*100).rounded()/100 }
            venue.longitude = venue.longitude.map { ($0*100).rounded()/100 }
        case .city, .unknown: venue.latitude = nil; venue.longitude = nil; venue.churchName = nil
        case .privateLocation: venue.latitude = nil; venue.longitude = nil; venue.churchName = nil; venue.city = nil; venue.region = nil; venue.country = nil
        }
        return venue
    }
}
