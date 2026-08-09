import Foundation
import Observation
import os

/// The live data source: hook install state, the spool tail, and the
/// transcript scan. Everything fragile about depending on Claude Code's
/// internals is kept behind this type — the office only ever sees
/// `ClaudeEvent`s.
///
/// Two feeds cooperate:
///
///   • **The spool** (hooks) is the source of truth for rich states —
///     waiting, finished, failed.
///   • **The transcript scan** runs at launch and then every 30 seconds
///     as a safety net: it catches sessions the hooks missed (started
///     before the install, hook removed, anything), and it retires
///     sessions whose transcript has gone quiet without a SessionEnd.
///     Presence never depends on the hook alone.
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
    /// Spool lines accepted so far — visible in logs, handy when debugging.
    private(set) var eventsProcessed = 0

    private let office: Office
    @ObservationIgnored private var watcher: SpoolWatcher?
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    /// session key → transcript file, for the staleness sweep.
    @ObservationIgnored private var transcripts: [String: URL] = [:]
    /// How many desks were last persisted — save only when it changes.
    @ObservationIgnored private var savedStationCount = 0

    private let log = Logger(subsystem: "com.lndev.roster", category: "source")

    /// A transcript untouched for this long counts as "probably running".
    @ObservationIgnored private let aliveWindow: TimeInterval = 300
    /// A tracked session whose transcript is older than this is retired.
    @ObservationIgnored private let staleAfter: TimeInterval = 20 * 60

    /// Where the hook writes and Roster reads.
    static var spoolURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Roster/events.jsonl")
    }

    private static var projectsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/projects")
    }

    init(office: Office) {
        self.office = office
    }

    deinit {
        rescanTask?.cancel()
    }

    /// Called once at launch.
    ///
    /// The feeds start in EVERY case: the transcript scan is read-only and
    /// harmless, so real sessions appear in the room automatically, hook
    /// or not. What consent gates is only the *write* — installing the
    /// hook into ~/.claude/settings.json, which unlocks the rich states
    /// (waiting for input, finished, failed) and the walk.
    func refresh() {
        if HookInstaller.isInstalled() {
            log.info("hook already installed")
            state = .connected
        } else {
            log.info("hook not installed; presence-only until consent")
            state = .notConnected
        }
        startFeeds()
    }

    /// The consent button. Installs (or upgrades) the hook set — with a
    /// backup. The feeds are already running; from here the spool starts
    /// filling. Errors land in `state` for the banner to display.
    func connect() {
        do {
            try HookInstaller.install()
            log.info("hook installed")
            state = .connected
        } catch {
            log.error("hook install failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Feeds

    private func startFeeds() {
        // Desks remembered from previous launches come back first (empty),
        // so the room opens familiar instead of blank.
        for workstation in WorkstationStore.load() {
            office.restoreWorkstation(workstation)
        }
        savedStationCount = office.workstations.count

        if watcher == nil {
            let watcher = SpoolWatcher(url: Self.spoolURL) { [weak self] line in
                self?.handle(line: line)
            }
            watcher.start()
            self.watcher = watcher
        }

        scanTranscripts()

        if rescanTask == nil {
            // The safety net: every 30 s, look at the transcripts. Cheap
            // (a directory listing and a few stats) and it makes presence
            // independent from the hook being there first.
            rescanTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    self?.scanTranscripts()
                }
            }
        }
    }

    private func handle(line: String) {
        if let (key, path) = ClaudeEvent.transcriptPath(fromJSONLine: line) {
            transcripts[key] = URL(fileURLWithPath: path)
        }
        guard let event = ClaudeEvent(jsonLine: line) else {
            log.debug("spool line ignored")
            return
        }
        eventsProcessed += 1
        log.info("event #\(self.eventsProcessed): \(String(describing: event), privacy: .public)")
        office.apply(event)
        persistWorkstationsIfNeeded()
    }

    /// Remembers real desks (the ones with a repository path) whenever a
    /// new one appears.
    private func persistWorkstationsIfNeeded() {
        guard office.workstations.count != savedStationCount else { return }
        savedStationCount = office.workstations.count
        WorkstationStore.save(office.workstations.filter { $0.path != nil })
    }

    // MARK: - Transcript scan
    //
    // This reads an UNDOCUMENTED layout — transcripts named
    // <session-id>.jsonl in per-project folders, each line carrying a
    // "cwd" field. It can break with any Claude Code release, which is
    // why it only ever adds a working session or retires a quiet one,
    // and why failures are silent. The hooks remain the source of truth
    // for everything richer.

    private func scanTranscripts() {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: Self.projectsURL, includingPropertiesForKeys: nil
        ) else {
            log.debug("no ~/.claude/projects to scan")
            return
        }

        var found = 0
        for dir in projectDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for transcript in files where transcript.pathExtension == "jsonl" {
                guard let modified = modificationDate(of: transcript) else { continue }
                let key = transcript.deletingPathExtension().lastPathComponent

                if Date().timeIntervalSince(modified) < aliveWindow {
                    transcripts[key] = transcript
                    guard let cwd = Self.cwd(fromTranscript: transcript) else { continue }
                    // Idempotent: a session already in the room is a no-op.
                    office.apply(.sessionStart(key: key, cwd: cwd))
                    found += 1
                }
            }
        }
        if found > 0 {
            log.info("transcript scan: \(found) live session(s)")
        }
        persistWorkstationsIfNeeded()

        // Retire tracked sessions whose transcript has gone quiet — they
        // ended while nobody was listening (or before the hook existed).
        for (key, url) in transcripts {
            guard let modified = modificationDate(of: url) else { continue }
            if Date().timeIntervalSince(modified) > staleAfter {
                log.info("session \(key, privacy: .public) stale; retiring")
                office.apply(.sessionEnd(key: key))
                transcripts[key] = nil
            }
        }
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
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
