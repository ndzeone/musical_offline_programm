import Foundation
import CryptoKit

struct LyricLine: Identifiable, Hashable {
    let id: Int
    var time: Double
    var text: String
}

struct Lyrics {
    var synced: Bool
    var lines: [LyricLine]

    /// Для текста без таймингов раскладываем строки равномерно по длине песни.
    func estimated(duration: Double) -> Lyrics {
        guard !synced else { return self }
        let d = duration > 0 ? duration : 180
        let start = d * 0.07, end = d * 0.93
        let n = Double(max(1, lines.count))
        return Lyrics(synced: false, lines: lines.enumerated().map {
            LyricLine(id: $0.offset, time: start + (end - start) * Double($0.offset) / n, text: $0.element.text)
        })
    }
}

enum LyricsParser {
    private static let timeTag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
    private static let anyTag = try! NSRegularExpression(pattern: #"\[[^\]]*\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"<\d+:\d+(?:[.:]\d+)?>"#)
    private static let metaLine = try! NSRegularExpression(pattern: #"^\s*\[[a-zA-Z#]+:.*\]\s*$"#)
    private static let offsetTag = try! NSRegularExpression(pattern: #"^\s*\[offset:\s*([+-]?\d+)\s*\]"#,
                                                            options: .caseInsensitive)

    static func parse(_ input: String) -> Lyrics? {
        let pre = input.precomposedStringWithCanonicalMapping
        let text = pre.hasPrefix("\u{FEFF}") ? String(pre.dropFirst()) : pre
        var raw: [(Double?, String)] = []
        var offset = 0.0, synced = false

        for line in text.components(separatedBy: .newlines) {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let m = offsetTag.firstMatch(in: line, range: full) {
                offset = (Double(ns.substring(with: m.range(at: 1))) ?? 0) / 1000
                continue
            }
            let tags = timeTag.matches(in: line, range: full)
            if !tags.isEmpty {
                synced = true
                var t = anyTag.stringByReplacingMatches(in: line, range: full, withTemplate: "")
                t = wordTag.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length),
                                                     withTemplate: "")
                t = t.trimmingCharacters(in: .whitespaces)
                for m in tags {
                    let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                    let ss = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                    raw.append((mm * 60 + ss - offset, t))
                }
            } else if metaLine.firstMatch(in: line, range: full) == nil {
                raw.append((nil, line.trimmingCharacters(in: .whitespaces)))
            }
        }

        var out: [(Double, String)]
        if synced {
            out = raw.compactMap { r in r.0.map { ($0, r.1) } }.sorted { $0.0 < $1.0 }
        } else {
            var lines: [String] = []
            for (_, t) in raw where !(t.isEmpty && (lines.last?.isEmpty ?? true)) { lines.append(t) }
            while lines.last?.isEmpty == true { lines.removeLast() }
            out = lines.map { (0, $0) }
        }
        guard out.contains(where: { !$0.1.isEmpty }) else { return nil }
        return Lyrics(synced: synced, lines: out.enumerated().map {
            LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1)
        })
    }
}

// MARK: - Сеть: повторы при сбоях, чтобы один обрыв связи не оставлял песню без текста

