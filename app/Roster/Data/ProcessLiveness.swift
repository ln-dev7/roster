import Darwin
import Foundation

/// "Is anyone actually running in this folder?" — answered with libproc:
/// the user's processes, their working directories, and a peek at their
/// command lines. No sandbox makes this possible, the same trade-off
/// that lets Roster install hooks.
///
/// This is what turns "the transcript is warm, the session is probably
/// open" into a fact: a desk only counts as occupied while a process
/// that looks like the provider's CLI sits in that desk's folder.
/// Cursor is the one provider this cannot cover — its hooks come from
/// the IDE, whose processes don't live in the workspace folder.
enum ProcessLiveness {

    /// One pass over the process table, taken once per scan and queried
    /// many times. `entries` empty means the pass FAILED (libproc said
    /// nothing) — callers must then skip retirement: an unreadable
    /// process table never proves anybody's death.
    struct Snapshot {
        let entries: [(cwd: String, commandLine: String)]

        func contains(_ provider: ProviderKind, at path: String) -> Bool {
            let target = URL(fileURLWithPath: path)
                .resolvingSymlinksInPath().path
            return entries.contains {
                $0.cwd == target && $0.commandLine.contains(provider.processToken)
            }
        }
    }

    static func snapshot() -> Snapshot {
        var entries: [(String, String)] = []
        for pid in allPIDs() {
            // Other users' processes answer neither call; skipping them
            // is correct — agents run as the user.
            guard let cwd = workingDirectory(of: pid),
                  let commandLine = commandLine(of: pid)
            else { continue }
            entries.append((
                URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path,
                commandLine
            ))
        }
        return Snapshot(entries: entries)
    }

    // ── libproc plumbing ────────────────────────────────────────────────

    private static func allPIDs() -> [pid_t] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        // Headroom: processes can appear between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(capacity) * 2)
        let filled = proc_listallpids(
            &pids, Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        guard filled > 0 else { return [] }
        return Array(pids.prefix(Int(filled)))
    }

    /// The process's current working directory, via PROC_PIDVNODEPATHINFO.
    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size
        else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    /// Exec path and arguments glued into one searchable string
    /// (KERN_PROCARGS2: an argc header, then NUL-separated strings).
    private static func commandLine(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let strings = buffer.dropFirst(MemoryLayout<Int32>.size)
            .map { $0 == 0 ? UInt8(ascii: " ") : $0 }
        return String(decoding: strings, as: UTF8.self)
    }
}
