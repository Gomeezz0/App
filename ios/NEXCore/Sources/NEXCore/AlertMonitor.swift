import Foundation

/// Aviso situado por delante del vehículo.
public struct AlertAhead: Sendable, Equatable, Identifiable {
    public var alert: CommunityAlert
    /// Metros hasta el aviso (por la ruta si se navega; en línea recta si no).
    public var distance: Double
    public var id: String { alert.id }
}

/// Avisos situados sobre una ruta, precalculados. Proyectar cada aviso sobre la polilínea es
/// caro, así que se hace una vez cuando cambian la ruta o los avisos, no en cada lectura de GPS.
public struct RouteAlertIndex: Sendable {
    public struct Entry: Sendable {
        public var alert: CommunityAlert
        /// Metros desde el inicio de la ruta hasta donde empieza a afectar el aviso.
        public var along: Double
        /// Metros desde el inicio hasta donde deja de afectar (igual a `along` salvo en zonas).
        public var exit: Double
    }

    public let entries: [Entry]

    /// - Parameter corridor: separación máxima de la ruta para considerar que un aviso está en ella.
    public init(alerts: [CommunityAlert], route: Polyline, corridor: Double = 70) {
        var found: [Entry] = []
        for alert in alerts {
            if alert.approximate, let radius = alert.zoneRadiusM {
                // Zona: primer tramo de la ruta que entra en el círculo.
                for index in 0..<route.segmentCount {
                    let hit = Geo.project(alert.coordinate, ontoSegmentFrom: route.points[index], to: route.points[index + 1])
                    guard hit.distance <= radius else { continue }
                    let along = route.cumulative[index] + (route.cumulative[index + 1] - route.cumulative[index]) * hit.t
                    let half = (radius * radius - hit.distance * hit.distance).squareRoot()
                    found.append(Entry(alert: alert, along: max(0, along - half), exit: min(route.length, along + half)))
                    break
                }
            } else if let hit = route.nearest(to: alert.coordinate), hit.offset <= corridor {
                found.append(Entry(alert: alert, along: hit.distanceAlong, exit: hit.distanceAlong))
            }
        }
        entries = found.sorted { $0.along < $1.along }
    }

    /// Avisos por delante de la posición indicada, del más cercano al más lejano.
    public func ahead(from distanceAlong: Double, range: Double, preferences: [AlertType: AlertPreference])
        -> [AlertAhead]
    {
        entries.compactMap { entry in
            guard (preferences[entry.alert.type] ?? .voice) != .hidden,
                  entry.exit > distanceAlong, entry.along - distanceAlong <= range
            else { return nil }
            return AlertAhead(alert: entry.alert, distance: max(0, entry.along - distanceAlong))
        }
    }
}

/// Selecciona los avisos relevantes sin ruta activa y decide cuáles anunciar por voz.
public struct AlertMonitor: Sendable {
    /// Sin ruta: semiángulo del cono frontal en el que se buscan avisos.
    public var coneHalfAngle = 40.0
    private var announced: Set<String> = []

    public init() {}

    /// Antelación en metros: unos 20 s de conducción, entre 300 m y 1,5 km.
    public static func warningDistance(speed: Double) -> Double { min(1500, max(300, speed * 20)) }

    /// Avisos por delante en conducción libre (sin ruta), del más cercano al más lejano.
    /// Sin rumbo conocido (vehículo parado) se devuelven todos los que estén en el radio.
    public func alertsAhead(
        _ alerts: [CommunityAlert], location: Coordinate, course: Double?,
        preferences: [AlertType: AlertPreference], range: Double
    ) -> [AlertAhead] {
        var result: [AlertAhead] = []
        for alert in alerts where (preferences[alert.type] ?? .voice) != .hidden {
            let distance = Geo.distance(location, alert.coordinate)
            guard distance <= range else { continue }
            let inside = distance <= max(70, alert.zoneRadiusM ?? 0)
            if !inside, let course {
                let bearing = Geo.bearing(from: location, to: alert.coordinate)
                guard Geo.angleDifference(course, bearing) <= coneHalfAngle else { continue }
                // Si el aviso lleva sentido, se descartan los del sentido contrario.
                if let heading = alert.heading, Geo.angleDifference(course, heading) > 100 { continue }
            }
            result.append(AlertAhead(alert: alert, distance: inside && alert.approximate ? 0 : distance))
        }
        return result.sorted { $0.distance < $1.distance }
    }

    /// Anuncios de voz pendientes. Cada aviso se anuncia una sola vez y solo si tiene confianza suficiente.
    public mutating func announcements(
        for ahead: [AlertAhead], speed: Double, preferences: [AlertType: AlertPreference]
    ) -> [Announcement] {
        let limit = Self.warningDistance(speed: speed)
        var output: [Announcement] = []
        for item in ahead where item.distance <= limit {
            let alert = item.alert
            guard (preferences[alert.type] ?? .voice) == .voice, alert.level >= .medium,
                  announced.insert(alert.id).inserted
            else { continue }
            output.append(Announcement(Self.phrase(for: item), kind: .alert))
        }
        return output
    }

    static func phrase(for item: AlertAhead) -> String {
        let alert = item.alert
        if alert.type == .police {
            // Sin distancia ni posición: el mensaje es de prudencia, no de evasión.
            return "Zona de control. Respeta los límites de velocidad"
        }
        let where_ = item.distance < 80 ? "aquí" : "a \(NEXFormat.spokenDistance(item.distance))"
        let suffix = alert.level == .high || alert.isOfficial ? "" : ", sin confirmar"
        return "\(alert.type.spoken) \(where_)\(suffix)"
    }
}
