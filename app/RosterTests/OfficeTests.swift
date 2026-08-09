import XCTest

/// Tests for the room's state machine.
///
/// The `Office` sources are compiled straight into this bundle (see
/// project.yml), so there is no app to launch and nothing to import. The
/// injected sleeper makes every choreography instantaneous — and lets a test
/// observe the phase at each step of the walk.
@MainActor
final class OfficeTests: XCTestCase {

    /// A demo office whose clock never sleeps: choreographies run instantly.
    private func makeInstantOffice() -> Office {
        let office = Office(sleeper: { _ in })
        office.seedDemo()
        return office
    }

    // MARK: Seating

    func testSeedDemoSeatsOneWorkingAgentPerStation() {
        let office = makeInstantOffice()
        XCTAssertEqual(office.workstations.count, 3)
        XCTAssertEqual(office.sessions.count, 3)
        for (index, session) in office.sessions.enumerated() {
            XCTAssertEqual(session.stationIndex, index)
            XCTAssertEqual(session.status, .working)
            XCTAssertEqual(session.phase, .seated)
        }
    }

    func testTwoAgentsShareAStationThenItIsFull() {
        let office = makeInstantOffice()
        let second = office.startSession(onStation: 0)
        XCTAssertNotNil(second)

        // Both occupants hold different seat slots.
        let slots = office.sessions
            .filter { $0.stationIndex == 0 }
            .map(\.seatSlot)
            .sorted()
        XCTAssertEqual(slots, [0, 1])

        // A third agent is refused: the drawing would lie.
        XCTAssertFalse(office.canAddSession(onStation: 0))
        XCTAssertNil(office.startSession(onStation: 0))
    }

    func testEndingASessionFreesItsSeat() {
        let office = makeInstantOffice()
        let second = office.startSession(onStation: 0)!
        office.endSession(second)
        XCTAssertTrue(office.canAddSession(onStation: 0))
        XCTAssertEqual(office.seatCount(onStation: 0), 1)
        XCTAssertEqual(office.workstations.count, 3,
                       "the desk stays while a colleague still works there")
    }

    func testEndingTheLastSessionRemovesTheDesk() {
        let office = makeInstantOffice()
        // Demo room: one agent per desk. Ending the middle one must take
        // its desk along — and re-point the sessions past it, since desk
        // indices stay dense.
        office.endSession(office.sessions[1].id)

        XCTAssertEqual(office.workstations.count, 2)
        XCTAssertEqual(office.sessions.count, 2)
        XCTAssertEqual(office.sessions.map(\.stationIndex), [0, 1],
                       "sessions after the removed desk shift down")
    }

    // MARK: Waiting for input

    func testNeedsInputStandsUpAndAnswerSitsBackDown() {
        let office = makeInstantOffice()
        let id = office.sessions[0].id

        office.needsInput(id)
        XCTAssertEqual(office.session(id)?.status, .waitingForInput)
        XCTAssertEqual(office.session(id)?.phase, .standing)
        // A waiting agent is not "working": its monitor goes quiet.
        XCTAssertFalse(office.hasWorkingAgent(onStation: 0))

        office.resumeWorking(id)
        XCTAssertEqual(office.session(id)?.status, .working)
        XCTAssertEqual(office.session(id)?.phase, .seated)
        XCTAssertTrue(office.hasWorkingAgent(onStation: 0))
    }

    // MARK: The walk

    func testFinishWalksToTheDeskAndStaysThere() async {
        let office = makeInstantOffice()
        let id = office.sessions[0].id

        await office.finish(id)?.value

        XCTAssertEqual(office.session(id)?.status, .finished)
        XCTAssertEqual(office.session(id)?.phase, .atDesk)
    }

    func testFinishPlaysPhasesInOrder() async {
        // A logging sleeper: records the agent's phase at every pause, i.e.
        // right after each step of the choreography was applied.
        var observedPhases: [AgentPhase] = []
        var office: Office!
        office = Office(sleeper: { _ in
            if let phase = office.sessions.first?.phase {
                observedPhases.append(phase)
            }
        })
        office.seedDemo()
        let id = office.sessions[0].id

        await office.finish(id)?.value

        XCTAssertEqual(observedPhases, [.standing, .walking])
        XCTAssertEqual(office.session(id)?.phase, .atDesk)
    }

    func testReviewedAgentWalksBackAndWorksAgain() async {
        let office = makeInstantOffice()
        let id = office.sessions[0].id
        await office.finish(id)?.value

        await office.resumeWorking(id)?.value

        XCTAssertEqual(office.session(id)?.status, .working)
        XCTAssertEqual(office.session(id)?.phase, .seated)
    }

    func testTwoFinishedAgentsQueueAtDifferentDeskSlots() async {
        let office = makeInstantOffice()
        let first = office.sessions[0].id
        let second = office.sessions[1].id

        await office.finish(first)?.value
        await office.finish(second)?.value

        let slots = [office.session(first)!.deskSlot, office.session(second)!.deskSlot]
        XCTAssertEqual(Set(slots).count, 2, "queued agents must not overlap")
    }

    // MARK: Arrival callback

    func testArrivalCallbackFiresExactlyOnceAtTheDesk() async {
        let office = makeInstantOffice()
        var arrivals: [Int] = []
        office.onAgentArrived = { arrivals.append($0.id) }
        let id = office.sessions[0].id

        await office.finish(id)?.value
        XCTAssertEqual(arrivals, [id])

        // The return leg must not fire it again.
        await office.resumeWorking(id)?.value
        XCTAssertEqual(arrivals, [id])
    }

    // MARK: Failure & interruption

    func testFailurePullsTheAgentBackToItsStation() async {
        let office = makeInstantOffice()
        let id = office.sessions[0].id
        await office.finish(id)?.value

        office.fail(id)

        XCTAssertEqual(office.session(id)?.status, .failed)
        XCTAssertEqual(office.session(id)?.phase, .standing)
    }

    func testEventDuringTheWalkCancelsTheChoreography() async {
        // The sleeper injects a failure right in the middle of the walk —
        // the stale choreography must NOT overwrite the failure afterwards.
        var office: Office!
        var interrupted = false
        office = Office(sleeper: { _ in
            if !interrupted, office.sessions.first?.phase == .walking {
                interrupted = true
                office.fail(office.sessions[0].id)
            }
        })
        office.seedDemo()
        let id = office.sessions[0].id

        await office.finish(id)?.value

        XCTAssertEqual(office.session(id)?.status, .failed)
        XCTAssertEqual(office.session(id)?.phase, .standing,
                       "the dead walk must not push the agent to the desk")
    }
}
