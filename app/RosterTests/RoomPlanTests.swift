import XCTest

/// Geometry sanity checks — cheap insurance that layout edits never make
/// two agents overlap.
final class RoomPlanTests: XCTestCase {

    func testLoneAgentTakesTheChair() {
        for station in RoomPlan.stations {
            XCTAssertEqual(station.seatPoint(slot: 0, of: 1), station.chairCenter)
        }
    }

    func testSharedStationSpreadsSeatsApart() {
        let station = RoomPlan.stations[0]
        let left = station.seatPoint(slot: 0, of: 2)
        let right = station.seatPoint(slot: 1, of: 2)
        XCTAssertNotEqual(left, right)
        // Symmetric around the chair.
        XCTAssertEqual((left.x + right.x) / 2, station.chairCenter.x, accuracy: 0.001)
    }

    func testStandPointsOfSeatSlotsDoNotCollide() {
        let station = RoomPlan.stations[0]
        XCTAssertNotEqual(station.standPoint(slot: 0), station.standPoint(slot: 1))
    }

    func testDeskQueueSlotsAreDistinct() {
        let points = (0..<6).map { RoomPlan.arrival(deskSlot: $0) }
        XCTAssertEqual(Set(points.map(\.x)).count, points.count,
                       "every desk slot needs its own spot")
    }

    func testStationsSitInsideTheWalls() {
        for station in RoomPlan.stations {
            XCTAssertTrue(RoomPlan.wall.contains(station.deskRect))
        }
        XCTAssertTrue(RoomPlan.wall.contains(RoomPlan.myDesk))
    }
}
