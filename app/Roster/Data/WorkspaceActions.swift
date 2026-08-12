import AppKit

/// The three click actions, kept dumb on purpose.
///
/// "Open the terminal" deliberately opens a *new* Terminal window at the
/// project folder rather than hunting for the exact window the session
/// runs in — there is no reliable API for that (the session may even live
/// inside VS Code's integrated terminal), and a wrong guess is worse than
/// an honest new window.
enum WorkspaceActions {

    private static let terminalBundleID = "com.apple.Terminal"

    /// Opens the repository in the session's own editor; falls back to
    /// revealing the folder in Finder when that app isn't installed.
    static func openInEditor(_ editor: EditorApp, path: String) {
        open(path: path, withBundleID: editor.bundleID)
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

/// The desktop app a session belongs to — what the detail card's first
/// action opens, and what its label says.
///
/// Both editors raise the window that already has the folder open instead
/// of making a second one, so handing them the project folder is enough to
/// land the user back in the exact window their agent works in.
enum EditorApp: Equatable {
    case vsCode
    case cursor

    /// Shown in the button title. A product name — never localized.
    var productName: String {
        switch self {
        case .vsCode: return "VS Code"
        case .cursor: return "Cursor"
        }
    }

    var bundleID: String {
        switch self {
        case .vsCode: return "com.microsoft.VSCode"
        // Cursor ships through ToDesktop, hence the opaque identifier.
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        }
    }
}

extension ProviderKind {

    /// The app to open a desk of this tool in. Cursor sessions live in
    /// Cursor's own window; the terminal CLIs have no window of their own,
    /// so they keep VS Code — the V0 default, and the editor their
    /// integrated-terminal sessions most likely run in.
    var editor: EditorApp {
        switch self {
        case .cursor: return .cursor
        case .claudeCode, .gemini, .codex: return .vsCode
        }
    }
}
