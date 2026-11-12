import ActivityKit
import SwiftUI

/// Datos de la Live Activity de navegación. Lo comparten la app (que la actualiza)
/// y la extensión de widgets (que la dibuja).
struct NavigationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case navigating, rerouting, arrived }

        var phase: Phase
        /// Texto de la próxima maniobra.
        var instruction: String
        /// Metros hasta la próxima maniobra.
        var distanceToManeuver: Double
        /// Metros hasta el destino.
        var distanceRemaining: Double
        /// Hora estimada de llegada.
        var arrival: Date
    }

    var destinationName: String
}

/// Paleta mínima de marca para la extensión (la app tiene la completa en `NEXColor`).
enum NEXBrand {
    static let black = Color(red: 0.031, green: 0.031, blue: 0.039)
    static let red = Color(red: 0.882, green: 0.071, blue: 0.137)
    static let text = Color(red: 0.961, green: 0.961, blue: 0.969)
    static let textDim = Color(red: 0.663, green: 0.678, blue: 0.710)
}
