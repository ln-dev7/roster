import XCTest

/// Round-trip of the remembered desks.
final class WorkstationStoreTests: XCTestCase {

    func testRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "roster-tests-\(UUID().uuidString)/workstations.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let desks = [
            Workstation(id: "/repo/circle", name: "circle", path: "/repo/circle"),
            Workstation(id: "/repo/blog", name: "blog", path: "/repo/blog"),
        ]
        WorkstationStore.save(desks, to: url)

        XCTAssertEqual(WorkstationStore.load(from: url), desks)
    }

    func testMissingOrCorruptFileLoadsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "roster-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let missing = dir.appending(path: "nope.json")
        XCTAssertEqual(WorkstationStore.load(from: missing), [])

        let corrupt = dir.appending(path: "bad.json")
        try Data("not json".utf8).write(to: corrupt)
        XCTAssertEqual(WorkstationStore.load(from: corrupt), [])
    }
}
