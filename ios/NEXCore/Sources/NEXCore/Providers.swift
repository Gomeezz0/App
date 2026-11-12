import Foundation

/// Lo que un proveedor de mapas ofrece de verdad. La interfaz consulta estos valores para
/// mostrar u ocultar funciones: nada se presenta como disponible si aquí es `false`.
public struct ProviderCapabilities: Sendable, Equatable {
    public var name: String
    /// El tiempo estimado tiene en cuenta el tráfico actual.
    public var trafficAwareETA: Bool
    /// Admite estimar el tiempo para una hora de salida futura.
    public var departureTimeETA: Bool
    public var offlineMaps: Bool
    public var speedLimits: Bool
    public var laneGuidance: Bool

    public init(
        name: String, trafficAwareETA: Bool, departureTimeETA: Bool, offlineMaps: Bool, speedLimits: Bool,
        laneGuidance: Bool
    ) {
        self.name = name
        self.trafficAwareETA = trafficAwareETA
        self.departureTimeETA = departureTimeETA
        self.offlineMaps = offlineMaps
        self.speedLimits = speedLimits
        self.laneGuidance = laneGuidance
    }
}

public protocol RoutingProvider {
    var capabilities: ProviderCapabilities { get }
    /// Rutas en coche entre dos puntos, con alternativas si el proveedor las ofrece.
    func routes(from origin: Coordinate, to destination: Coordinate, departure: Date?) async throws -> [Route]
    /// Tiempo estimado de viaje, en segundos, saliendo a la hora indicada.
    func travelTime(from origin: Coordinate, to destination: Coordinate, departure: Date) async throws -> TimeInterval
}

public protocol PlaceSearchProvider {
    func search(_ query: String, near center: Coordinate?) async throws -> [Place]
}

public protocol ParkingProvider {
    /// `true` si el proveedor informa de plazas libres en tiempo real (no solo de la ubicación).
    var providesAvailability: Bool { get }
    func parking(near coordinate: Coordinate) async throws -> [Place]
}

/// Incidencias de tráfico de una fuente oficial o comercial (TomTom, HERE…).
/// No hay ninguna implementación conectada todavía: requiere contratar un proveedor.
public protocol TrafficIncidentProvider {
    func incidents(near coordinate: Coordinate, radius: Double) async throws -> [CommunityAlert]
}

public enum ProviderError: LocalizedError {
    case noRoute
    case noResults

    public var errorDescription: String? {
        switch self {
        case .noRoute: return "No se ha encontrado ninguna ruta en coche hasta ese destino."
        case .noResults: return "Sin resultados."
        }
    }
}
