import XCTest
@testable import NEXCore

let sol = Coordinate(latitude: 40.4168, longitude: -3.7038)

/// Desplaza una coordenada los metros indicados hacia el norte y el este.
func offset(_ c: Coordinate, north: Double = 0, east: Double = 0) -> Coordinate {
    Coordinate(
        latitude: c.latitude + north / 111_320,
        longitude: c.longitude + east / (111_320 * cos(c.latitude * .pi / 180)))
}

final class GeoTests: XCTestCase {
    func testDistanceMadridBarcelona() {
        let barcelona = Coordinate(latitude: 41.3874, longitude: 2.1686)
        XCTAssertEqual(Geo.distance(sol, barcelona), 505_000, accuracy: 3_000)
        XCTAssertEqual(Geo.distance(sol, sol), 0)
    }

    func testBearing() {
        XCTAssertEqual(Geo.bearing(from: sol, to: offset(sol, north: 500)), 0, accuracy: 0.5)
        XCTAssertEqual(Geo.bearing(from: sol, to: offset(sol, east: 500)), 90, accuracy: 0.5)
        XCTAssertEqual(Geo.bearing(from: sol, to: offset(sol, north: -500)), 180, accuracy: 0.5)
        XCTAssertEqual(Geo.bearing(from: sol, to: offset(sol, east: -500)), 270, accuracy: 0.5)
    }

    func testAngleDifferenceWrapsAround() {
        XCTAssertEqual(Geo.angleDifference(350, 10), 20)
        XCTAssertEqual(Geo.angleDifference(10, 350), 20)
        XCTAssertEqual(Geo.angleDifference(0, 180), 180)
    }

    func testProjectionOntoSegment() {
        let a = sol, b = offset(sol, north: 1000)
        let p = offset(sol, north: 400, east: 30)
        let result = Geo.project(p, ontoSegmentFrom: a, to: b)
        XCTAssertEqual(result.t, 0.4, accuracy: 0.01)
        XCTAssertEqual(result.distance, 30, accuracy: 1)
        // Más allá del extremo se queda en el extremo.
        let beyond = Geo.project(offset(sol, north: 1200), ontoSegmentFrom: a, to: b)
        XCTAssertEqual(beyond.t, 1)
        XCTAssertEqual(beyond.distance, 200, accuracy: 2)
    }

    func testPolylineDistanceAlong() {
        let line = Polyline([sol, offset(sol, north: 1000), offset(sol, north: 1000, east: 500)])
        XCTAssertEqual(line.length, 1500, accuracy: 5)
        let hit = line.nearest(to: offset(sol, north: 1010, east: 200))!
        XCTAssertEqual(hit.segment, 1)
        XCTAssertEqual(hit.distanceAlong, 1200, accuracy: 5)
        XCTAssertEqual(hit.offset, 10, accuracy: 1)
        XCTAssertEqual(line.segmentIndex(atDistance: 0), 0)
        XCTAssertEqual(line.segmentIndex(atDistance: 1200), 1)
        XCTAssertEqual(line.segmentIndex(atDistance: 99_999), 1)
        XCTAssertNil(Polyline([sol]).nearest(to: sol))
    }

    func testFormatting() {
        XCTAssertEqual(NEXFormat.distance(347), "350 m")
        XCTAssertEqual(NEXFormat.distance(1240), "1,2 km")
        XCTAssertEqual(NEXFormat.distance(24_600), "25 km")
        XCTAssertEqual(NEXFormat.duration(480), "8 min")
        XCTAssertEqual(NEXFormat.duration(3900), "1 h 05 min")
        XCTAssertEqual(NEXFormat.spokenDistance(310), "300 metros")
        XCTAssertEqual(NEXFormat.spokenDistance(42), "40 metros")
        XCTAssertEqual(NEXFormat.spokenDistance(1000), "un kilómetro")
        XCTAssertEqual(NEXFormat.spokenDistance(1480), "1 coma 5 kilómetros")
        XCTAssertEqual(NEXFormat.spokenDistance(2100), "2 kilómetros")
        XCTAssertEqual(NEXFormat.kmh(33.33), 120)
    }

    func testSolarElevationMadrid() {
        // Valores de referencia: 21 de junio de 2026, mediodía solar ≈ 12:18 UTC (≈ 73°).
        let noon = Date(timeIntervalSince1970: 1_782_044_280)
        XCTAssertEqual(Solar.elevation(at: noon, coordinate: sol), 73, accuracy: 0.5)
        XCTAssertFalse(Solar.isNight(at: noon, coordinate: sol))
        let midnight = noon.addingTimeInterval(-12 * 3600 - 18 * 60)
        XCTAssertTrue(Solar.isNight(at: midnight, coordinate: sol))
        // Amanecer ≈ 04:45 UTC: el sol roza el horizonte y ya no se considera noche.
        let sunrise = midnight.addingTimeInterval(4 * 3600 + 45 * 60)
        XCTAssertEqual(Solar.elevation(at: sunrise, coordinate: sol), -0.8, accuracy: 0.5)
        XCTAssertFalse(Solar.isNight(at: sunrise, coordinate: sol))
    }
}
