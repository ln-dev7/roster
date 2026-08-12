import XCTest

/// Which app a desk opens in. Pure mapping — nothing here launches
/// anything; the NSWorkspace calls stay untested on purpose.
final class WorkspaceActionsTests: XCTestCase {

    func testCursorDesksOpenInCursorAndTerminalCLIsInVSCode() {
        XCTAssertEqual(ProviderKind.cursor.editor, .cursor)
        for kind in [ProviderKind.claudeCode, .gemini, .codex] {
            XCTAssertEqual(kind.editor, .vsCode, "\(kind) has no window of its own")
        }
    }

    /// The label is built from this name, so a typo here would ship a
    /// button that promises the wrong app.
    func testEditorsCarryTheirProductNameAndBundleID() {
        XCTAssertEqual(EditorApp.cursor.productName, "Cursor")
        XCTAssertEqual(EditorApp.cursor.bundleID, "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(EditorApp.vsCode.productName, "VS Code")
        XCTAssertEqual(EditorApp.vsCode.bundleID, "com.microsoft.VSCode")
    }
}
