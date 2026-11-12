import XCTest
@testable import NEXCore

/// Ruta en L: 1 km al norte, giro a la derecha y 500 m al este.
private func makeRoute() -> Route {
    let corner = offset(sol, north: 1000)
    let end = offset(sol, north: 1000, east: 500)
    let line = Polyline([sol, corner, end])
    return Route(
        name: "Prueba", polyline: line, distance: line.length, expectedTravelTime: 150,
        steps: [
            RouteStep(instruction: "Gira a la derecha por Calle Mayor", maneuverDistance: 1000),
            RouteStep(instruction: "Tu destino está a la derecha", maneuverDistance: line.length),
        ])
}

final class RouteTrackerTests: XCTestCase {
    func testProgressAlongRoute() {
        var tracker = RouteTracker(route: makeRoute())
        let p = tracker.update(location: offset(sol, north: 400, east: 8), horizontalAccuracy: 10)
        XCTAssertFalse(p.isOffRoute)
        XCTAssertEqual(p.distanceTravelled, 400, accuracy: 5)
        XCTAssertEqual(p.distanceRemaining, 1100, accuracy: 8)
        XCTAssertEqual(p.stepIndex, 0)
        XCTAssertEqual(p.distanceToManeuver, 600, accuracy: 5)
        XCTAssertEqual(p.timeRemaining, 110, accuracy: 2)
        XCTAssertEqual(p.snappedBearing, 0, accuracy: 1)

        let after = tracker.update(location: offset(sol, north: 1000, east: 200), horizontalAccuracy: 10)
        XCTAssertEqual(after.stepIndex, 1)
        XCTAssertEqual(after.distanceToManeuver, 300, accuracy: 5)
        XCTAssertEqual(after.snappedBearing, 90, accuracy: 1)
    }

    func testOffRouteNeedsSeveralReadings() {
        var tracker = RouteTracker(route: makeRoute())
        _ = tracker.update(location: offset(sol, north: 300), horizontalAccuracy: 10)
        let away = offset(sol, north: 320, east: 80)
        XCTAssertFalse(tracker.update(location: away, horizontalAccuracy: 10).isOffRoute)
        XCTAssertFalse(tracker.update(location: away, horizontalAccuracy: 10).isOffRoute)
        XCTAssertTrue(tracker.update(location: away, horizontalAccuracy: 10).isOffRoute)
        // Al volver a la ruta se recupera.
        XCTAssertFalse(tracker.update(location: offset(sol, north: 350), horizontalAccuracy: 10).isOffRoute)
    }

    func testFarAwayIsOffRouteImmediately() {
        var tracker = RouteTracker(route: makeRoute())
        _ = tracker.update(location: offset(sol, north: 250), horizontalAccuracy: 10)
        XCTAssertTrue(tracker.update(location: offset(sol, north: 300, east: 400), horizontalAccuracy: 10).isOffRoute)
    }

    func testStartingAwayFromTheRoadIsNotOffRoute() {
        // Salida desde un aparcamiento a 200 m de la calzada: no es un desvío mientras se acerca.
        var tracker = RouteTracker(route: makeRoute())
        for east in [200.0, 200, 200, 150, 90] {
            let p = tracker.update(location: offset(sol, north: 50, east: east), horizontalAccuracy: 10)
            XCTAssertFalse(p.isOffRoute)
            XCTAssertEqual(p.stepIndex, 0)
        }
        // Una vez en la ruta, la detección normal de desvío vuelve a aplicarse.
        XCTAssertFalse(tracker.update(location: offset(sol, north: 100), horizontalAccuracy: 10).isOffRoute)
        XCTAssertTrue(tracker.update(location: offset(sol, north: 150, east: 300), horizontalAccuracy: 10).isOffRoute)
    }

    func testDrivingAwayBeforeJoiningIsOffRoute() {
        var tracker = RouteTracker(route: makeRoute())
        XCTAssertFalse(tracker.update(location: offset(sol, north: 50, east: 200), horizontalAccuracy: 10).isOffRoute)
        XCTAssertFalse(tracker.update(location: offset(sol, north: 50, east: 300), horizontalAccuracy: 10).isOffRoute)
        XCTAssertTrue(tracker.update(location: offset(sol, north: 50, east: 380), horizontalAccuracy: 10).isOffRoute)
    }

    func testPoorAccuracyNeverTriggersOffRoute() {
        var tracker = RouteTracker(route: makeRoute())
        let away = offset(sol, north: 300, east: 400)
        for _ in 0..<5 {
            XCTAssertFalse(tracker.update(location: away, horizontalAccuracy: 150).isOffRoute)
        }
        XCTAssertFalse(tracker.update(location: away, horizontalAccuracy: -1).isOffRoute)
    }

    func testArrival() {
        var tracker = RouteTracker(route: makeRoute())
        XCTAssertFalse(tracker.update(location: offset(sol, north: 1000, east: 300), horizontalAccuracy: 10).hasArrived)
        let p = tracker.update(location: offset(sol, north: 1000, east: 485), horizontalAccuracy: 10)
        XCTAssertTrue(p.hasArrived)
        XCTAssertEqual(p.distanceRemaining, 15, accuracy: 5)
    }

