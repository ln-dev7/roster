import Foundation

/// Where Claude Code lives — possibly in several places.
///
/// People running multiple accounts use shell aliases that point
/// `CLAUDE_CONFIG_DIR` at separate folders (`~/.claude-pro`,
/// `~/.claude-perso`, …). Each of those is a full config root with its
/// own `settings.json` and its own `projects/` transcripts, so Roster
/// must hook and scan *all* of them.
///
/// Discovery: every `~/.claude*` directory that looks like a config root,
/// plus any folder the user added by hand in Settings.
enum ClaudeConfigRoots {

    private static let extrasKey = "extraClaudeConfigRoots"

    /// User-added roots (paths), managed from Settings.
    static var extras: [String] {
        UserDefaults.standard.stringArray(forKey: extrasKey) ?? []
    }

    static func addExtra(_ path: String) {
        var list = extras
        guard !list.contains(path) else { return }
        list.append(path)
        UserDefaults.standard.set(list, forKey: extrasKey)
    }

    static func removeExtra(_ path: String) {
        UserDefaults.standard.set(extras.filter { $0 != path },
                                  forKey: extrasKey)
    }

    /// All config roots, deduplicated and sorted. Parameterized for tests.
    static func discover(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        extraPaths: [String]? = nil
    ) -> [URL] {
        let fm = FileManager.default
        var found: [String: URL] = [:]

        // ~/.claude* directories that actually look like config roots.
        if let children = try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for child in children where child.lastPathComponent.hasPrefix(".claude") {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory == true else { continue }
                guard looksLikeConfigRoot(child) else { continue }
                found[child.path] = child
            }
        }

        // Folders the user added by hand (aliases can point anywhere).
        for path in extraPaths ?? extras {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                found[url.path] = url
            }
        }

        return found.values.sorted { $0.path < $1.path }
    }

    /// A config root carries transcripts and/or a settings file. This
    /// filters out unrelated `.claude*`-prefixed folders from other tools.
    private static func looksLikeConfigRoot(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appending(path: "projects").path)
            || fm.fileExists(atPath: url.appending(path: "settings.json").path)
    }
}
