import CoreLocation
import NEXCore
import Observation

/// Envoltorio de `CLLocationManager` con dos modos, pensado para gastar lo mínimo:
/// `browsing` (mapa abierto, precisión reducida, solo en primer plano) y
/// `navigating` (precisión máxima, también con la pantalla bloqueada).
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Mode { case stopped, browsing, navigating }

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var location: CLLocation?
    private(set) var mode: Mode = .stopped

    /// Se llama con cada lectura aceptada.
    @ObservationIgnored var onUpdate: ((CLLocation) -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
        manager.activityType = .automotiveNavigation
    }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        guard isAuthorized else { return }
        switch newMode {
        case .stopped:
            manager.allowsBackgroundLocationUpdates = false
            manager.stopUpdatingLocation()
        case .browsing:
            manager.allowsBackgroundLocationUpdates = false
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 10
            manager.pausesLocationUpdatesAutomatically = true
            manager.startUpdatingLocation()
        case .navigating:
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
            manager.pausesLocationUpdatesAutomatically = false
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.startUpdatingLocation()
        }
    }

    // MARK: Conducción simulada (solo depuración)

    #if DEBUG
    @ObservationIgnored private var replay: Task<Void, Never>?

    /// Reproduce un trayecto a lo largo de una polilínea, como si el vehículo la recorriera.
    /// Solo existe en compilaciones de depuración: sirve para pruebas de interfaz y demos,
    /// porque el simulador no entrega cambios de posición durante una prueba.
    func startReplay(along line: Polyline, speed: Double) {
        stopReplay()
        guard line.segmentCount > 0 else { return }
        replay = Task { [weak self] in
            let tick = 0.5
            var along = 0.0
            while !Task.isCancelled, along < line.length {
                along = min(line.length, along + speed * tick)
                let index = line.segmentIndex(atDistance: along)
                let a = line.points[index], b = line.points[index + 1]
                let span = line.cumulative[index + 1] - line.cumulative[index]
                let t = span > 0 ? (along - line.cumulative[index]) / span : 0
                let reading = CLLocation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: a.latitude + (b.latitude - a.latitude) * t,
                        longitude: a.longitude + (b.longitude - a.longitude) * t),
                    altitude: 650, horizontalAccuracy: 5, verticalAccuracy: 5,
                    course: Geo.bearing(from: a, to: b), speed: speed, timestamp: Date())
                self?.location = reading
                self?.onUpdate?(reading)
                try? await Task.sleep(for: .seconds(tick))
            }
        }
    }

    func stopReplay() {
        replay?.cancel()
        replay = nil
    }
    #endif

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            if isAuthorized, mode != .stopped { setMode(mode) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            #if DEBUG
            guard replay == nil else { return }
            #endif
            for reading in locations {
                // Se descartan lecturas inválidas o antiguas (p. ej. la última conocida al arrancar).
                guard reading.horizontalAccuracy >= 0, reading.timestamp.timeIntervalSinceNow > -10 else { continue }
                location = reading
                onUpdate?(reading)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Los fallos puntuales (túneles, sin cobertura) se resuelven solos con la siguiente lectura.
    }
}
