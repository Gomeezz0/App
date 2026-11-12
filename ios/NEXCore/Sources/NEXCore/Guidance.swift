import Foundation

public struct Announcement: Sendable, Equatable {
    public enum Kind: Sendable { case maneuver, alert, status }
    public var text: String
    public var kind: Kind

    public init(_ text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

/// Decide qué indicaciones de giro se dicen y cuándo. La antelación depende de la velocidad
/// (segundos, no metros fijos): a 120 km/h se avisa mucho antes que a 30 km/h.
public struct GuidanceAnnouncer: Sendable {
    private enum Stage: Int, Comparable {
        case none, preview, prepare, now
        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    public var verbosity: VoiceVerbosity
    private var stepIndex: Int?
    private var stage: Stage = .none
    private var announcedArrival = false
    private var announcedOffRoute = false

    public init(verbosity: VoiceVerbosity = .standard) {
        self.verbosity = verbosity
    }

    /// Distancia a la que se da el aviso previo ("En 300 metros…").
    public static func prepareDistance(speed: Double) -> Double { min(2000, max(250, speed * 18)) }
    /// Distancia a la que se da la orden final.
    public static func nowDistance(speed: Double) -> Double { min(200, max(35, speed * 4)) }

    public mutating func announcements(for progress: RouteProgress, route: Route, speed: Double) -> [Announcement] {
        guard verbosity != .off else { return [] }

        if progress.isOffRoute {
            guard !announcedOffRoute else { return [] }
            announcedOffRoute = true
            return [Announcement("Recalculando ruta", kind: .status)]
        }
        announcedOffRoute = false

        if progress.hasArrived {
            guard !announcedArrival else { return [] }
            announcedArrival = true
            return [Announcement("Has llegado a tu destino", kind: .status)]
        }

        guard let index = progress.stepIndex else { return [] }
        if index != stepIndex {
            stepIndex = index
            stage = .none
        }
        let instruction = route.steps[index].instruction
        guard !instruction.isEmpty else { return [] }

        let distance = progress.distanceToManeuver
        let prepare = Self.prepareDistance(speed: speed)
        let now = Self.nowDistance(speed: speed)

        let target: Stage
        if distance <= now {
            target = .now
        } else if distance <= prepare {
            target = .prepare
        } else {
            target = .preview
        }
        guard target > stage else { return [] }
        stage = target

        switch target {
        case .now:
            return [Announcement(instruction, kind: .maneuver)]
        case .prepare:
            guard verbosity != .minimal else { return [] }
            return [Announcement("En \(NEXFormat.spokenDistance(distance)), \(lowercasedFirst(instruction))", kind: .maneuver)]
        case .preview:
            // Solo merece la pena si queda un tramo largo por delante.
            guard verbosity == .full, distance > prepare * 2 else { return [] }
            return [Announcement("Continúa \(NEXFormat.spokenDistance(distance))", kind: .maneuver)]
        case .none:
            return []
        }
    }

    private func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
