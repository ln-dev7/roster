import AppKit

/// The three click actions, kept dumb on purpose.
///
/// "Open the terminal" deliberately opens a *new* Terminal window at the
/// project folder rather than hunting for the exact window the session
/// runs in — there is no reliable API for that (the session may even live
/// inside VS Code's integrated terminal), and a wrong guess is worse than
/// an honest new window.
enum WorkspaceActions {

    private static let vsCodeBundleID = "com.microsoft.VSCode"
    private static let terminalBundleID = "com.apple.Terminal"

    /// Opens the repository in VS Code; falls back to revealing the folder
    /// in Finder when VS Code isn't installed.
    static func openInVSCode(path: String) {
        open(path: path, withBundleID: vsCodeBundleID)
    }

    /// Opens a new Terminal window at the repository folder.
    static func openTerminal(path: String) {
        open(path: path, withBundleID: terminalBundleID)
    }

    /// The shop page where people can support Roster's development —
    /// linked from the sidebar and Settings.
    static let supportURL = URL(string: "https://lndev.mychariow.shop/prd_3cu1s0")!

    static func openSupport() {
        NSWorkspace.shared.open(supportURL)
    }

    private static func open(path: String, withBundleID bundleID: String) {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open([folder], withApplicationAt: app,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            // No such app: at least put the folder in front of the user.
            NSWorkspace.shared.open(folder)
        }
    }
}