    func testDoesNotJumpToOverlappingLaterSection() {
        // Ida y vuelta por la misma calle: al principio debe quedarse en la ida.
        let far = offset(sol, north: 2000)
        let line = Polyline([sol, far, offset(sol, east: 5)])
        let route = Route(name: "Ida y vuelta", polyline: line, distance: line.length, expectedTravelTime: 300, steps: [])
        var tracker = RouteTracker(route: route)
        let p = tracker.update(location: offset(sol, north: 200, east: 4), horizontalAccuracy: 10)
        XCTAssertEqual(p.distanceTravelled, 200, accuracy: 10)
    }

    func testRouteClassification() {
        let line = Polyline([sol, offset(sol, north: 100)])
        func route(_ name: String, _ distance: Double, _ time: TimeInterval) -> Route {
            Route(name: name, polyline: line, distance: distance, expectedTravelTime: time, steps: [])
        }
        let sorted = [route("B", 9_000, 900), route("A", 12_000, 600), route("C", 11_000, 800)].classified()
        XCTAssertEqual(sorted.map(\.name), ["A", "C", "B"])
        XCTAssertEqual(sorted.map(\.kind), [.fastest, .alternative, .shortest])
        // Si la más rápida es también la más corta, no hay etiqueta "más corta".
        let single = [route("A", 5_000, 600), route("B", 6_000, 700)].classified()
        XCTAssertEqual(single.map(\.kind), [.fastest, .alternative])
    }
}

final class GuidanceTests: XCTestCase {
    private func drive(_ announcer: inout GuidanceAnnouncer, north: [Double], speed: Double) -> [String] {
        let route = makeRoute()
        var tracker = RouteTracker(route: route)
        var spoken: [String] = []
        for meters in north {
            let progress = tracker.update(location: offset(sol, north: meters), horizontalAccuracy: 5)
            spoken += announcer.announcements(for: progress, route: route, speed: speed).map(\.text)
        }
        return spoken
    }

    func testPrepareThenNowOncePerManeuver() {
        var announcer = GuidanceAnnouncer(verbosity: .standard)
        // A 50 km/h (≈14 m/s): aviso previo a 250 m y orden final a 56 m.
        let spoken = drive(&announcer, north: [100, 500, 760, 800, 900, 950, 960, 990], speed: 14)
        XCTAssertEqual(spoken, [
            "En 250 metros, gira a la derecha por Calle Mayor",
            "Gira a la derecha por Calle Mayor",
        ])
    }

    func testManeuverKindFromInstruction() {
        XCTAssertEqual(ManeuverKind(instruction: "Gira a la derecha por Calle de la Salud"), .right)
        XCTAssertEqual(ManeuverKind(instruction: "Gira a la izquierda por Gran Vía"), .left)
        XCTAssertEqual(ManeuverKind(instruction: "Mantente a la izquierda en la bifurcación"), .slightLeft)
        XCTAssertEqual(ManeuverKind(instruction: "Toma la salida 12 a la derecha"), .slightRight)
        XCTAssertEqual(ManeuverKind(instruction: "En la rotonda, toma la segunda salida"), .roundabout)
        XCTAssertEqual(ManeuverKind(instruction: "Haz un cambio de sentido"), .uTurn)
        XCTAssertEqual(ManeuverKind(instruction: "Tu destino está a la derecha"), .arrive)
        XCTAssertEqual(ManeuverKind(instruction: "Continúa por Paseo de la Castellana"), .straight)
        XCTAssertEqual(ManeuverKind(instruction: "Turn left onto Main St"), .left)
    }

    func testFasterMeansEarlier() {
        XCTAssertGreaterThan(GuidanceAnnouncer.prepareDistance(speed: 33), GuidanceAnnouncer.prepareDistance(speed: 8))
        XCTAssertEqual(GuidanceAnnouncer.prepareDistance(speed: 33), 594, accuracy: 1)
        XCTAssertEqual(GuidanceAnnouncer.nowDistance(speed: 0), 35)
    }

    func testVerbosityLevels() {
        var full = GuidanceAnnouncer(verbosity: .full)
        XCTAssertEqual(drive(&full, north: [100], speed: 14), ["Continúa 900 metros"])
        var minimal = GuidanceAnnouncer(verbosity: .minimal)
        XCTAssertEqual(drive(&minimal, north: [100, 800, 960], speed: 14), ["Gira a la derecha por Calle Mayor"])
        var off = GuidanceAnnouncer(verbosity: .off)
        XCTAssertEqual(drive(&off, north: [100, 800, 960], speed: 14), [])
    }

    func testArrivalAndOffRouteAnnouncedOnce() {
        let route = makeRoute()
        var tracker = RouteTracker(route: route)
        var announcer = GuidanceAnnouncer(verbosity: .standard)
        let away = offset(sol, north: 300, east: 400)
        var spoken: [String] = []
        _ = tracker.update(location: offset(sol, north: 300), horizontalAccuracy: 5)
        for _ in 0..<3 {
            let progress = tracker.update(location: away, horizontalAccuracy: 5)
            spoken += announcer.announcements(for: progress, route: route, speed: 10).map(\.text)
        }
        XCTAssertEqual(spoken, ["Recalculando ruta"])

        spoken = []
        for _ in 0..<2 {
            let progress = tracker.update(location: offset(sol, north: 1000, east: 495), horizontalAccuracy: 5)
            spoken += announcer.announcements(for: progress, route: route, speed: 3).map(\.text)
        }
        XCTAssertEqual(spoken, ["Has llegado a tu destino"])
    }
}

