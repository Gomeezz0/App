import CoreLocation
import Foundation
import NEXCore
import Observation

/// Raíz de dependencias de la app. Aquí se decide qué proveedor implementa cada capacidad:
/// para cambiar de MapKit a otro, basta con sustituir las tres líneas de proveedores.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let trips: TripStore
    let favorites = FavoritesStore()
    let location: LocationService
    let alerts: AlertsService
    let navigation: NavigationSession
    let speech: SpeechService
    let api: APIClient

    let routing: RoutingProvider
    let search: PlaceSearchProvider
    let parking: ParkingProvider

    /// Perfil del usuario con sesión iniciada, o `nil`.
    private(set) var user: UserProfile?
    /// Destino elegido desde cualquier pantalla; el mapa abre su vista previa de rutas.
    var pendingDestination: Place?

    @ObservationIgnored private var freeDriveMonitor = AlertMonitor()
    /// Últimos avisos entregados a la sesión de navegación.
    @ObservationIgnored private var syncedAlerts: [CommunityAlert] = []

    init() {
        let settings = SettingsStore()
        let trips = TripStore()
        let speech = SpeechService()
        let api = APIClient(baseURL: Self.apiBaseURL, tokenStore: KeychainTokenStore())

        self.settings = settings
        self.trips = trips
        self.speech = speech
        self.api = api
        location = LocationService()
        alerts = AlertsService(api: api)

        routing = MapKitRoutingProvider(preferences: {
            RoutePreferences(avoidTolls: settings.avoidTolls, avoidHighways: settings.avoidHighways)
        })
        search = MapKitSearchProvider()
        parking = MapKitParkingProvider()
        navigation = NavigationSession(routing: routing, speech: speech, settings: settings, trips: trips)

        location.onUpdate = { [weak self] reading in self?.handle(reading) }
    }

    private static var apiBaseURL: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "NEXAPIBaseURL") as? String
        return configured.flatMap(URL.init(string:)) ?? URL(string: "http://localhost:8080")!
    }

    var isSignedIn: Bool { user != nil }

    /// Mapa en modo noche: manual, o automático según la posición del sol donde está el usuario.
    var mapIsNight: Bool {
        switch settings.mapAppearance {
        case .day: return false
        case .night: return true
        case .automatic:
            guard let here else { return true }
            return Solar.isNight(at: Date(), coordinate: here)
        }
    }
    var here: Coordinate? { location.location.map { Coordinate($0.coordinate) } }

    // MARK: - Ciclo de vida

    /// Al abrir la app: recupera la sesión guardada, si la hay.
    func restoreSession() async {
        guard await api.isSignedIn else { return }
        do {
            user = try await api.me()
        } catch APIError.unauthorized {
            user = nil
        } catch {
            // Sin red: se mantiene la sesión y se reintentará al usarla.
        }
    }

    /// El mapa pasa a primer plano o a segundo. Fuera de una navegación no se usa el GPS en segundo plano.
    func setForeground(_ foreground: Bool) {
        if navigation.isActive {
            location.setMode(.navigating)
        } else {
            location.setMode(foreground && settings.hasOnboarded ? .browsing : .stopped)
        }
    }

    // MARK: - Sesión de usuario

    func signIn(email: String, password: String) async throws {
        user = try await api.login(email: email, password: password)
        refreshAlerts(force: true)
    }

    func register(email: String, password: String, displayName: String) async throws {
        user = try await api.register(email: email, password: password, displayName: displayName)
        refreshAlerts(force: true)
    }

    func signOut() async {
        await api.logout()
        user = nil
    }

    func deleteAccount(password: String) async throws {
        try await api.deleteAccount(password: password)
        user = nil
    }

    func reloadProfile() async {
        if let fresh = try? await api.me() { user = fresh }
    }

    // MARK: - Navegación

    func startNavigation(route: Route, to destination: Place) {
        navigation.setAlerts(alerts.alerts)
        navigation.start(route: route, to: destination)
        location.setMode(.navigating)
        // Con el coche parado no llega una lectura nueva: se arranca con la última conocida.
        if let last = location.location { navigation.handle(last) }
    }

    func stopNavigation() {
        navigation.stop()
        location.setMode(.browsing)
    }

    // MARK: - Avisos

    /// Hay que gastar menos: lo pide el usuario, el iPhone está en bajo consumo o se está calentando.
    var isConstrained: Bool {
        settings.batterySaver || ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    /// Segundos entre consultas de avisos.
    var alertInterval: TimeInterval {
        let base: TimeInterval = navigation.isActive ? 30 : 60
        return isConstrained ? base * 2 : base
    }

    func refreshAlerts(force: Bool = false) {
        guard let here else { return }
        alerts.refreshIfNeeded(around: here, interval: alertInterval, force: force)
    }

    func report(_ type: AlertType) async throws -> ReportResult {
        guard let reading = location.location else {
            throw APIError.server(status: 0, code: "no_location", message: "Aún no hay señal GPS.")
        }
        let result = try await alerts.report(type, at: reading)
        navigation.setAlerts(alerts.alerts)
        return result
    }

    func vote(_ vote: AlertVote, on alert: CommunityAlert) async throws {
        guard let here else { return }
        try await alerts.vote(vote, on: alert, from: here)
        navigation.setAlerts(alerts.alerts)
    }

    // MARK: - Privado

    private func handle(_ reading: CLLocation) {
        refreshAlerts()

        if navigation.isActive {
            // La descarga es asíncrona: se compara con lo último entregado, no con el valor de este instante.
            if alerts.alerts != syncedAlerts {
                syncedAlerts = alerts.alerts
                navigation.setAlerts(syncedAlerts)
            }
            navigation.handle(reading)
        } else if reading.speed > 3, settings.verbosity != .off {
            // Conducción libre: avisos por delante según el rumbo.
            let ahead = freeDriveMonitor.alertsAhead(
                alerts.alerts, location: Coordinate(reading.coordinate), course: reading.course >= 0 ? reading.course : nil,
                preferences: settings.alertPreferences, range: 2_000)
            for announcement in freeDriveMonitor.announcements(
                for: ahead, speed: reading.speed, preferences: settings.alertPreferences)
            {
                speech.speak(announcement.text)
            }
        }
    }
}
