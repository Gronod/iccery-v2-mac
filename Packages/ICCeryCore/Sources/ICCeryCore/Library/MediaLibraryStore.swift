import Foundation

/// Persistence for `MediaRecipe` entries (issue #146).
///
/// `media_library.json` is a sibling of `settings.json`, never a field
/// inside it. Writes are atomic via `JSONFileStore` → `AtomicFileWriter`
/// (`.tmp` + rename, #213). A corrupt file throws on load/upsert and is
/// never overwritten — the view model turns the throw into an empty
/// list plus a persistent warning banner.
public actor MediaLibraryStore {

    /// Default cap.
    public static let defaultCapacity = 200

    /// Path to the JSON store.
    public let url: URL

    /// In-memory cache, kept in sync with disk.
    private var recipes: [MediaRecipe] = []

    /// Explicit load flag — an empty file is still "loaded".
    private var loaded = false

    private let capacity: Int
    private let fileStore: JSONFileStore<[MediaRecipe]>

    public init(
        url: URL = AppPaths.appDataDir.appendingPathComponent("media_library.json"),
        capacity: Int = defaultCapacity
    ) {
        self.url = url
        self.capacity = capacity
        self.fileStore = JSONFileStore(
            fileURL: url,
            corrupt: .throwCorrupt,
            defaultValue: { [] },
            dateEncoding: .iso8601,
            dateDecoding: .iso8601
        )
    }

    /// Loads recipes from disk. Returns the existing cache if already
    /// loaded.
    ///
    /// Throws when the file exists but cannot be parsed; the existing
    /// file is never overwritten in that case and `loaded` stays false
    /// so the next call re-reads.
    public func load() throws -> [MediaRecipe] {
        guard !loaded else { return recipes }
        guard FileManager.default.fileExists(atPath: url.path) else {
            loaded = true
            return []
        }
        recipes = try fileStore.load()
        loaded = true
        return recipes
    }

    /// Returns all cached recipes.
    public func all() -> [MediaRecipe] {
        recipes
    }

    /// Inserts or replaces a recipe matched by `id`, then writes
    /// atomically. Replacement preserves `created` and bumps `updated`;
    /// inserts beyond `capacity` throw `.capacityReached` — no silent
    /// eviction.
    ///
    /// Loads the existing library first and propagates any load error
    /// so an unparseable file is never overwritten.
    @discardableResult
    public func upsert(_ recipe: MediaRecipe) throws -> [MediaRecipe] {
        let validated = try recipe.validated()
        try load()

        var updated = recipes
        if let index = updated.firstIndex(where: { $0.id == validated.id }) {
            var existing = validated
            existing.created = updated[index].created
            existing.updated = Date()
            updated[index] = existing
        } else {
            guard updated.count < capacity else {
                throw MediaLibraryError.capacityReached(capacity)
            }
            updated.append(validated)
        }

        try fileStore.save(updated)
        recipes = updated
        return updated
    }

    /// Removes a recipe by id and writes atomically. Returns false when
    /// no recipe with that id exists.
    @discardableResult
    public func delete(id: String) throws -> Bool {
        try load()
        let before = recipes.count
        let updated = recipes.filter { $0.id != id }
        guard updated.count != before else { return false }
        try fileStore.save(updated)
        recipes = updated
        return true
    }

    public enum MediaLibraryError: LocalizedError, Equatable {
        case capacityReached(Int)

        public var errorDescription: String? {
            switch self {
            case .capacityReached(let cap):
                return "Media library is full (\(cap)). Delete a recipe first."
            }
        }
    }
}
