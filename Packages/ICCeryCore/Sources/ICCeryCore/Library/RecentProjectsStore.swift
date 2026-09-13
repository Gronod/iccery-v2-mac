import Foundation

/// One row in `recent_projects.json` — bookmark `Data` *and* the plain
/// absolute path so the entry still resolves when the bookmark can't.
public struct RecentProjectEntry: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    /// Absolute path to the `.icceryproj` file.
    public var path: String
    /// File bookmark; optional — path is the fallback.
    public var bookmark: Data?
    public var updated: Date

    public var id: String { path }

    /// Stable digest of `path` for `projectRecent-{hash}` menu ids —
    /// FNV-1a 64, stable across launches unlike `hashValue`.
    public var bookmarkHash: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    public init(name: String, path: String, bookmark: Data? = nil, updated: Date = Date()) {
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.updated = updated
    }

    enum CodingKeys: String, CodingKey {
        case name, path, bookmark, updated
    }
}

/// Recent-projects list (issue #149). Lives in
/// `AppPaths.appDataDir/recent_projects.json` — app data, never inside
/// the project file (R12).
///
/// Cap 20, newest first, deduplicated by path. Entries whose file is
/// gone are dropped by `pruneMissing()` (called when the Open Recent
/// submenu builds). A corrupt file throws on load and is never
/// overwritten — the view model shows an empty list and keeps the
/// bytes (`.throwCorrupt`, R12).
public actor RecentProjectsStore {

    /// Default cap.
    public static let defaultCapacity = 20

    /// Path to the JSON store.
    public let url: URL

    /// In-memory cache, kept in sync with disk.
    private var entries: [RecentProjectEntry] = []

    /// Explicit load flag — an empty file is still "loaded".
    private var loaded = false

    private let capacity: Int
    private let fileStore: JSONFileStore<[RecentProjectEntry]>
    private let fileManager: FileManager

    public init(
        url: URL = AppPaths.appDataDir.appendingPathComponent("recent_projects.json"),
        capacity: Int = defaultCapacity,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.capacity = capacity
        self.fileManager = fileManager
        self.fileStore = JSONFileStore(
            fileURL: url,
            corrupt: .throwCorrupt,
            defaultValue: { [] },
            dateEncoding: .iso8601,
            dateDecoding: .iso8601
        )
    }

    /// Loads entries from disk. Returns the existing cache if already
    /// loaded. Throws when the file exists but cannot be parsed; the
    /// existing file is never overwritten in that case.
    public func load() throws -> [RecentProjectEntry] {
        guard !loaded else { return entries }
        guard fileManager.fileExists(atPath: url.path) else {
            loaded = true
            return []
        }
        entries = try fileStore.load()
        loaded = true
        return entries
    }

    /// Returns all cached entries, newest first.
    public func all() -> [RecentProjectEntry] {
        entries
    }

    /// Pushes a project to the front, deduplicating by path and
    /// trimming to `capacity`. Writes atomically.
    ///
    /// Loads the existing list first and propagates any load error so
    /// an unparseable file is never overwritten.
    @discardableResult
    public func add(url fileURL: URL, name: String) throws -> [RecentProjectEntry] {
        try load()
        let bookmark = try? fileURL.bookmarkData()
        var updated = entries.filter { $0.path != fileURL.path }
        updated.insert(
            RecentProjectEntry(
                name: name,
                path: fileURL.path,
                bookmark: bookmark,
                updated: Date()),
            at: 0)
        if updated.count > capacity {
            updated = Array(updated.prefix(capacity))
        }
        try fileStore.save(updated)
        entries = updated
        return updated
    }

    /// Removes an entry by path and writes atomically. Returns false
    /// when no entry with that path exists.
    @discardableResult
    public func remove(path: String) throws -> Bool {
        try load()
        let before = entries.count
        let updated = entries.filter { $0.path != path }
        guard updated.count != before else { return false }
        try fileStore.save(updated)
        entries = updated
        return true
    }

    /// `Clear Menu` — wipes the recents file only; `.icceryproj` files
    /// are never deleted (R12).
    public func clear() throws {
        try load()
        try fileStore.save([])
        entries = []
    }

    /// Drops entries whose file is gone and rewrites the store.
    /// Called when the Open Recent submenu builds — missing files are
    /// dropped there, not at launch (issue #149).
    @discardableResult
    public func pruneMissing() throws -> [RecentProjectEntry] {
        try load()
        let kept = entries.filter {
            fileManager.fileExists(atPath: $0.path)
        }
        if kept.count != entries.count {
            try fileStore.save(kept)
            entries = kept
        }
        return kept
    }
}
