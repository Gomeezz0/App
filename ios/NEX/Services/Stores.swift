import Foundation
import NEXCore
import Observation

enum MapAppearance: String, CaseIterable, Identifiable {
    case automatic, day, night

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automático"
        case .day: return "Día"
        case .night: return "Noche"
        }
    }
}

/// Preferencias del usuario, guardadas en `UserDefaults`.
@MainActor
@Observable
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") } }
    var verbosity: VoiceVerbosity { didSet { defaults.set(verbosity.rawValue, forKey: "verbosity") } }
    var mapAppearance: MapAppearance { didSet { defaults.set(mapAppearance.rawValue, forKey: "mapAppearance") } }
    var avoidTolls: Bool { didSet { defaults.set(avoidTolls, forKey: "avoidTolls") } }
    var avoidHighways: Bool { didSet { defaults.set(avoidHighways, forKey: "avoidHighways") } }
    var showTraffic: Bool { didSet { defaults.set(showTraffic, forKey: "showTraffic") } }
    /// Reduce la frecuencia de consulta de avisos y las animaciones de cámara.
    var batterySaver: Bool { didSet { defaults.set(batterySaver, forKey: "batterySaver") } }
    var saveTrips: Bool { didSet { defaults.set(saveTrips, forKey: "saveTrips") } }
    var alertPreferences: [AlertType: AlertPreference] {
        didSet {
            let raw = Dictionary(uniqueKeysWithValues: alertPreferences.map { ($0.key.rawValue, $0.value.rawValue) })
            defaults.set(raw, forKey: "alertPreferences")
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasOnboarded = defaults.bool(forKey: "hasOnboarded")
        verbosity = VoiceVerbosity(rawValue: defaults.string(forKey: "verbosity") ?? "") ?? .standard
        mapAppearance = MapAppearance(rawValue: defaults.string(forKey: "mapAppearance") ?? "") ?? .automatic
        avoidTolls = defaults.bool(forKey: "avoidTolls")
        avoidHighways = defaults.bool(forKey: "avoidHighways")
        showTraffic = defaults.object(forKey: "showTraffic") as? Bool ?? true
        batterySaver = defaults.bool(forKey: "batterySaver")
        saveTrips = defaults.object(forKey: "saveTrips") as? Bool ?? true
        var preferences: [AlertType: AlertPreference] = [:]
        for (key, value) in defaults.dictionary(forKey: "alertPreferences") as? [String: String] ?? [:] {
            if let type = AlertType(rawValue: key), let preference = AlertPreference(rawValue: value) {
                preferences[type] = preference
            }
        }
        alertPreferences = preferences
    }

    func preference(for type: AlertType) -> AlertPreference { alertPreferences[type] ?? .voice }
}

/// Historial de viajes en un archivo JSON local. Nunca sale del dispositivo.
@MainActor
@Observable
final class TripStore {
    private(set) var trips: [Trip] = []
    @ObservationIgnored private let url: URL

    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("trips.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Trip].self, from: data) {
            trips = saved
        }
    }

    func add(_ trip: Trip) {
        trips.insert(trip, at: 0)
        // Tope para que el archivo no crezca sin límite.
        if trips.count > 500 { trips.removeLast(trips.count - 500) }
        persist()
    }

    func remove(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        persist()
    }

    func removeAll() {
        trips = []
        persist()
    }

    /// Destinos recientes sin repetir, para el buscador.
    var recentPlaces: [Place] {
        var seen = Set<String>()
        return trips.map(\.destination).filter { seen.insert($0.id).inserted }.prefix(8).map { $0 }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(trips) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
