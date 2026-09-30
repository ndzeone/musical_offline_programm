import SwiftUI

/// Трек в плейлисте: файл с диска или трек с площадки (с аккаунтом, откуда он взят).
struct SavedTrack: Codable, Identifiable, Hashable {
    enum Source: Codable, Hashable {
        case file(path: String)
        case web(platform: Platform, account: UUID?, link: String?)
    }

    var id = UUID()
    var source: Source
    var title: String
    var artist: String
    var album = ""
    var duration: Double = 0
    var artURL: String?
    var added = Date()

    enum CodingKeys: String, CodingKey { case id, source, title, artist, album, duration, artURL, added }

    init(id: UUID = UUID(), source: Source, title: String, artist: String, album: String = "", duration: Double = 0,
         artURL: String? = nil, added: Date = Date()) {
        self.id = id; self.source = source; self.title = title; self.artist = artist
        self.album = album; self.duration = duration; self.artURL = artURL; self.added = added
    }

    /// Терпеливое чтение: без необязательных полей запись всё равно читается.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        source = try c.decode(Source.self, forKey: .source)
        title = try c.decode(String.self, forKey: .title)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        artist = (try? c.decodeIfPresent(String.self, forKey: .artist)) ?? ""
        album = (try? c.decodeIfPresent(String.self, forKey: .album)) ?? ""
        duration = (try? c.decodeIfPresent(Double.self, forKey: .duration)) ?? 0
        artURL = try? c.decodeIfPresent(String.self, forKey: .artURL)
        added = (try? c.decodeIfPresent(Date.self, forKey: .added)) ?? Date()
    }

    var key: String {
        switch source {
        case .file(let p): return "file:" + URL(fileURLWithPath: p).standardizedFileURL.path
        case .web: return PlayerModel.webKey(artist: artist, title: title)
        }
    }

    var platform: Platform? {
        if case .web(let p, _, _) = source { return p }
        return nil
    }

    var fileURL: URL? {
        if case .file(let p) = source { return URL(fileURLWithPath: p) }
        return nil
    }

    var link: String? {
        if case .web(_, _, let l) = source { return l }
        return nil
    }
}

struct Playlist: Codable, Identifiable, Hashable {
    static let favoritesID = UUID(uuidString: "F4F0F4F0-0000-4000-8000-00000000F4F0")!

    var id = UUID()
    var name: String
    var items: [SavedTrack] = []
    var created = Date()

    var isFavorites: Bool { id == Self.favoritesID }
    var symbol: String { isFavorites ? "heart.fill" : "music.note.list" }
    var duration: Double { items.reduce(0) { $0 + $1.duration } }

    enum CodingKeys: String, CodingKey { case id, name, items, created }

    init(id: UUID = UUID(), name: String, items: [SavedTrack] = [], created: Date = Date()) {
        self.id = id; self.name = name; self.items = items; self.created = created
    }

    /// Одна испорченная запись не должна уничтожить весь плейлист: такие записи пропускаем.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Плейлист"
        created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? Date()
        items = ((try? c.decodeIfPresent([Lenient<SavedTrack>].self, forKey: .items)) ?? []).compactMap(\.value)
    }
}

/// Читает значение, а если не вышло — просто пропускает его.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from d: Decoder) throws { value = try? T(from: d) }
}

/// Файл библиотеки (тот же формат у версий для Mac, Android и Windows — копию можно переносить).
struct LibraryFile: Codable {
    var format = "muzyka-offline-library"
    var version = 2
    var app = "mac"
    var savedAt = Date()
    var playlists: [Playlist]

    enum CodingKeys: String, CodingKey { case format, version, app, savedAt, playlists }

    init(app: String = "mac", playlists: [Playlist]) { self.app = app; self.playlists = playlists }

    /// Копия с Android или Windows читается, даже если какое-то служебное поле записано иначе.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        playlists = ((try c.decode([Lenient<Playlist>].self, forKey: .playlists))).compactMap(\.value)
        format = (try? c.decodeIfPresent(String.self, forKey: .format)) ?? "muzyka-offline-library"
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 2
        app = (try? c.decodeIfPresent(String.self, forKey: .app)) ?? "mac"
        savedAt = (try? c.decodeIfPresent(Date.self, forKey: .savedAt)) ?? Date()
    }
}

/// Плейлисты хранятся в ~/Library/Application Support/MusicCraft/playlists.json.
/// Пишем с небольшой задержкой, при выходе — сразу. Прошлая версия остаётся в playlists.bak.json,
/// повреждённый файл не перезаписывается молча, а откладывается в сторону.
enum LibraryStore {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicCraft", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static let url = dir.appendingPathComponent("playlists.json")
    static let backupURL = dir.appendingPathComponent("playlists.bak.json")

    private static let queue = DispatchQueue(label: "library.save", qos: .utility)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pending: [Playlist]?
    nonisolated(unsafe) private static var scheduled = false
    /// Для проверочных снимков: ничего не записывать на диск.
    nonisolated(unsafe) static var readOnly = false

    static func load() -> [Playlist] {
        let fm = FileManager.default
        var list = read(url)
        if list == nil, fm.fileExists(atPath: url.path) {
            // Файл есть, но не читается — откладываем его, чтобы не потерять, и берём резервную копию
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? fm.copyItem(at: url, to: dir.appendingPathComponent("playlists.corrupt-\(stamp).json"))
            list = read(backupURL)
        }
        var out = list ?? []
        if !out.contains(where: \.isFavorites) {
            out.insert(Playlist(id: Playlist.favoritesID, name: "Любимые"), at: 0)
        }
        return out
    }

    static func read(_ u: URL) -> [Playlist]? {
        guard let d = try? Data(contentsOf: u) else { return nil }
        return decode(d)
    }

    /// Понимает и старый формат (просто список), и новый (с заголовком).
    static func decode(_ d: Data) -> [Playlist]? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let f = try? dec.decode(LibraryFile.self, from: d) { return f.playlists }
        if let l = try? dec.decode([Lenient<Playlist>].self, from: d) { return l.compactMap(\.value) }
        return nil
    }

    static func encode(_ list: [Playlist], app: String = "mac") -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(LibraryFile(app: app, playlists: list))
    }

    static func save(_ list: [Playlist]) {
        guard !readOnly else { return }
        lock.lock()
        pending = list
        let needSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if needSchedule {
            queue.asyncAfter(deadline: .now() + 0.4) { flush() }
        }
    }

    /// Записать немедленно (при выходе из программы).
    static func flushNow() {
        guard !readOnly else { return }
        queue.sync { flush() }
    }

    private static func flush() {
        lock.lock()
        let list = pending
        pending = nil
        scheduled = false
        lock.unlock()
        guard let list, let data = encode(list) else { return }
        let fm = FileManager.default
        // Прошлая исправная версия становится резервной копией
        if fm.fileExists(atPath: url.path), read(url) != nil {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
        }
        try? data.write(to: url, options: .atomic)
    }
}

/// Очередь: играем плейлист по порядку (или вперемешку), треки могут быть с разных площадок.
struct PlayQueue: Codable {
    var playlistID: UUID
    var items: [SavedTrack]
    var order: [Int]
    var pos: Int

    var current: SavedTrack? { order.indices.contains(pos) ? items[order[pos]] : nil }
    var upNext: SavedTrack? { order.indices.contains(pos + 1) ? items[order[pos + 1]] : nil }
}

/// Что играло перед выходом — чтобы после запуска продолжить с того же места.
struct LastSession: Codable {
    var track: SavedTrack
    var position: Double
    var queue: PlayQueue?
    var savedAt = Date()
}
