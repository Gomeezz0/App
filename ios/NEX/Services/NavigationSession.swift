import CoreLocation
import Foundation
import NEXCore
import Observation
import UIKit

/// Sesión de navegación activa: sigue la ruta, habla, recalcula al desviarse y registra el viaje.
/// Una vez calculada la ruta, la guía no necesita red; solo el recálculo la necesita.
@MainActor
@Observable
final class NavigationSession {
    enum Phase: Equatable { case idle, navigating, rerouting, arrived }

    private(set) var phase: Phase = .idle
    private(set) var route: Route?
    private(set) var destination: Place?
    private(set) var progress: RouteProgress?
    private(set) var alertsAhead: [AlertAhead] = []
    /// m/s, nunca negativa.
    private(set) var speed = 0.0
    /// Mensaje breve cuando el recálculo falla (normalmente por falta de red).
    private(set) var rerouteError: String?

    var isActive: Bool { phase != .idle }

    @ObservationIgnored private let routing: RoutingProvider
    @ObservationIgnored private let speech: SpeechService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let trips: TripStore

    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private var tracker: RouteTracker?
    @ObservationIgnored private var announcer = GuidanceAnnouncer()
    @ObservationIgnored private var monitor = AlertMonitor()
    @ObservationIgnored private var alertIndex: RouteAlertIndex?
    @ObservationIgnored private var knownAlerts: [CommunityAlert] = []
    @ObservationIgnored private var lastRerouteAttempt = Date.distantPast
    @ObservationIgnored private var rerouteInFlight = false

    // Registro del viaje.
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var travelled = 0.0
    @ObservationIgnored private var maxSpeed = 0.0
    @ObservationIgnored private var lastFix: CLLocation?

    init(routing: RoutingProvider, speech: SpeechService, settings: SettingsStore, trips: TripStore) {
        self.routing = routing
        self.speech = speech
        self.settings = settings
        self.trips = trips
    }

    func start(route: Route, to destination: Place) {
        self.destination = destination
        apply(route)
        phase = .navigating
        startedAt = Date()
        travelled = 0
        maxSpeed = 0
        lastFix = nil
        rerouteError = nil
        monitor = AlertMonitor()
        announcer = GuidanceAnnouncer(verbosity: settings.verbosity)
        UIApplication.shared.isIdleTimerDisabled = true
        liveActivity.start(
            destinationName: destination.name,
            state: .init(
                phase: .navigating, instruction: route.steps.first?.instruction ?? "", distanceToManeuver:
                    route.steps.first?.maneuverDistance ?? route.distance, distanceRemaining: route.distance,
                arrival: Date().addingTimeInterval(route.expectedTravelTime)))
        if settings.verbosity != .off {
            speech.speak("Ruta iniciada. \(NEXFormat.spokenDistance(route.distance)) hasta \(destination.name)")
        }
    }

    /// Termina la navegación y guarda el viaje si el usuario lo permite y se ha movido algo.
    func stop() {
        guard isActive else { return }
        if let destination, settings.saveTrips, travelled > 200 {
            trips.add(Trip(
                startedAt: startedAt, endedAt: Date(), destination: destination, distance: travelled,
                maxSpeed: maxSpeed, completed: phase == .arrived))
        }
        speech.stop()
        liveActivity.end()
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .idle
        route = nil
        destination = nil
        progress = nil
        tracker = nil
        alertIndex = nil
        alertsAhead = []
        rerouteError = nil
    }

    func setAlerts(_ alerts: [CommunityAlert]) {
        knownAlerts = alerts
        rebuildAlertIndex()
    }

    func handle(_ location: CLLocation) {
        guard isActive, phase != .arrived, var tracker, let route else { return }
        speed = max(0, location.speed)
        record(location)

        let update = tracker.update(location: Coordinate(location.coordinate), horizontalAccuracy: location.horizontalAccuracy)
        self.tracker = tracker
        progress = update

        announcer.verbosity = settings.verbosity
        var spoken = announcer.announcements(for: update, route: route, speed: speed)

        if update.isOffRoute {
            alertsAhead = []
            reroute(from: location)
        } else {
            if phase == .rerouting { phase = .navigating }
            alertsAhead = alertIndex?.ahead(
                from: update.distanceTravelled, range: 5_000, preferences: settings.alertPreferences) ?? []
            if settings.verbosity != .off {
                spoken += monitor.announcements(for: alertsAhead, speed: speed, preferences: settings.alertPreferences)
            }
        }

        for announcement in spoken {
            speech.speak(announcement.text, urgent: announcement.kind == .maneuver)
        }
        if update.hasArrived { phase = .arrived }

        liveActivity.update(.init(
            phase: phase == .arrived ? .arrived : (phase == .rerouting ? .rerouting : .navigating),
            instruction: update.stepIndex.map { route.steps[$0].instruction } ?? "Sigue la ruta",
            distanceToManeuver: update.distanceToManeuver,
            distanceRemaining: update.distanceRemaining,
            arrival: Date().addingTimeInterval(update.timeRemaining)))
    }

    // MARK: - Privado

    private func apply(_ route: Route) {
        self.route = route
        tracker = RouteTracker(route: route)
        progress = nil
        rebuildAlertIndex()
    }

    private func rebuildAlertIndex() {
        guard let route else { return }
        alertIndex = RouteAlertIndex(alerts: knownAlerts, route: route.polyline)
    }

    private func record(_ location: CLLocation) {
        guard location.horizontalAccuracy <= 50 else { return }
        if let lastFix {
            let step = location.distance(from: lastFix)
            // Por debajo de unos metros es ruido del GPS con el coche parado.
            guard step >= 5 else { return }
            travelled += step
        }
        lastFix = location
        maxSpeed = max(maxSpeed, speed)
    }

    private func reroute(from location: CLLocation) {
        // Un solo recálculo a la vez y, si falla, no más de un intento cada 8 s.
        guard let destination, !rerouteInFlight, Date().timeIntervalSince(lastRerouteAttempt) > 8 else { return }
        lastRerouteAttempt = Date()
        rerouteInFlight = true
        phase = .rerouting

        Task {
            defer { rerouteInFlight = false }
            do {
                let routes = try await routing.routes(
                    from: Coordinate(location.coordinate), to: destination.coordinate, departure: nil)
                guard isActive, let best = routes.first else { return }
                apply(best)
                announcer = GuidanceAnnouncer(verbosity: settings.verbosity)
                rerouteError = nil
                phase = .navigating
            } catch {
                // Se reintenta con las siguientes lecturas; mientras tanto se informa al conductor.
                rerouteError = "Sin conexión para recalcular. Reintentando…"
            }
        }
    }
}
