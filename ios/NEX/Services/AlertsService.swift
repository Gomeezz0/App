import CoreLocation
import Foundation
import NEXCore
import Observation

/// Avisos comunitarios cercanos. Consulta el backend solo cuando hace falta: al pasar el intervalo
/// o al alejarse de la zona ya descargada. Si falla la red, conserva los últimos avisos válidos.
@MainActor
@Observable
final class AlertsService {
    private(set) var alerts: [CommunityAlert] = []
    /// `true` si la última consulta falló (la interfaz lo indica; no se inventan datos).
    private(set) var isStale = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var lastCenter: Coordinate?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var country: (code: String?, at: Coordinate)?
    @ObservationIgnored private let geocoder = CLGeocoder()

    static let radius = 15_000.0

    init(api: APIClient) {
        self.api = api
    }

    /// Descarga avisos si toca. `interval` lo decide quien llama según el modo y el estado de la batería.
    func refreshIfNeeded(around center: Coordinate, interval: TimeInterval, force: Bool = false) {
        guard !inFlight else { return }
        let moved = lastCenter.map { Geo.distance($0, center) > Self.radius / 3 } ?? true
        let due = lastFetch.map { Date().timeIntervalSince($0) >= interval } ?? true
        guard force || moved || due else { return }

        inFlight = true
        Task {
            defer { inFlight = false }
            do {
                let fresh = try await api.alerts(near: center, radius: Self.radius)
                alerts = fresh
                isStale = false
                lastCenter = center
            } catch {
                isStale = true
                // Los avisos guardados siguen sirviendo hasta que caducan.
                let now = Date()
                alerts.removeAll { ($0.expiresAt ?? .distantFuture) < now }
            }
            lastFetch = Date()
        }
    }

    func report(_ type: AlertType, at location: CLLocation) async throws -> ReportResult {
        let coordinate = Coordinate(location.coordinate)
        let heading = location.course >= 0 && location.speed > 2 ? location.course : nil
        let result = try await api.report(
            type, at: coordinate, heading: heading, country: await countryCode(for: location))
        upsert(result.alert)
        return result
    }

    func vote(_ vote: AlertVote, on alert: CommunityAlert, from location: Coordinate) async throws {
        let result = try await api.vote(vote, on: alert.id, from: location)
        if let updated = result.alert, !result.removed {
            upsert(updated)
        } else {
            alerts.removeAll { $0.id == alert.id }
        }
    }

    private func upsert(_ alert: CommunityAlert) {
        if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
            alerts[index] = alert
        } else {
            alerts.append(alert)
        }
    }

    /// Código ISO del país, necesario para aplicar la política legal de cada aviso.
    /// Se reutiliza mientras el usuario no se aleje 20 km del punto donde se resolvió.
    private func countryCode(for location: CLLocation) async -> String? {
        let here = Coordinate(location.coordinate)
        if let country, Geo.distance(country.at, here) < 20_000 { return country.code }
        let code = try? await geocoder.reverseGeocodeLocation(location).first?.isoCountryCode
        if let code { country = (code, here) }
        return code
    }
}
