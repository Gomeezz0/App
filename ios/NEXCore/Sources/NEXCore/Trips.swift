import Foundation

/// Viaje registrado. Se guarda únicamente en el dispositivo.
public struct Trip: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var destination: Place
    /// Metros realmente recorridos según el GPS.
    public var distance: Double
    /// m/s.
    public var maxSpeed: Double
    /// `true` si se llegó al destino; `false` si la navegación se detuvo antes.
    public var completed: Bool

    public init(
        id: UUID = UUID(), startedAt: Date, endedAt: Date, destination: Place, distance: Double, maxSpeed: Double,
        completed: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.destination = destination
        self.distance = distance
        self.maxSpeed = maxSpeed
        self.completed = completed
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    /// m/s.
    public var averageSpeed: Double { duration > 0 ? distance / duration : 0 }
}

public struct TripStats: Sendable, Equatable {
    public var count = 0
    public var distance = 0.0
    public var duration: TimeInterval = 0
    public var maxSpeed = 0.0

    public var averageSpeed: Double { duration > 0 ? distance / duration : 0 }

    public init(trips: [Trip]) {
        for trip in trips {
            count += 1
            distance += trip.distance
            duration += trip.duration
            maxSpeed = max(maxSpeed, trip.maxSpeed)
        }
    }

    public static func since(_ date: Date, in trips: [Trip]) -> TripStats {
        TripStats(trips: trips.filter { $0.startedAt >= date })
    }
}

/// Destino al que el usuario suele ir a una hora parecida.
public struct RoutineSuggestion: Sendable, Equatable, Identifiable {
    public var place: Place
    public var visits: Int
    public var id: String { place.id }
}

/// Detecta rutas habituales a partir del historial local: mismo destino (±150 m),
/// misma franja horaria (±90 min) y mismo tipo de día (laborable o fin de semana).
public enum RoutineDetector {
    public static func suggestions(
        from trips: [Trip], at date: Date, near location: Coordinate?, calendar: Calendar = .current,
        minimumVisits: Int = 3, limit: Int = 2
    ) -> [RoutineSuggestion] {
        let nowMinutes = minutesOfDay(date, calendar)
        let weekend = calendar.isDateInWeekend(date)

        var clusters: [(place: Place, visits: Int, last: Date)] = []
        for trip in trips where trip.completed {
            guard calendar.isDateInWeekend(trip.startedAt) == weekend else { continue }
            let delta = abs(minutesOfDay(trip.startedAt, calendar) - nowMinutes)
            guard min(delta, 1440 - delta) <= 90 else { continue }
            if let index = clusters.firstIndex(where: {
                Geo.distance($0.place.coordinate, trip.destination.coordinate) <= 150
            }) {
                clusters[index].visits += 1
                if trip.startedAt > clusters[index].last {
                    clusters[index].last = trip.startedAt
                    clusters[index].place = trip.destination
                }
            } else {
                clusters.append((trip.destination, 1, trip.startedAt))
            }
        }

        return clusters
            .filter { cluster in
                guard cluster.visits >= minimumVisits else { return false }
                // No se sugiere el sitio en el que ya se está.
                if let location, Geo.distance(location, cluster.place.coordinate) < 300 { return false }
                return true
            }
            .sorted { ($0.visits, $0.last) > ($1.visits, $1.last) }
            .prefix(limit)
            .map { RoutineSuggestion(place: $0.place, visits: $0.visits) }
    }

    private static func minutesOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
