import Foundation

/// Formato de distancias y tiempos en español, determinista (no depende de la configuración regional).
public enum NEXFormat {
    /// "350 m", "1,2 km", "24 km".
    public static func distance(_ meters: Double) -> String {
        let m = max(0, meters)
        if m < 1000 { return "\(Int((m / 10).rounded()) * 10) m" }
        let km = m / 1000
        if km < 10 { return String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",") + " km" }
        return "\(Int(km.rounded())) km"
    }

    /// "8 min", "1 h 05 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
    }

    /// Distancia para leer en voz alta, redondeada a valores fáciles de oír.
    public static func spokenDistance(_ meters: Double) -> String {
        let m = max(0, meters)
        if m >= 950 {
            let halves = (m / 500).rounded() / 2
            if halves == 1 { return "un kilómetro" }
            let text = halves == halves.rounded()
                ? "\(Int(halves))"
                : String(format: "%.1f", halves).replacingOccurrences(of: ".", with: " coma ")
            return "\(text) kilómetros"
        }
        let step: Double = m >= 100 ? 50 : 10
        let rounded = max(step, (m / step).rounded() * step)
        return "\(Int(rounded)) metros"
    }

    /// km/h a partir de m/s.
    public static func kmh(_ metersPerSecond: Double) -> Int {
        Int((max(0, metersPerSecond) * 3.6).rounded())
    }
}
