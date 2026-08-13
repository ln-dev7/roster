import Foundation

/// Read-only presence helpers for **Cursor IDE** agent transcripts.
///
/// Layout (undocumented, verified live against Cursor 3.15):
/// `~/.cursor/projects/<slug>/agent-transcripts/<id>/<id>.jsonl`
/// where `<slug>` is the workspace path with `/` replaced by `-`.
///
/// Subagent transcripts live under `…/<id>/subagents/` and are ignored —
/// the parent conversation is the desk. Failures are silent: this is
/// enrichment only; hooks remain the source of truth for rich states.
enum CursorTranscripts {

    /// Reverse Cursor's project-folder slug into an absolute workspace
    /// path, but only when that path actually exists on disk.
    ///
    /// The encoding is lossy: a hyphen in the slug is either a path
    /// separator or a literal hyphen in a folder name (`my-project`), and
    /// nothing in the slug says which. So we walk the tree instead of
    /// substituting blindly, trying the shortest component first and
    /// backtracking when the branch leads nowhere. Existence on disk is
    /// the only arbiter; a slug that resolves to nothing yields nil.
    static func workspacePath(fromProjectSlug slug: String) -> String? {
        guard !slug.isEmpty else { return nil }
        var probes = 0
        return resolve(segments: slug.components(separatedBy: "-"),
                       from: 0,
                       under: "",
                       probes: &probes)
    }

    /// Directory probes allowed per slug. Backtracking is exponential in
    /// the worst case; real paths settle in a handful of probes, and a
    /// pathological slug is not worth a stalled scan.
    private static let probeBudget = 4_096

    private static func resolve(
        segments: [String],
        from index: Int,
        under prefix: String,
        probes: inout Int
    ) -> String? {
        let fm = FileManager.default
        for end in index..<segments.count {
            guard probes < probeBudget else { return nil }
            probes += 1

            let candidate = prefix + "/" + segments[index...end].joined(separator: "-")
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue
            else { continue }

            if end == segments.count - 1 { return candidate }
            if let resolved = resolve(segments: segments,
                                      from: end + 1,
                                      under: candidate,
                                      probes: &probes) {
                return resolved
            }
        }
        return nil
    }

    /// One warm parent transcript the room can seat.
    struct Hit: Equatable {
        let key: String
        let cwd: String
        let url: URL
        let modified: Date
    }

    /// Scan `projectsRoot` (normally `~/.cursor/projects`) for parent
    /// transcripts whose mtime is inside `aliveWindow`. Pure enough to
    /// unit-test against a temp tree; never throws.
    static func warmParentTranscripts(
        under projectsRoot: URL,
        aliveWindow: TimeInterval,
        now: Date = Date()
    ) -> [Hit] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot, includingPropertiesForKeys: nil
        ) else { return [] }

        var hits: [Hit] = []
        for projectDir in projectDirs {
            guard let cwd = workspacePath(fromProjectSlug: projectDir.lastPathComponent)
            else { continue }
            let transcriptsRoot = projectDir.appending(path: "agent-transcripts")
            guard let conversations = try? fm.contentsOfDirectory(
                at: transcriptsRoot, includingPropertiesForKeys: nil
            ) else { continue }

            for conversation in conversations {
                let id = conversation.lastPathComponent
                let transcript = conversation.appending(path: "\(id).jsonl")
                guard fm.fileExists(atPath: transcript.path),
                      let values = try? transcript.resourceValues(
                        forKeys: [.contentModificationDateKey]
                      ),
                      let modified = values.contentModificationDate,
                      now.timeIntervalSince(modified) < aliveWindow
                else { continue }
                hits.append(Hit(
                    key: "cursor:\(id)",
                    cwd: cwd,
                    url: transcript,
                    modified: modified
                ))
            }
        }
        return hits
    }
}
