import Foundation

/// Remembers the desks between launches — the room greets you with your
/// projects (empty seats and all) instead of a blank floor.
///
/// One small JSON file in Application Support; only real workstations
/// (those with a repository path) are worth remembering, and the caller
/// filters accordingly.
enum WorkstationStore {

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Roster/workstations.json")
    }

    static func load(from url: URL = defaultURL) -> [Workstation] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Workstation].self, from: data)
        else { return [] }
        return list
    }

    static func save(_ workstations: [Workstation], to url: URL = defaultURL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(workstations) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