final class AlertMonitorTests: XCTestCase {
    private let line = makeRoute().polyline

    private func alert(_ id: String, _ type: AlertType, at c: Coordinate, level: ConfidenceLevel = .medium,
                       zone: Double? = nil, heading: Double? = nil) -> CommunityAlert {
        CommunityAlert(
            id: id, type: type, lat: c.latitude, lon: c.longitude, heading: heading, approximate: zone != nil,
            zoneRadiusM: zone, level: level)
    }

    func testOnlyAlertsAheadOnRoute() {
        let alerts = [
            alert("afterTurn", .trafficJam, at: offset(sol, north: 1000, east: 300)),
            alert("ahead", .accident, at: offset(sol, north: 800, east: 10)),
            alert("behind", .roadworks, at: offset(sol, north: 100)),
            alert("off", .hazard, at: offset(sol, north: 800, east: 400)),
        ]
        let index = RouteAlertIndex(alerts: alerts, route: line)
        XCTAssertEqual(index.entries.map(\.alert.id), ["behind", "ahead", "afterTurn"])
        let ahead = index.ahead(from: 300, range: 5000, preferences: [:])
        XCTAssertEqual(ahead.map(\.id), ["ahead", "afterTurn"])
        XCTAssertEqual(ahead[0].distance, 500, accuracy: 10)
        XCTAssertEqual(ahead[1].distance, 1000, accuracy: 10)
        XCTAssertEqual(index.ahead(from: 300, range: 600, preferences: [:]).map(\.id), ["ahead"])
    }

    func testFreeDriveUsesFrontCone() {
        let monitor = AlertMonitor()
        let alerts = [
            alert("front", .accident, at: offset(sol, north: 600, east: 50)),
            alert("side", .accident, at: offset(sol, east: 600)),
            alert("back", .accident, at: offset(sol, north: -600)),
            alert("oncoming", .accident, at: offset(sol, north: 700), heading: 180),
        ]
        let ahead = monitor.alertsAhead(alerts, location: sol, course: 0, preferences: [:], range: 2000)
        XCTAssertEqual(ahead.map(\.id), ["front"])
        // Parado (sin rumbo) se muestran todos los cercanos.
        XCTAssertEqual(monitor.alertsAhead(alerts, location: sol, course: nil, preferences: [:], range: 2000).count, 4)
    }

    func testHiddenPreferenceAndZones() {
        let alerts = [
            alert("hidden", .roadworks, at: offset(sol, north: 500)),
            // Zona de control con centro a 600 m de la ruta: la ruta la cruza gracias a su radio de 1 km.
            alert("zone", .police, at: offset(sol, north: 900, east: 600), zone: 1000),
        ]
        let index = RouteAlertIndex(alerts: alerts, route: line)
        let ahead = index.ahead(from: 0, range: 5000, preferences: [.roadworks: .hidden])
        XCTAssertEqual(ahead.map(\.id), ["zone"])
        // La ruta entra en la zona unos 800 m antes del punto más cercano al centro (≈ km 0,9).
        XCTAssertEqual(ahead[0].distance, 100, accuracy: 15)
        // Dentro de la zona sigue vigente, con distancia 0.
        XCTAssertEqual(index.ahead(from: 600, range: 5000, preferences: [.roadworks: .hidden]).first?.distance, 0)
    }

    func testVoiceOncePerAlertAndOnlyWithEnoughConfidence() {
        var monitor = AlertMonitor()
        let items = [
            AlertAhead(alert: alert("a", .accident, at: sol, level: .high), distance: 400),
            AlertAhead(alert: alert("b", .roadObject, at: sol, level: .low), distance: 200),
            AlertAhead(alert: alert("c", .roadworks, at: sol), distance: 250),
            AlertAhead(alert: alert("d", .trafficJam, at: sol), distance: 4000),
            AlertAhead(alert: alert("e", .police, at: sol, zone: 1000), distance: 100),
        ]
        let prefs: [AlertType: AlertPreference] = [.roadworks: .silent]
        let first = monitor.announcements(for: items, speed: 25, preferences: prefs).map(\.text)
        XCTAssertEqual(first, ["Accidente a 400 metros", "Zona de control. Respeta los límites de velocidad"])
        XCTAssertEqual(monitor.announcements(for: items, speed: 25, preferences: prefs), [])
    }

    func testWarningDistanceScalesWithSpeed() {
        XCTAssertEqual(AlertMonitor.warningDistance(speed: 5), 300)
        XCTAssertEqual(AlertMonitor.warningDistance(speed: 33), 660)
        XCTAssertEqual(AlertMonitor.warningDistance(speed: 200), 1500)
    }
}