enum Net {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 25
        c.httpMaximumConnectionsPerHost = 4
        c.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 40 << 20)
        c.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: c)
    }()

    /// Возвращает данные и код ответа. Повторяет запрос при обрыве связи, 429 и ошибках сервера.
    static func get(_ url: URL, headers: [String: String] = [:], attempts: Int = 3) async throws -> (Data, Int) {
        var lastError: Error = URLError(.unknown)
        for i in 0..<attempts {
            if i > 0 { try await Task.sleep(nanoseconds: UInt64(0.7 * pow(2.4, Double(i - 1)) * 1e9)) }
            do {
                var r = URLRequest(url: url)
                r.timeoutInterval = i == 0 ? 8 : 14
                for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
                let (d, resp) = try await session.data(for: r)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 429 || code >= 500 { lastError = URLError(.badServerResponse); continue }
                return (d, code)
            } catch let e as URLError where e.code == .cancelled {
                throw CancellationError()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

// MARK: - Найденный текст

struct LrcResult: Identifiable {
    let id: String
    let provider: String          // «lrclib» или «NetEase»
    let trackName: String?
    let artistName: String?
    let duration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?
    var score = 0.0
}

enum LyricsSearchError: Error { case network }

// MARK: - lrclib.net (открытая база синхронизированных текстов)

enum LrcLib {
    private struct Item: Decodable {
        let id: Int
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    private static func url(_ path: String, _ items: [URLQueryItem]) -> URL {
        var c = URLComponents(string: "https://lrclib.net" + path)!
        c.queryItems = items
        return c.url!
    }

    private static let headers = ["User-Agent": "MuzykaOffline/2.1 (macOS; https://lrclib.net)"]

    private static func convert(_ x: Item) -> LrcResult? {
        guard x.syncedLyrics != nil || x.plainLyrics != nil else { return nil }
        return LrcResult(id: "lrclib-\(x.id)", provider: "lrclib", trackName: x.trackName, artistName: x.artistName,
                         duration: x.duration, syncedLyrics: x.syncedLyrics, plainLyrics: x.plainLyrics)
    }

    static func search(_ q: String) async throws -> [LrcResult] {
        let (d, code) = try await Net.get(url("/api/search", [URLQueryItem(name: "q", value: q)]), headers: headers)
        guard code == 200 else { return [] }
        return ((try? JSONDecoder().decode([Item].self, from: d)) ?? []).compactMap(convert)
    }

    static func search(track: String, artist: String) async throws -> [LrcResult] {
        var items = [URLQueryItem(name: "track_name", value: track)]
        if !artist.isEmpty { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        let (d, code) = try await Net.get(url("/api/search", items), headers: headers)
        guard code == 200 else { return [] }
        return ((try? JSONDecoder().decode([Item].self, from: d)) ?? []).compactMap(convert)
    }

    /// Точное совпадение по исполнителю, названию и длительности. nil — такого нет в базе.
    static func get(artist: String, title: String, duration: Double) async throws -> LrcResult? {
        let (d, code) = try await Net.get(url("/api/get", [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]), headers: headers)
        guard code == 200, let x = try? JSONDecoder().decode(Item.self, from: d) else { return nil }
        return convert(x)
    }
}

// MARK: - NetEase Cloud Music (вторая база, много синхронных текстов)

enum NetEase {
    private struct SearchResp: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        let result: Result?
    }
    struct Song: Decodable {
        struct Artist: Decodable { let name: String }
        let id: Int
        let name: String
        let artists: [Artist]?
        let duration: Int?
    }
    private struct LyricResp: Decodable {
        struct L: Decodable { let lyric: String? }
        let lrc: L?
    }

    private static let headers = [
        "User-Agent": WebSession.userAgent,
        "Referer": "https://music.163.com/",
    ]

    static func search(_ q: String) async throws -> [Song] {
        var c = URLComponents(string: "https://music.163.com/api/search/get")!
        c.queryItems = [URLQueryItem(name: "s", value: q), URLQueryItem(name: "type", value: "1"),
                        URLQueryItem(name: "limit", value: "8")]
        let (d, code) = try await Net.get(c.url!, headers: headers, attempts: 2)
        guard code == 200 else { return [] }
        return (try? JSONDecoder().decode(SearchResp.self, from: d))?.result?.songs ?? []
    }

    static func lyric(_ song: Song) async throws -> LrcResult? {
        let u = URL(string: "https://music.163.com/api/song/lyric?id=\(song.id)&lv=1&tv=-1")!
        let (d, code) = try await Net.get(u, headers: headers, attempts: 2)
        guard code == 200, let raw = (try? JSONDecoder().decode(LyricResp.self, from: d))?.lrc?.lyric,
              !raw.contains("纯音乐") else { return nil }
        // Убираем строки с авторами на китайском («作词 : …») — это не текст песни
        let credits = try! NSRegularExpression(pattern: #"^\s*(\[[^\]]*\])+\s*[^\s:：]{1,12}\s*[:：]"#)
        let cjk = try! NSRegularExpression(pattern: #"[一-鿿]"#)
        let lines = raw.components(separatedBy: .newlines).filter { l in
            let r = NSRange(location: 0, length: (l as NSString).length)
            return !(credits.firstMatch(in: l, range: r) != nil && cjk.firstMatch(in: l, range: r) != nil)
        }
        let text = lines.joined(separator: "\n")
        guard let parsed = LyricsParser.parse(text), parsed.lines.filter({ !$0.text.isEmpty }).count >= 4 else { return nil }
        let artist = (song.artists ?? []).map(\.name).joined(separator: ", ")
        return LrcResult(id: "netease-\(song.id)", provider: "NetEase", trackName: song.name, artistName: artist,
                         duration: song.duration.map { Double($0) / 1000 },
                         syncedLyrics: parsed.synced ? text : nil, plainLyrics: parsed.synced ? nil : text)
    }
}

// MARK: - Поиск по всем источникам

enum LyricsSearch {
    /// Упрощение строки для сравнения: регистр, «ё», скобки и знаки препинания.
    static func norm(_ s: String) -> String {
        var t = s.lowercased().replacingOccurrences(of: "ё", with: "е")
        t = t.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Название без приписок: «(feat. …)», «(prod. …)», «- Remastered», «[Explicit]».
    static func bareTitle(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*(?i:feat|ft\.|prod|remaster|explicit|version|edit|mix|live|bonus)[^\)\]]*[\)\]]"#,
                                       with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+-\s+.*(?i:remaster|version|edit|live).*$"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+(?i:feat\.?|ft\.)\s.*$"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Первый исполнитель из «A, B & C feat. D».
    static func mainArtist(_ s: String) -> String {
        let parts = s.components(separatedBy: CharacterSet(charactersIn: ",&;/"))
        let first = parts.first ?? s
        return first.replacingOccurrences(of: #"\s+(?i:feat\.?|ft\.|x|и)\s.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let x = norm(a), y = norm(b)
        if x.isEmpty || y.isEmpty { return 0 }
        if x == y { return 1 }
        if x.contains(y) || y.contains(x) { return 0.85 }
        let sx = Set(x.split(separator: " ")), sy = Set(y.split(separator: " "))
        let inter = Double(sx.intersection(sy).count), uni = Double(sx.union(sy).count)
        return uni > 0 ? inter / uni : 0
    }

    static func score(_ r: LrcResult, artist: String, title: String, duration: Double) -> Double {
        let ts = similarity(r.trackName ?? "", title)
        let aSim = artist.isEmpty ? 0.5 : max(similarity(r.artistName ?? "", artist), similarity(r.artistName ?? "", mainArtist(artist)))
        var s = (r.syncedLyrics != nil ? 100 : 0) + ts * 60 + aSim * 30
        if duration > 0, let d = r.duration, d > 0 { s -= min(45, abs(d - duration) * 2.5) }
        if r.provider == "lrclib" { s += 3 }
        return s
    }

    /// Ищет текст: сначала lrclib (быстро), затем NetEase, если хорошего синхронного текста нет.
    /// `query` — ручной поиск по строке. Бросает `.network`, если все источники недоступны.
    private struct Outcome<T: Sendable>: Sendable {
        var value: T
        var failed: Bool
    }

    private static func attempt<T: Sendable>(_ fallback: T, _ f: @escaping @Sendable () async throws -> T) async -> Outcome<T> {
        do { return Outcome(value: try await f(), failed: false) } catch { return Outcome(value: fallback, failed: true) }
    }

    static func find(artist: String, title: String, duration: Double, query: String?) async throws -> [LrcResult] {
        var outcomes: [Bool] = []          // true — запрос не удался (нет связи)
        var list: [LrcResult] = []
        let bare = bareTitle(title), main = mainArtist(artist)
        let both = [main, bare].filter { !$0.isEmpty }.joined(separator: " ")

        if let q = query {
            async let a = attempt([LrcResult]()) { try await LrcLib.search(q) }
            async let b = attempt([NetEase.Song]()) { try await NetEase.search(q) }
            let (ra, rb) = await (a, b)
            outcomes += [ra.failed, rb.failed]
            list = ra.value + (await neteaseLyrics(Array(rb.value.prefix(3))))
        } else {
            // Три запроса к lrclib сразу; как только есть хороший синхронный текст — остальные не ждём
            let isGood: (LrcResult) -> Bool = { r in
                r.syncedLyrics != nil && similarity(r.trackName ?? "", bare) >= 0.8
                    && (artist.isEmpty || similarity(r.artistName ?? "", main) >= 0.5 || similarity(r.artistName ?? "", artist) >= 0.5)
            }
            let canExact = !artist.isEmpty && duration > 0
            await withTaskGroup(of: Outcome<[LrcResult]>.self) { g in
                g.addTask { await attempt([LrcResult]()) { try await LrcLib.search(track: bare, artist: main) } }
                g.addTask { await attempt([LrcResult]()) { try await LrcLib.search(both) } }
                if canExact {
                    g.addTask {
                        await attempt([LrcResult]()) {
                            (try await LrcLib.get(artist: artist, title: title, duration: duration)).map { [$0] } ?? []
                        }
                    }
                }
                for await r in g {
                    outcomes.append(r.failed)
                    list += r.value
                    if list.contains(where: isGood) { g.cancelAll(); break }
                }
            }
            if list.isEmpty && !artist.isEmpty {
                let r = await attempt([LrcResult]()) { try await LrcLib.search(bare) }
                outcomes.append(r.failed)
                list += r.value
            }
            let good = list.contains(where: isGood)
            if !good {
                let r = await attempt([NetEase.Song]()) { try await NetEase.search(both) }
                outcomes.append(r.failed)
                let fitting = r.value.filter { similarity($0.name, bare) >= 0.6 }
                list += await neteaseLyrics(Array(fitting.prefix(3)))
            }
        }

        var seen = Set<String>()
        list = list.filter { seen.insert($0.id).inserted }
        for i in list.indices { list[i].score = score(list[i], artist: artist, title: title, duration: duration) }
        if query == nil { list = list.filter { similarity($0.trackName ?? "", bare) >= 0.45 } }
        list.sort { $0.score > $1.score }
        if list.isEmpty && !outcomes.isEmpty && outcomes.allSatisfy({ $0 }) { throw LyricsSearchError.network }
        return list
    }

    private static func neteaseLyrics(_ songs: [NetEase.Song]) async -> [LrcResult] {
        await withTaskGroup(of: LrcResult?.self) { g in
            for s in songs { g.addTask { try? await NetEase.lyric(s) } }
            var out: [LrcResult] = []
            for await r in g { if let r { out.append(r) } }
            return out
        }
    }
}

// MARK: - Кэш найденных текстов

enum LyricsCache {
    static let dir: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicCraft/Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    static func url(for track: URL) -> URL {
        let h = Insecure.MD5.hash(data: Data(track.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(h + ".lrc")
    }

    /// Для треков из аккаунтов: ключ «web:исполнитель|название».
    static func url(forKey key: String) -> URL {
        let h = Insecure.MD5.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(h + ".lrc")
    }

    static func save(_ text: String, for track: URL) {
        try? text.write(to: url(for: track), atomically: true, encoding: .utf8)
    }

    static func load(for track: URL) -> String? { readText(url(for: track)) }

    /// Размер кэша в байтах и очистка — для настроек.
    static func size() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    static func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }
}

/// Читает текстовый файл в UTF-8 или Windows-1251 (частая кодировка русских .lrc).
func readText(_ url: URL) -> String? {
    guard let d = try? Data(contentsOf: url) else { return nil }
    return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .windowsCP1251)
        ?? String(data: d, encoding: .isoLatin1)
}
