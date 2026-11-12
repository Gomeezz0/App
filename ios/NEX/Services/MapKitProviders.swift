import CoreLocation
import MapKit
import NEXCore

extension Coordinate {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(_ c: CLLocationCoordinate2D) { self.init(latitude: c.latitude, longitude: c.longitude) }
}

extension MKPolyline {
    var nexCoordinates: [Coordinate] {
        var buffer = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&buffer, range: NSRange(location: 0, length: pointCount))
        return buffer.map(Coordinate.init)
    }
}

/// Opciones de ruta que elige el usuario en Ajustes.
struct RoutePreferences {
    var avoidTolls = false
    var avoidHighways = false
}

/// Rutas con `MKDirections`. El tiempo estimado incluye el tráfico actual; no hay coste por uso.
/// Lo que MapKit no ofrece queda declarado en `capabilities` y la interfaz lo respeta.
struct MapKitRoutingProvider: RoutingProvider {
    var preferences: () -> RoutePreferences = { RoutePreferences() }

    let capabilities = ProviderCapabilities(
        name: "Apple MapKit", trafficAwareETA: true, departureTimeETA: true, offlineMaps: false, speedLimits: false,
        laneGuidance: false)

    private func makeRequest(from origin: Coordinate, to destination: Coordinate, departure: Date?) -> MKDirections.Request {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.cl))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.cl))
        request.transportType = .automobile
        if let departure { request.departureDate = departure }
        let options = preferences()
        request.tollPreference = options.avoidTolls ? .avoid : .any
        request.highwayPreference = options.avoidHighways ? .avoid : .any
        return request
    }

    func routes(from origin: Coordinate, to destination: Coordinate, departure: Date?) async throws -> [Route] {
        let request = makeRequest(from: origin, to: destination, departure: departure)
        request.requestsAlternateRoutes = true
        let response = try await MKDirections(request: request).calculate()
        let routes = response.routes.map(Self.convert)
        guard !routes.isEmpty else { throw ProviderError.noRoute }
        return routes.classified()
    }

    func travelTime(from origin: Coordinate, to destination: Coordinate, departure: Date) async throws -> TimeInterval {
        let request = makeRequest(from: origin, to: destination, departure: departure)
        return try await MKDirections(request: request).calculateETA().expectedTravelTime
    }

    static func convert(_ route: MKRoute) -> Route {
        // En MapKit cada paso describe la maniobra que se hace al terminar su tramo:
        // la distancia acumulada hasta el final del paso es el punto de maniobra.
        // (Pendiente de validar en carretera; si resultara ser al inicio, basta con
        // acumular después de asignar.)
        var travelled = 0.0
        var steps: [RouteStep] = []
        for step in route.steps {
            travelled += step.distance
            guard !step.instructions.isEmpty else { continue }
            steps.append(RouteStep(instruction: step.instructions, maneuverDistance: travelled))
        }
        return Route(
            name: route.name.isEmpty ? "Ruta" : route.name,
            polyline: Polyline(route.polyline.nexCoordinates),
            distance: route.distance,
            expectedTravelTime: route.expectedTravelTime,
            steps: steps,
            hasTolls: route.hasTolls,
            notices: route.advisoryNotices)
    }
}

private func place(from item: MKMapItem) -> Place {
    let placemark = item.placemark
    let parts = [placemark.thoroughfare, placemark.locality, placemark.administrativeArea].compactMap { $0 }
    var seen = Set<String>()
    let subtitle = parts.filter { seen.insert($0).inserted }.joined(separator: ", ")
    let coordinate = placemark.coordinate
    return Place(
        id: "\(item.name ?? "")|\(coordinate.latitude)|\(coordinate.longitude)",
        name: item.name ?? placemark.title ?? "Destino",
        subtitle: subtitle,
        coordinate: Coordinate(coordinate))
}

struct MapKitSearchProvider: PlaceSearchProvider {
    func search(_ query: String, near center: Coordinate?) async throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        if let center {
            request.region = MKCoordinateRegion(center: center.cl, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map(place(from:))
    }
}

/// Aparcamientos como puntos de interés de MapKit: ubicación y nombre, sin plazas libres.
struct MapKitParkingProvider: ParkingProvider {
    let providesAvailability = false

    func parking(near coordinate: Coordinate) async throws -> [Place] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate.cl, radius: 600)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.parking])
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map(place(from:))
            .sorted { Geo.distance($0.coordinate, coordinate) < Geo.distance($1.coordinate, coordinate) }
    }
}
