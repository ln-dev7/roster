import XCTest

/// Geometry sanity checks — cheap insurance that layout edits never make
/// two agents overlap or push a desk through a wall.
final class RoomPlanTests: XCTestCase {

    func testLoneAgentTakesTheChair() {
        let station = RoomPlan.station(index: 0, of: 3)
        XCTAssertEqual(station.seatPoint(slot: 0, of: 1), station.chairCenter)
    }

    func testSharedStationSpreadsSeatsApart() {
        let station = RoomPlan.station(index: 1, of: 3)
        let left = station.seatPoint(slot: 0, of: 2)
        let right = station.seatPoint(slot: 1, of: 2)
        XCTAssertNotEqual(left, right)
        // Symmetric around the chair.
        XCTAssertEqual((left.x + right.x) / 2, station.chairCenter.x, accuracy: 0.001)
    }

    func testStandPointsOfSeatSlotsDoNotCollide() {
        let station = RoomPlan.station(index: 0, of: 3)
        XCTAssertNotEqual(station.standPoint(slot: 0), station.standPoint(slot: 1))
    }

    func testDeskQueueSlotsAreDistinct() {
        let points = (0..<6).map { RoomPlan.arrival(deskSlot: $0) }
        XCTAssertEqual(Set(points.map(\.x)).count, points.count,
                       "every desk slot needs its own spot")
    }

    func testStationsStayInsideTheWallsForEveryRoomSize() {
        for count in 1...Office.maxStations {
            for index in 0..<count {
                let desk = RoomPlan.station(index: index, of: count).deskRect
                XCTAssertTrue(RoomPlan.wall.contains(desk),
                              "desk \(index + 1)/\(count) leaves the room")
            }
        }
        XCTAssertTrue(RoomPlan.wall.contains(RoomPlan.myDesk))
    }

    func testNeighbouringDesksNeverTouch() {
        for count in 2...Office.maxStations {
            for index in 1..<count {
                let previous = RoomPlan.station(index: index - 1, of: count).deskRect
                let current = RoomPlan.station(index: index, of: count).deskRect
                XCTAssertFalse(previous.intersects(current),
                               "desks \(index - 1) and \(index) overlap at count \(count)")
            }
        }
    }
}
