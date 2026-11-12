import Foundation

/// Estado de avance sobre una ruta tras procesar una lectura de GPS.
public struct RouteProgress: Sendable, Equatable {
    public var distanceTravelled: Double
    public var distanceRemaining: Double
    public var timeRemaining: TimeInterval
    /// Índice en `route.steps` de la próxima maniobra, o `nil` si no quedan.
    public var stepIndex: Int?
    public var distanceToManeuver: Double
    /// Posición ajustada a la ruta y rumbo de la vía en ese punto.
    public var snapped: Coordinate
    public var snappedBearing: Double
    public var isOffRoute: Bool
    public var hasArrived: Bool
}

/// Sigue la posición del vehículo sobre una ruta: ajuste a la vía, maniobra siguiente,
/// detección de desvío con histéresis y llegada.
public struct RouteTracker: Sendable {
    public struct Config: Sendable {
        /// Separación de la ruta a partir de la cual una lectura cuenta como "fuera".
        public var offRouteDistance = 45.0
        /// Lecturas consecutivas "fuera" necesarias para declarar el desvío.
        public var offRouteReadings = 3
        /// Separación que declara el desvío de inmediato.
        public var hardOffRouteDistance = 120.0
        /// Las lecturas con peor precisión que esta no cuentan para el desvío.
        public var maxUsableAccuracy = 65.0
        /// Distancia al destino que se considera llegada.
        public var arrivalDistance = 30.0
        /// Metros hacia delante en los que se busca el ajuste antes de recurrir a toda la ruta.
        public var searchAhead = 600.0
        /// Antes de incorporarse a la ruta: metros que hay que alejarse de ella para declarar el desvío.
        public var approachSlack = 150.0

        public init() {}
    }

    public let route: Route
    public var config: Config
    private var lastAlong = 0.0
    private var offCount = 0
    private var offRoute = false
    /// El vehículo ya ha estado sobre la ruta. Hasta entonces (salida desde un aparcamiento o una
    /// plaza, lejos de la calzada) estar separado de ella no es un desvío: se está yendo hacia ella.
    private var joined = false
    private var closestApproach = Double.infinity

    public init(route: Route, config: Config = Config()) {
        self.route = route
        self.config = config
    }

    /// Procesa una lectura.
    /// - Parameters:
    ///   - horizontalAccuracy: radio de incertidumbre en metros; negativo = lectura no válida.
    public mutating func update(location: Coordinate, horizontalAccuracy: Double) -> RouteProgress {
        let line = route.polyline
        guard line.segmentCount > 0 else {
            return RouteProgress(
                distanceTravelled: 0, distanceRemaining: 0, timeRemaining: 0, stepIndex: nil, distanceToManeuver: 0,
                snapped: location, snappedBearing: 0, isOffRoute: false, hasArrived: true)
        }

        // Primero se busca cerca del último punto conocido: evita saltar a otro tramo
        // de la ruta que pase cerca (rotondas, enlaces, ida y vuelta por la misma vía).
        let from = max(0, line.segmentIndex(atDistance: lastAlong) - 1)
        let to = min(line.segmentCount, line.segmentIndex(atDistance: lastAlong + config.searchAhead) + 1)
        var projection = line.nearest(to: location, in: from..<to)
        if projection == nil || projection!.offset > config.offRouteDistance {
            if let global = line.nearest(to: location), projection == nil || global.offset < projection!.offset {
                projection = global
            }
        }
        let fix = projection!

        let usable = horizontalAccuracy >= 0 && horizontalAccuracy <= config.maxUsableAccuracy
        if usable {
            let tolerance = max(config.offRouteDistance, horizontalAccuracy * 1.5)
            if !joined {
                closestApproach = min(closestApproach, fix.offset)
                if fix.offset <= tolerance {
                    joined = true
                    offCount = 0
                    offRoute = false
                } else if fix.offset > closestApproach + config.approachSlack {
                    // Se aleja de la ruta sin haberla alcanzado: va hacia otro sitio.
                    offRoute = true
                }
            } else if fix.offset > config.hardOffRouteDistance {
                offRoute = true
            } else if fix.offset > tolerance {
                offCount += 1
                if offCount >= config.offRouteReadings { offRoute = true }
            } else {
                offCount = 0
                offRoute = false
            }
        }
        if !offRoute { lastAlong = fix.distanceAlong }

        let along = lastAlong
        let remaining = max(0, line.length - along)
        let fraction = line.length > 0 ? remaining / line.length : 0
        let next = route.steps.firstIndex { $0.maneuverDistance > along + 5 }
        let toManeuver = next.map { route.steps[$0].maneuverDistance - along } ?? remaining

        return RouteProgress(
            distanceTravelled: along,
            distanceRemaining: remaining,
            timeRemaining: route.expectedTravelTime * fraction,
            stepIndex: next,
            distanceToManeuver: max(0, toManeuver),
            // Fuera de la ruta, o antes de incorporarse a ella, se muestra la posición real.
            snapped: offRoute || !joined ? location : fix.point,
            snappedBearing: line.bearing(ofSegment: fix.segment),
            isOffRoute: offRoute,
            hasArrived: !offRoute && remaining <= config.arrivalDistance
        )
    }
}
