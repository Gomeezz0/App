import Foundation

/// Coordenada geográfica en grados. Independiente de CoreLocation para poder testear sin simulador.
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum Geo {
    public static let earthRadius = 6_371_000.0

    static func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
    static func deg(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Distancia en metros (haversine).
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = rad(b.latitude - a.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(rad(a.latitude)) * cos(rad(b.latitude)) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Rumbo inicial de `a` hacia `b` en grados [0, 360), 0 = norte.
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = rad(a.latitude), lat2 = rad(b.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let value = deg(atan2(y, x))
        return value < 0 ? value + 360 : value
    }

    /// Diferencia mínima entre dos rumbos, en [0, 180].
    public static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    /// Proyección de `p` sobre el segmento `a`–`b` en un plano local (válido para segmentos cortos).
    /// - Returns: punto proyectado, fracción `t` en [0, 1] y distancia de `p` al segmento en metros.
    public static func project(_ p: Coordinate, ontoSegmentFrom a: Coordinate, to b: Coordinate)
        -> (point: Coordinate, t: Double, distance: Double)
    {
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(rad(a.latitude))
        let bx = (b.longitude - a.longitude) * metersPerDegLon
        let by = (b.latitude - a.latitude) * metersPerDegLat
        let px = (p.longitude - a.longitude) * metersPerDegLon
        let py = (p.latitude - a.latitude) * metersPerDegLat
        let lengthSquared = bx * bx + by * by
        let t = lengthSquared == 0 ? 0 : max(0, min(1, (px * bx + py * by) / lengthSquared))
        let point = Coordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
        let dx = px - bx * t, dy = py - by * t
        return (point, t, (dx * dx + dy * dy).squareRoot())
    }
}

/// Polilínea con distancias acumuladas, para situar un punto "a lo largo" de una ruta.
public struct Polyline: Sendable, Equatable {
    public let points: [Coordinate]
    /// `cumulative[i]` = metros desde el inicio hasta el vértice `i`.
    public let cumulative: [Double]

    public init(_ points: [Coordinate]) {
        self.points = points
        var sums: [Double] = []
        sums.reserveCapacity(points.count)
        var total = 0.0
        for (index, point) in points.enumerated() {
            if index > 0 { total += Geo.distance(points[index - 1], point) }
            sums.append(total)
        }
        cumulative = sums
    }

    public var length: Double { cumulative.last ?? 0 }
    public var segmentCount: Int { max(0, points.count - 1) }

    public struct Projection: Sendable, Equatable {
        public let segment: Int
        public let point: Coordinate
        /// Distancia perpendicular del punto original a la polilínea.
        public let offset: Double
        /// Metros desde el inicio de la polilínea hasta el punto proyectado.
        public let distanceAlong: Double
    }

    /// Punto de la polilínea más cercano a `p`, opcionalmente restringido a un rango de segmentos.
    public func nearest(to p: Coordinate, in range: Range<Int>? = nil) -> Projection? {
        guard segmentCount > 0 else { return nil }
        let bounds = (range ?? 0..<segmentCount).clamped(to: 0..<segmentCount)
        var best: Projection?
        for index in bounds {
            let a = points[index], b = points[index + 1]
            let result = Geo.project(p, ontoSegmentFrom: a, to: b)
            if best == nil || result.distance < best!.offset {
                let along = cumulative[index] + (cumulative[index + 1] - cumulative[index]) * result.t
                best = Projection(segment: index, point: result.point, offset: result.distance, distanceAlong: along)
            }
        }
        return best
    }

    /// Rumbo del segmento indicado.
    public func bearing(ofSegment index: Int) -> Double {
        guard segmentCount > 0 else { return 0 }
        let i = max(0, min(segmentCount - 1, index))
        return Geo.bearing(from: points[i], to: points[i + 1])
    }

    /// Índice del último segmento que empieza antes de `distance` metros desde el inicio.
    public func segmentIndex(atDistance distance: Double) -> Int {
        guard segmentCount > 0 else { return 0 }
        var low = 0, high = segmentCount - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if cumulative[mid] <= distance { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
