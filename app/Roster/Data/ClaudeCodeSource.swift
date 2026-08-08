import Foundation
import Observation

/// The live data source: hook install state, the spool tail, and the
/// bootstrap scan. Everything fragile about depending on Claude Code's
/// internals is kept behind this type — the office only ever sees
/// `ClaudeEvent`s.
@MainActor
@Observable
final class ClaudeCodeSource {

    enum ConnectionState: Equatable {
        /// Not looked yet (first millisecond of app life).
        case checking
        /// Hook not installed — the room runs on demo data.
        case notConnected
        /// Hook installed, spool being tailed.
        case connected
        /// Install failed; the message is shown to the user.
        case failed(String)
    }

    private(set) var state: ConnectionState = .checking

    private let office: Office
    @ObservationIgnored private var watcher: SpoolWatcher?

    /// Where the hook writes and Roster reads.
    static var spoolURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Roster/events.jsonl")
    }

    init(office: Office) {
        self.office = office
    }

    /// Called once at launch: adopt the existing install if there is one.
    func refresh() {
        if HookInstaller.isInstalled() {
            state = .connected
            startWatching()
            bootstrapScan()
        } else {
            state = .notConnected
        }
    }

    /// The consent button. Installs the hook (with backup), then starts
    /// listening. Errors land in `state` for the banner to display.
    func connect() {
        do {
            try HookInstaller.install()
            state = .connected
            startWatching()
            bootstrapScan()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let watcher = SpoolWatcher(url: Self.spoolURL) { [weak self] line in
            guard let self, let event = ClaudeEvent(jsonLine: line) else { return }
            self.office.apply(event)
        }
        watcher.start()
        self.watcher = watcher
    }

    // MARK: - Bootstrap scan
    //
    // The spool only knows about events fired since the hook existed. For
    // sessions already running before that (or transcripts still warm), we
    // peek at ~/.claude/projects: any transcript modified in the last few
    // minutes is presumed to be a live, working session.
    //
    // This reads an UNDOCUMENTED layout — transcripts named
    // <session-id>.jsonl in per-project folders, each line carrying a
    // "cwd" field. It can break with any Claude Code release, which is
    // why it only ever *adds* a working session and nothing else, and why
    // failures are silent. The hooks remain the source of truth.

    private static var projectsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/projects")
    }

    /// Transcripts younger than this count as "probably still running".
    private let bootstrapWindow: TimeInterval = 300

    private func bootstrapScan() {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: Self.projectsURL, includingPropertiesForKeys: nil
        ) else { return }

        for dir in projectDirs {
            guard let transcripts = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for transcript in transcripts where transcript.pathExtension == "jsonl" {
                guard
                    let modified = (try? transcript.resourceValues(
                        forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                    Date().timeIntervalSince(modified) < bootstrapWindow,
                    let cwd = Self.cwd(fromTranscript: transcript)
                else { continue }

                // The filename is the session id — the same key the hooks
                // will use, so live events attach to this same session.
                let key = transcript.deletingPathExtension().lastPathComponent
                office.apply(.sessionStart(key: key, cwd: cwd))
            }
        }
    }

    /// Reads the last few KB of a transcript and returns the most recent
    /// "cwd" value found, or nil. Deliberately tolerant: any surprise in
    /// the format simply yields nil.
    private static func cwd(fromTranscript url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 8192
        let start = size > window ? size - window : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        struct Line: Decodable { let cwd: String? }
        for line in text.split(separator: "\n").reversed() {
            if let parsed = try? JSONDecoder().decode(Line.self, from: Data(line.utf8)),
               let cwd = parsed.cwd {
                return cwd
            }
        }
        return nil
    }
}
