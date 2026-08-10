import Foundation

/// Tails Roster's spool file: replays what's already there (events that
/// happened while Roster was closed), then delivers each new line as the
/// hook appends it.
///
/// Plain GCD, no third parties: a `DispatchSource` watches the file
/// descriptor for writes, and every wake-up drains from the last offset.
/// Lines are handed to the callback **in order, on the main queue** — the
/// office lives on the main actor.
///
/// The callback's second parameter says whether the line is REPLAY
/// (already in the file when we opened it) or LIVE (appended while
/// watching). The distinction matters: replayed lines are history, and
/// the consumer may want to drop the history of sessions that are
/// provably over — otherwise a session that died without its SessionEnd
/// (killed terminal, crash) haunts the room at every launch.
final class SpoolWatcher {

    private let url: URL
    private let onLine: @MainActor (String, _ isReplay: Bool) -> Void
    private let queue = DispatchQueue(label: "me.lndev.roster.spool")

    private var handle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var remainder = Data()

    init(url: URL, onLine: @escaping @MainActor (String, _ isReplay: Bool) -> Void) {
        self.url = url
        self.onLine = onLine
    }

    deinit {
        source?.cancel()
        try? handle?.close()
    }

    func start() {
        queue.async { [self] in
            openFileCreatingIfNeeded()
            drain(replay: true)
            installSource()
        }
    }

    func stop() {
        queue.async { [self] in
            source?.cancel()
            source = nil
            try? handle?.close()
            handle = nil
        }
    }

    // MARK: - Internals (all on `queue`)

    private func openFileCreatingIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forReadingFrom: url)
    }

    private func installSource() {
        guard let handle else { return }
        // .extend fires on append — the common case; .write covers rewrites.
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: handle.fileDescriptor,
            eventMask: [.extend, .write, .delete, .rename],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            if src.data.contains(.delete) || src.data.contains(.rename) {
                // The file was replaced (e.g. rotated): reopen and rescan.
                // Rescanning a rotated file is reading history — replay.
                self.source?.cancel()
                self.source = nil
                try? self.handle?.close()
                self.remainder.removeAll()
                self.openFileCreatingIfNeeded()
                self.drain(replay: true)
                self.installSource()
            } else {
                self.drain(replay: false)
            }
        }
        src.activate()
        source = src
    }

    /// Reads everything new since the last call and emits complete lines.
    private func drain(replay: Bool) {
        guard let handle else { return }

        // Truncation guard: if the file shrank under us, start over.
        let size = (try? FileManager.default
            .attributesOfItem(atPath: url.path))?[.size] as? UInt64
        if let size, let position = try? handle.offset(), size < position {
            try? handle.seek(toOffset: 0)
            remainder.removeAll()
        }

        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        remainder.append(data)

        // Split on \n; the tail after the last newline stays buffered until
        // the hook finishes writing it.
        while let newline = remainder.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = remainder[remainder.startIndex..<newline]
            remainder.removeSubrange(remainder.startIndex...newline)
            guard let line = String(data: Data(lineData), encoding: .utf8),
                  !line.trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }

            // Main queue keeps delivery ordered; assumeIsolated is sound
            // because the main queue *is* the main actor's executor.
            DispatchQueue.main.async { [onLine] in
                MainActor.assumeIsolated {
                    onLine(line, replay)
                }
            }
        }
    }
}
