import Foundation
import Observation
import os
import SwiftUI

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

    /// See AgentProvider.swift — the states are shared by every provider.
    private(set) var state: ConnectionState = .checking
    /// Spool lines accepted so far — visible in logs, handy when debugging.
    private(set) var eventsProcessed = 0
    /// All Claude config roots currently known (~/.claude, ~/.claude-pro,
    /// user-added folders…). Settings displays and manages this list.
    private(set) var roots: [URL] = []

    /// One row per OTHER detected tool (Gemini CLI, Cursor, Codex) —
    /// detected means its config folder exists. Settings lists them;
    /// Connect wires them all.
    struct ProviderStatus: Identifiable, Equatable {
        let kind: ProviderKind
        let configPath: String
        let installed: Bool
        var id: String { kind.rawValue }
    }

    private(set) var providerStatuses: [ProviderStatus] = []

    private let office: Office
    @ObservationIgnored private var watcher: SpoolWatcher?
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    /// session key → transcript file, for the staleness sweep.
    @ObservationIgnored private var transcripts: [String: URL] = [:]
    /// session key → last spool event, for sessions WITHOUT a transcript
    /// on disk yet (Codex mid-turn before a rollout lands, Cursor IDE
    /// before the parent transcript appears): quietness is the retirement
    /// signal until a scan enrolls them in `transcripts`.
    @ObservationIgnored private var lastEventAt: [String: Date] = [:]
    /// Sessions that ENDED, with when. The transcript file outlives the
    /// session, and its mtime stays "fresh" for a few minutes — without
    /// this tombstone the 30-second rescan would resurrect a session the
    /// user just quit. A transcript modified AFTER its tombstone means
    /// the session was resumed, and the tombstone is lifted.
    @ObservationIgnored private var endedAt: [String: Date] = [:]

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

    init(office: Office) {
        self.office = office
    }

    deinit {
        rescanTask?.cancel()
    }

    /// True when every known root carries the current hook set.
    var allRootsInstalled: Bool {
        !roots.isEmpty && roots.allSatisfy {
            HookInstaller.isInstalled(at: $0.appending(path: "settings.json"))
        }
    }

    /// The other tools, looked up fresh from disk.
    private func detectProviders() -> [ProviderStatus] {
        var statuses: [ProviderStatus] = []
        if GeminiInstaller.toolDetected {
            statuses.append(ProviderStatus(
                kind: .gemini,
                configPath: GeminiInstaller.defaultSettingsURL.path,
                installed: GeminiInstaller.isInstalled()
            ))
        }
        if CursorInstaller.toolDetected {
            statuses.append(ProviderStatus(
                kind: .cursor,
                configPath: CursorInstaller.defaultHooksURL.path,
                installed: CursorInstaller.isInstalled()
            ))
        }
        if CodexInstaller.toolDetected {
            statuses.append(ProviderStatus(
                kind: .codex,
                configPath: CodexInstaller.defaultConfigURL.path,
                installed: CodexInstaller.isInstalled()
            ))
        }
        return statuses
    }

    /// Called at launch and whenever the root list may have changed
    /// (Settings adds a folder, an alias creates a new config dir…).
    ///
    /// The feeds start in EVERY case: the transcript scan is read-only and
    /// harmless, so real sessions appear in the room automatically, hook
    /// or not. What consent gates is only the *write* — installing the
    /// hooks into each root's settings.json, which unlocks the rich
    /// states (waiting for input, finished, failed) and the walk.
    func refresh() {
        roots = ClaudeConfigRoots.discover()
        providerStatuses = detectProviders()
        let providersWired = providerStatuses.allSatisfy(\.installed)
        if allRootsInstalled && providersWired {
            log.info("hooks installed in all \(self.roots.count) root(s) and \(self.providerStatuses.count) provider(s)")
            state = .connected
        } else {
            log.info("wiring missing somewhere; presence-only until consent")
            state = .notConnected
        }
        startFeeds()
    }

    /// The consent button. Installs (or upgrades) the wiring EVERYWHERE —
    /// every Claude Code root, plus every other detected tool — each
    /// config with its own backup. The feeds are already running; from
    /// here the spool starts filling. The first error lands in `state`
    /// for the banner to display.
    func connect() {
        // Ask for notification permission HERE, not at launch: arrivals —
        // the only thing Roster notifies about — require the finished
        // state, which only exists once the hooks are in. Asking at the
        // moment of consent also keeps first launch down to one dialog.
        Notifier.requestPermissionIfNeeded()

        roots = ClaudeConfigRoots.discover()
        var firstError: Error?
        for root in roots {
            do {
                try HookInstaller.install(at: root.appending(path: "settings.json"))
                log.info("hooks installed in \(root.path, privacy: .public)")
            } catch {
                log.error("hook install failed in \(root.path, privacy: .public): \(error.localizedDescription)")
                firstError = firstError ?? error
            }
        }

        // The other tools, one installer each — only where detected.
        let installs: [(detected: Bool, name: String, install: () throws -> Void)] = [
            (GeminiInstaller.toolDetected, "gemini", { try GeminiInstaller.install() }),
            (CursorInstaller.toolDetected, "cursor", { try CursorInstaller.install() }),
            (CodexInstaller.toolDetected, "codex", { try CodexInstaller.install() }),
        ]
        for item in installs where item.detected {
            do {
                try item.install()
                log.info("wired \(item.name, privacy: .public)")
            } catch {
                log.error("\(item.name, privacy: .public) install failed: \(error.localizedDescription)")
                firstError = firstError ?? error
            }
        }

        providerStatuses = detectProviders()
        if let firstError {
            state = .failed(firstError.localizedDescription)
        } else {
            state = .connected
        }
    }

    // MARK: - Feeds

    private func startFeeds() {
        if watcher == nil {
            let watcher = SpoolWatcher(url: Self.spoolURL) { [weak self] line, isReplay in
                self?.handle(line: line, isReplay: isReplay)
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

    private func handle(line: String, isReplay: Bool) {
        let transcriptRef = ClaudeEvent.transcriptPath(fromJSONLine: line)
        if let (key, path) = transcriptRef {
            transcripts[key] = URL(fileURLWithPath: path)
        }

        // Replayed history of a session whose transcript is GONE (Claude
        // Code cleans them up after ~30 days) or long quiet is exactly
        // that — history. Sessions that died without their SessionEnd
        // (killed terminal, crash) would otherwise haunt the room as
        // ghost desks at every launch, forever if the transcript file no
        // longer exists. Live lines are never dropped: a hook that just
        // fired belongs to a session that is provably alive.
        if isReplay, let (key, path) = transcriptRef {
            let modified = modificationDate(of: URL(fileURLWithPath: path))
            let longQuiet = modified.map {
                Date().timeIntervalSince($0) > staleAfter
            } ?? true // no file at all = the oldest kind of quiet
            if longQuiet {
                transcripts[key] = nil
                return
            }
        }

        guard let event = ClaudeEvent(jsonLine: line) else {
            log.debug("spool line ignored")
            return
        }
        eventsProcessed += 1
        log.info("event #\(self.eventsProcessed): \(String(describing: event), privacy: .public)")

        switch event {
        case .sessionEnd(let key):
            // Tombstone first, so the rescan can't resurrect it.
            endedAt[key] = Date()
            lastEventAt[key] = nil
        case .sessionStart(let key, _), .promptSubmitted(let key, _),
             .needsInput(let key, _), .completed(let key, _),
             .stopped(let key, _, _), .stopFailed(let key, _):
            // Any sign of life lifts a tombstone (resumed session).
            endedAt[key] = nil
            lastEventAt[key] = Date()
        }

        // A SessionStart whose transcript ALREADY exists on disk is a
        // real conversation opening (a resume, a warm start) — seat it
        // the moment the session launches, which is what the desk should
        // feel like. Claude Code 2.x's pre-created slots carry a
        // transcript path that does not exist yet (verified live: five
        // slots without a file, the one real session with it) — those
        // stay pending in the Office until their first sign of work.
        // Replayed starts additionally need a live process: the fast
        // path must not resurrect a session that quit while we were off.
        if case .sessionStart(let key, let cwd) = event,
           let (_, path) = transcriptRef,
           FileManager.default.fileExists(atPath: path),
           !isReplay || ProcessLiveness.snapshot()
               .contains(ProviderKind(sessionKey: key), at: cwd) {
            _ = withAnimation(.easeOut(duration: 0.45)) {
                office.seatActiveSession(key: key, cwd: cwd)
            }
            return
        }

        // withAnimation so session arrivals/departures fade like the demo
        // ones (RoomView's insertion/removal transitions).
        _ = withAnimation(.easeOut(duration: 0.45)) {
            office.apply(event)
        }
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
        // Aliases can create a new config root at any time.
        roots = ClaudeConfigRoots.discover()
        // One pass over the process table for this whole scan: presence
        // stops being "the transcript is warm" and becomes "a matching
        // CLI process is actually sitting in that folder".
        let liveness = ProcessLiveness.snapshot()

        var found = 0
        for root in roots {
            let projects = root.appending(path: "projects")
            guard let projectDirs = try? fm.contentsOfDirectory(
                at: projects, includingPropertiesForKeys: nil
            ) else { continue }

            for dir in projectDirs {
                guard let files = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
                ) else { continue }

                for transcript in files where transcript.pathExtension == "jsonl" {
                    guard let modified = modificationDate(of: transcript) else { continue }
                    let key = transcript.deletingPathExtension().lastPathComponent

                    // Ended sessions stay dead — unless the transcript
                    // moved on since (resume), which lifts the tombstone.
                    if let ended = endedAt[key] {
                        if modified > ended.addingTimeInterval(2) {
                            endedAt[key] = nil
                        } else {
                            continue
                        }
                    }

                    if Date().timeIntervalSince(modified) < aliveWindow {
                        transcripts[key] = transcript
                        guard let cwd = Self.cwd(fromTranscript: transcript),
                              // A warm transcript alone is hearsay — a
                              // claude process in that folder is proof.
                              liveness.contains(.claudeCode, at: cwd)
                        else { continue }
                        // Idempotent: a session already in the room is a no-op.
                        // seatActiveSession, not a SessionStart event: a
                        // transcript being written is proof of real work.
                        _ = withAnimation(.easeOut(duration: 0.45)) {
                            office.seatActiveSession(key: key, cwd: cwd)
                        }
                        found += 1
                    }
                }
            }
        }
        found += scanCodexRollouts(liveness: liveness)
        found += scanCursorTranscripts()

        if found > 0 {
            log.info("transcript scan: \(found) live session(s) across \(self.roots.count) root(s)")
        }

        // Liveness sweep: a desk whose folder hosts no matching CLI
        // process is a leftover — the tool quit without its SessionEnd
        // (killed terminal, Claude 2.x background churn). ~30 s to leave
        // instead of the 20-minute quiet rule. Cursor is exempt (its
        // hooks come from the IDE, whose processes live elsewhere), and
        // an EMPTY snapshot means the process table was unreadable —
        // never a proof of death, so everybody stays.
        if !liveness.entries.isEmpty {
            for (key, id) in Array(office.externalToID) {
                let provider = ProviderKind(sessionKey: key)
                guard provider != .cursor,
                      let session = office.session(id),
                      office.workstations.indices.contains(session.stationIndex),
                      let path = office.workstations[session.stationIndex].path,
                      !liveness.contains(provider, at: path)
                else { continue }
                log.info("session \(key, privacy: .public) has no live process; retiring")
                endedAt[key] = Date()
                _ = withAnimation(.easeOut(duration: 0.45)) {
                    office.apply(.sessionEnd(key: key))
                }
                transcripts[key] = nil
                lastEventAt[key] = nil
            }
        }

        // Retire tracked sessions whose transcript has gone quiet — they
        // ended while nobody was listening (or before the hook existed).
        // A transcript that VANISHED counts as ancient (Claude Code
        // cleaned it up), with one guard: a brand-new session can fire
        // its first hooks before the file lands on disk, so fresh events
        // keep it alive.
        for (key, url) in transcripts {
            let modified = modificationDate(of: url)
            if modified == nil,
               let last = lastEventAt[key],
               Date().timeIntervalSince(last) < staleAfter {
                continue
            }
            if Date().timeIntervalSince(modified ?? .distantPast) > staleAfter {
                log.info("session \(key, privacy: .public) stale; retiring")
                endedAt[key] = Date()
                _ = withAnimation(.easeOut(duration: 0.45)) {
                    office.apply(.sessionEnd(key: key))
                }
                transcripts[key] = nil
                lastEventAt[key] = nil
            }
        }

        // Transcript-less sessions (Codex without a rollout yet, or a
        // Cursor IDE chat that never wrote a parent transcript) retire
        // on event quietness alone — those tools may never say goodbye.
        for (key, at) in lastEventAt where transcripts[key] == nil {
            if Date().timeIntervalSince(at) > staleAfter {
                log.info("session \(key, privacy: .public) quiet; retiring")
                endedAt[key] = Date()
                _ = withAnimation(.easeOut(duration: 0.45)) {
                    office.apply(.sessionEnd(key: key))
                }
                lastEventAt[key] = nil
            }
        }

        // Tombstones older than the alive window can go: a transcript that
        // old wouldn't count as live anyway.
        for (key, date) in endedAt where Date().timeIntervalSince(date) > aliveWindow {
            endedAt[key] = nil
        }
    }

    /// Codex presence. The CLI's notify only speaks at end-of-turn, so a
    /// running Codex agent would stay invisible until its first turn
    /// completed. But Codex also writes a rollout transcript per session
    /// (~/.codex/sessions/YYYY/MM/DD/rollout-….jsonl) whose FIRST line —
    /// `session_meta` — carries the session id and cwd. Same contract as
    /// the Claude scan: undocumented layout, so this only ever adds a
    /// working session (the mtime sweep retires quiet ones), and any
    /// format surprise silently yields nothing. The id matches notify's
    /// thread-id, so the desk this creates is the SAME session the
    /// end-of-turn events later enrich.
    private func scanCodexRollouts(liveness: ProcessLiveness.Snapshot) -> Int {
        guard CodexInstaller.toolDetected else { return 0 }
        let fm = FileManager.default
        let sessionsDir = fm.homeDirectoryForCurrentUser
            .appending(path: ".codex/sessions")
        // Date-nested dirs, a few stats per file — cheap at 30 s cadence.
        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }

        var found = 0
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let modified = modificationDate(of: url),
                  Date().timeIntervalSince(modified) < aliveWindow,
                  let meta = Self.codexMeta(fromRollout: url),
                  // Same rule as Claude: a warm rollout only counts with
                  // a codex process actually sitting in that folder.
                  liveness.contains(.codex, at: meta.cwd)
            else { continue }
            let key = "codex:\(meta.id)"

            // Same tombstone rule as Claude transcripts: ended stays
            // ended unless the rollout moved on since (resume).
            if let ended = endedAt[key] {
                if modified > ended.addingTimeInterval(2) {
                    endedAt[key] = nil
                } else {
                    continue
                }
            }

            // Registering into `transcripts` enrolls the rollout in the
            // existing staleness sweep — retirement comes for free.
            transcripts[key] = url
            _ = withAnimation(.easeOut(duration: 0.45)) {
                office.seatActiveSession(key: key, cwd: meta.cwd)
            }
            found += 1
        }
        return found
    }

    /// Cursor IDE presence. Agent Chat leaves parent transcripts under
    /// `~/.cursor/projects/<slug>/agent-transcripts/<id>/<id>.jsonl`.
    /// Undocumented layout → enrichment only, silent on surprise. No
    /// process check: the IDE's processes do not live in the workspace
    /// cwd (same reason Cursor is exempt from the liveness sweep).
    private func scanCursorTranscripts() -> Int {
        guard CursorInstaller.toolDetected else { return 0 }
        let projectsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cursor/projects")
        let hits = CursorTranscripts.warmParentTranscripts(
            under: projectsRoot, aliveWindow: aliveWindow
        )
        var found = 0
        for hit in hits {
            if let ended = endedAt[hit.key] {
                if hit.modified > ended.addingTimeInterval(2) {
                    endedAt[hit.key] = nil
                } else {
                    continue
                }
            }
            transcripts[hit.key] = hit.url
            _ = withAnimation(.easeOut(duration: 0.45)) {
                office.seatActiveSession(key: hit.key, cwd: hit.cwd)
            }
            found += 1
        }
        return found
    }

    /// First line of a rollout → (session id, cwd), or nil on any surprise.
    /// The window is generous: that line embeds Codex's whole system
    /// prompt (18 KB in 0.147.0, measured live) — an 8 KB read would
    /// truncate it and silently parse nothing.
    private static func codexMeta(fromRollout url: URL) -> (id: String, cwd: String)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 262_144),
              let text = String(data: data, encoding: .utf8),
              let first = text.split(separator: "\n").first
        else { return nil }

        struct Meta: Decodable {
            let type: String?
            let payload: Payload?
            struct Payload: Decodable {
                let id: String?
                let cwd: String?
            }
        }
        guard let meta = try? JSONDecoder().decode(Meta.self, from: Data(first.utf8)),
              meta.type == "session_meta",
              let id = meta.payload?.id, let cwd = meta.payload?.cwd
        else { return nil }
        return (id, cwd)
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
