import XCTest

/// Geometry sanity checks for the pixel office — cheap insurance that
/// layout edits never make two agents overlap or push a desk off-screen.
final class RoomPlanTests: XCTestCase {

    private let bounds = CGRect(origin: .zero, size: RoomPlan.size)

    func testPodsStayInsideTheSceneForEveryRoomSize() {
        for count in 1...Office.maxStations {
            for index in 0..<count {
                let carpet = RoomPlan.pod(index: index, of: count).carpet
                XCTAssertTrue(bounds.contains(carpet),
                              "pod \(index + 1)/\(count) leaves the scene")
            }
        }
    }

    func testNeighbouringPodsNeverOverlap() {
        for count in 2...Office.maxStations {
            for index in 1..<count {
                let previous = RoomPlan.pod(index: index - 1, of: count).carpet
                let current = RoomPlan.pod(index: index, of: count).carpet
                XCTAssertFalse(previous.intersects(current),
                               "pods \(index - 1) and \(index) overlap at count \(count)")
            }
        }
    }

    func testSeatSlotsSpreadWhenShared() {
        let pod = RoomPlan.pod(index: 0, of: 3)
        XCTAssertEqual(pod.seat(slot: 0, of: 1), pod.seat(slot: 1, of: 1),
                       "a lone agent always takes the chair")
        let left = pod.seat(slot: 0, of: 2)
        let right = pod.seat(slot: 1, of: 2)
        XCTAssertNotEqual(left, right)
        XCTAssertEqual((left.x + right.x) / 2, pod.seat(slot: 0, of: 1).x, accuracy: 0.001)
    }

    func testStandPointsOfSeatSlotsDoNotCollide() {
        let pod = RoomPlan.pod(index: 0, of: 3)
        XCTAssertNotEqual(pod.stand(slot: 0), pod.stand(slot: 1))
    }

    func testArrivalQueueSlotsAreDistinctAndOnYourRug() {
        let points = (0..<6).map { RoomPlan.arrival(deskSlot: $0) }
        XCTAssertEqual(Set(points.map(\.x)).count, points.count,
                       "every desk slot needs its own spot")
        for point in points {
            XCTAssertTrue(RoomPlan.youZone.insetBy(dx: -2, dy: -2).contains(point),
                          "arrival \(point) misses your rug")
        }
    }

    func testBottomZonesDoNotCollide() {
        let zones = [
            RoomPlan.youZone,
            RoomPlan.Furniture.loungeZone,
            RoomPlan.Furniture.pingPong,
        ]
        for (i, a) in zones.enumerated() {
            XCTAssertTrue(bounds.contains(a), "zone \(i) leaves the scene")
            for b in zones[(i + 1)...] {
                XCTAssertFalse(a.intersects(b), "bottom zones overlap")
            }
        }
    }

    func testPodsNeverReachTheBottomZones() {
        for count in 1...Office.maxStations {
            for index in 0..<count {
                let carpet = RoomPlan.pod(index: index, of: count).carpet
                XCTAssertLessThan(carpet.maxY, RoomPlan.youZone.minY,
                                  "pods must stay above the corridor")
            }
        }
    }

    func testTransformCentersAndFits() {
        let (scale, offset) = RoomPlan.transform(in: CGSize(width: 768, height: 440))
        XCTAssertEqual(scale, 2, accuracy: 0.001)
        XCTAssertEqual(offset.x, 0, accuracy: 0.001)
        XCTAssertEqual(offset.y, 0, accuracy: 0.001)

        let wide = RoomPlan.transform(in: CGSize(width: 1000, height: 440))
        XCTAssertEqual(wide.scale, 2, accuracy: 0.001)
        XCTAssertGreaterThan(wide.offset.x, 0)
    }
}
