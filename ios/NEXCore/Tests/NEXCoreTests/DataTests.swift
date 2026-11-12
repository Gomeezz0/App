import XCTest
@testable import NEXCore

final class TripTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // Noviembre de 2026: el día 2 es lunes.
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private let office = Place(id: "office", name: "Oficina", coordinate: offset(sol, north: 5000))
    private let gym = Place(id: "gym", name: "Gimnasio", coordinate: offset(sol, east: 3000))

    private func trip(_ place: Place, _ start: Date, completed: Bool = true) -> Trip {
        Trip(startedAt: start, endedAt: start.addingTimeInterval(1200), destination: place, distance: 6000,
             maxSpeed: 22, completed: completed)
    }

    func testRoutineDetectedAtUsualTime() {
        let trips = [
            trip(office, date(2, 8, 10)), trip(office, date(3, 8, 25)), trip(office, date(4, 7, 55)),
            trip(gym, date(2, 19)), trip(gym, date(4, 19)),
        ]
        let morning = RoutineDetector.suggestions(from: trips, at: date(5, 8, 0), near: sol, calendar: calendar)
        XCTAssertEqual(morning.map(\.place.name), ["Oficina"])
        XCTAssertEqual(morning.first?.visits, 3)
        // Por la tarde no, y el gimnasio solo tiene dos visitas.
        XCTAssertTrue(RoutineDetector.suggestions(from: trips, at: date(5, 19), near: sol, calendar: calendar).isEmpty)
        // En fin de semana tampoco.
        XCTAssertTrue(RoutineDetector.suggestions(from: trips, at: date(7, 8), near: sol, calendar: calendar).isEmpty)
    }

    func testRoutineIgnoresCurrentPlaceAndUnfinishedTrips() {
        let trips = [trip(office, date(2, 8)), trip(office, date(3, 8)), trip(office, date(4, 8))]
        XCTAssertTrue(
            RoutineDetector.suggestions(from: trips, at: date(5, 8), near: office.coordinate, calendar: calendar).isEmpty)
        let unfinished = trips.map { trip($0.destination, $0.startedAt, completed: false) }
        XCTAssertTrue(RoutineDetector.suggestions(from: unfinished, at: date(5, 8), near: sol, calendar: calendar).isEmpty)
    }

    func testStats() {
        let trips = [trip(office, date(2, 8)), trip(gym, date(9, 19))]
        let all = TripStats(trips: trips)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.distance, 12_000)
        XCTAssertEqual(all.averageSpeed, 5, accuracy: 0.01)
        XCTAssertEqual(TripStats.since(date(8, 0), in: trips).count, 1)
        XCTAssertEqual(TripStats(trips: []).averageSpeed, 0)
    }
}

final class APIDecodingTests: XCTestCase {
    func testDecodesAlertListFromBackend() throws {
        let json = """
        {"alerts":[{"id":"7b0e6c0e-4a43-4a8e-9d4b-2f8a3c1f0a11","type":"speed_camera","lat":40.4168,"lon":-3.7038,
        "heading":null,"approximate":false,"zoneRadiusM":null,"source":"official","confidence":1,"level":"high",
        "confirmations":0,"denials":0,"createdAt":"2026-11-11T10:00:00.123Z","expiresAt":null,"mine":false,"myVote":null},
        {"id":"2","type":"police","lat":40.415,"lon":-3.705,"heading":null,"approximate":true,"zoneRadiusM":1000,
        "source":"community","confidence":0.487,"level":"medium","confirmations":2,"denials":0,
        "createdAt":"2026-11-11T10:00:00Z","expiresAt":"2026-11-11T10:45:00.000Z","mine":true,"myVote":"confirm"}]}
        """
        struct List: Decodable { var alerts: [CommunityAlert] }
        let alerts = try APIClient.decoder().decode(List.self, from: Data(json.utf8)).alerts
        XCTAssertEqual(alerts.count, 2)
        XCTAssertEqual(alerts[0].type, .speedCamera)
        XCTAssertTrue(alerts[0].isOfficial)
        XCTAssertNil(alerts[0].expiresAt)
        XCTAssertEqual(alerts[1].zoneRadiusM, 1000)
        XCTAssertEqual(alerts[1].myVote, .confirm)
        XCTAssertEqual(alerts[1].expiresAt!.timeIntervalSince(alerts[1].createdAt), 2700, accuracy: 1)
    }

    func testAlertTypesMatchBackendContract() {
        XCTAssertEqual(
            AlertType.allCases.map(\.rawValue),
            ["police", "speed_camera", "accident", "traffic_jam", "stopped_vehicle", "road_object", "roadworks",
             "road_closed", "weather", "hazard"])
    }
}
