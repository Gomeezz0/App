import Foundation

// MARK: - Lugares y rutas

public struct Place: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var coordinate: Coordinate

    public init(id: String = UUID().uuidString, name: String, subtitle: String = "", coordinate: Coordinate) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.coordinate = coordinate
    }
}

public struct RouteStep: Hashable, Sendable {
    /// Texto de la maniobra tal como lo entrega el proveedor ("Gira a la derecha por…").
    public var instruction: String
    /// Metros desde el inicio de la ruta hasta el punto donde se ejecuta la maniobra.
    public var maneuverDistance: Double

    public init(instruction: String, maneuverDistance: Double) {
        self.instruction = instruction
        self.maneuverDistance = maneuverDistance
    }
}

public enum RouteKind: String, Sendable, CaseIterable {
    case fastest, shortest, alternative

    public var title: String {
        switch self {
        case .fastest: return "Más rápida"
        case .shortest: return "Más corta"
        case .alternative: return "Alternativa"
        }
    }
}

public struct Route: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var kind: RouteKind
    public var polyline: Polyline
    /// Metros.
    public var distance: Double
    /// Segundos, según el proveedor (con tráfico si el proveedor lo soporta).
    public var expectedTravelTime: TimeInterval
    public var steps: [RouteStep]
    public var hasTolls: Bool
    public var notices: [String]

    public init(
        id: UUID = UUID(), name: String, kind: RouteKind = .alternative, polyline: Polyline, distance: Double,
        expectedTravelTime: TimeInterval, steps: [RouteStep], hasTolls: Bool = false, notices: [String] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.polyline = polyline
        self.distance = distance
        self.expectedTravelTime = expectedTravelTime
        self.steps = steps
        self.hasTolls = hasTolls
        self.notices = notices
    }
}

public extension Array where Element == Route {
    /// Etiqueta la más rápida y la más corta; el resto quedan como alternativas. Ordena por tiempo.
    func classified() -> [Route] {
        guard !isEmpty else { return [] }
        var routes = sorted { $0.expectedTravelTime < $1.expectedTravelTime }
        for index in routes.indices { routes[index].kind = .alternative }
        routes[0].kind = .fastest
        if let shortest = routes.indices.dropFirst().min(by: { routes[$0].distance < routes[$1].distance }),
           routes[shortest].distance < routes[0].distance
        {
            routes[shortest].kind = .shortest
        }
        return routes
    }
}

// MARK: - Avisos comunitarios

public enum AlertType: String, Codable, CaseIterable, Sendable, Identifiable {
    case police
    case speedCamera = "speed_camera"
    case accident
    case trafficJam = "traffic_jam"
    case stoppedVehicle = "stopped_vehicle"
    case roadObject = "road_object"
    case roadworks
    case roadClosed = "road_closed"
    case weather
    case hazard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .police: return "Control"
        case .speedCamera: return "Radar fijo"
        case .accident: return "Accidente"
        case .trafficJam: return "Retención"
        case .stoppedVehicle: return "Vehículo detenido"
        case .roadObject: return "Objeto en la vía"
        case .roadworks: return "Obras"
        case .roadClosed: return "Vía cortada"
        case .weather: return "Mal tiempo"
        case .hazard: return "Peligro"
        }
    }

    /// Frase hablada. Los avisos de control no invitan a cambiar la conducción: recuerdan respetar los límites.
    public var spoken: String {
        switch self {
        case .police: return "Zona de control"
        case .speedCamera: return "Radar fijo"
        case .accident: return "Accidente"
        case .trafficJam: return "Retención"
        case .stoppedVehicle: return "Vehículo detenido"
        case .roadObject: return "Objeto en la calzada"
        case .roadworks: return "Obras"
        case .roadClosed: return "Vía cortada"
        case .weather: return "Condiciones meteorológicas adversas"
        case .hazard: return "Peligro"
        }
    }
}

public enum ConfidenceLevel: String, Codable, Sendable, Comparable {
    case low, medium, high

    private var order: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: ConfidenceLevel, rhs: ConfidenceLevel) -> Bool { lhs.order < rhs.order }

    public var title: String {
        switch self {
        case .low: return "Sin verificar"
        case .medium: return "Reportado"
        case .high: return "Confirmado"
        }
    }
}

public enum AlertVote: String, Codable, Sendable {
    case confirm, deny
}

/// Aviso tal como lo devuelve el backend (`GET /v1/alerts`).
public struct CommunityAlert: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var type: AlertType
    public var lat: Double
    public var lon: Double
    public var heading: Double?
    public var approximate: Bool
    public var zoneRadiusM: Double?
    public var source: String
    public var confidence: Double
    public var level: ConfidenceLevel
    public var confirmations: Int
    public var denials: Int
    public var createdAt: Date
    public var expiresAt: Date?
    public var mine: Bool
    public var myVote: AlertVote?

    public var coordinate: Coordinate { Coordinate(latitude: lat, longitude: lon) }
    public var isOfficial: Bool { source == "official" }

    /// Título para mostrar. Los avisos con ubicación aproximada se presentan como zona.
    public var displayTitle: String {
        guard approximate else { return type.title }
        return type == .police ? "Zona de control" : "Zona de \(type.title.lowercased())"
    }

    public init(
        id: String, type: AlertType, lat: Double, lon: Double, heading: Double? = nil, approximate: Bool = false,
        zoneRadiusM: Double? = nil, source: String = "community", confidence: Double = 0.5,
        level: ConfidenceLevel = .medium, confirmations: Int = 0, denials: Int = 0, createdAt: Date = Date(),
        expiresAt: Date? = nil, mine: Bool = false, myVote: AlertVote? = nil
    ) {
        self.id = id
        self.type = type
        self.lat = lat
        self.lon = lon
        self.heading = heading
        self.approximate = approximate
        self.zoneRadiusM = zoneRadiusM
        self.source = source
        self.confidence = confidence
        self.level = level
        self.confirmations = confirmations
        self.denials = denials
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.mine = mine
        self.myVote = myVote
    }
}

// MARK: - Preferencias de avisos

public enum AlertPreference: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Se muestra en el mapa y se anuncia por voz.
    case voice
    /// Solo en el mapa.
    case silent
    /// Ni se muestra ni se anuncia.
    case hidden

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .voice: return "Mapa y voz"
        case .silent: return "Solo mapa"
        case .hidden: return "Ocultar"
        }
    }
}

public enum VoiceVerbosity: String, Codable, CaseIterable, Sendable, Identifiable {
    case full, standard, minimal, off

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: return "Completa"
        case .standard: return "Normal"
        case .minimal: return "Solo giros"
        case .off: return "Silencio"
        }
    }
}
