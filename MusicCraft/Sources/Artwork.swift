import SwiftUI
import AVFoundation
import CryptoKit

private func md5(_ s: String) -> String {
    Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func supportDir(_ name: String) -> URL {
    let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MusicCraft/" + name, isDirectory: true)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

// MARK: - Картинки обложек по адресу: память + диск, чтобы плейлисты показывали обложки сразу

@MainActor
final class ArtworkLoader: ObservableObject {
    static let shared = ArtworkLoader()
    static let dir = supportDir("Artwork")

    private let cache = NSCache<NSString, NSImage>()
    private var loading = Set<String>()
    private var failed: [String: Date] = [:]
    @Published private(set) var version = 0

    /// Картинка сразу, если она уже есть; иначе начинаем загрузку и сообщаем, когда будет готова.
    func image(_ url: String?) -> NSImage? {
        guard let url, !url.isEmpty else { return nil }
        if let img = cache.object(forKey: url as NSString) { return img }
        if let f = failed[url], Date().timeIntervalSince(f) < 300 { return nil }
        guard !loading.contains(url) else { return nil }
        loading.insert(url)
        Task {
            _ = await fetch(url)
            loading.remove(url)
        }
        return nil
    }

    /// Загрузить картинку и дождаться её: память → диск → сеть. Для файлов — картинка из тегов.
    func fetch(_ url: String?) async -> NSImage? {
        guard let url, let u = URL(string: url) else { return nil }
        if let img = cache.object(forKey: url as NSString) { return img }
        var img: NSImage?
        if u.isFileURL {
            img = await Self.embedded(u)
        } else if u.scheme?.hasPrefix("http") == true {
            let file = Self.dir.appendingPathComponent(md5(url))
            if let d = try? Data(contentsOf: file) { img = NSImage(data: d) }
            if img == nil {
                do {
                    let (d, code) = try await Net.get(u, attempts: 2)
                    if code == 200, let i = NSImage(data: d) {
                        img = i
                        try? d.write(to: file, options: .atomic)
                    } else if code == 404 || code == 410 || code == 403 || code == 200 {
                        // Картинки по этому адресу больше нет — пусть найдут обложку заново
                        PlayerModel.shared.artworkBroken(url)
                    }
                } catch {
                    // Нет связи — адрес не трогаем, попробуем позже
                }
            }
        }
        if let img {
            cache.setObject(img, forKey: url as NSString)
            failed[url] = nil
            version += 1
        } else {
            failed[url] = Date()
        }
        return img
    }

    /// Обложка, вшитая в аудиофайл.
    private static func embedded(_ u: URL) async -> NSImage? {
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        let asset = AVURLAsset(url: u)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        for it in items where it.commonKey == .commonKeyArtwork {
            if let d = try? await it.load(.dataValue), let img = NSImage(data: d) { return img }
        }
        return nil
    }

    /// Уже загруженная картинка (без запуска загрузки).
    func cached(_ url: String?) -> NSImage? {
        guard let url else { return nil }
        return cache.object(forKey: url as NSString)
    }

    static func clearDisk() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }

    static func diskSize() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

// MARK: - Где взять настоящую обложку, если площадка её не дала

enum ArtResolver {
    /// По ссылке на трек (Spotify, SoundCloud — открытый oEmbed) или по названию (Deezer).
    static func resolve(title: String, artist: String, link: String?) async -> String? {
        if let link, let u = URL(string: link), let host = u.host?.lowercased() {
            if host.contains("spotify.com"), let t = await oembed("https://open.spotify.com/oembed", link) { return t }
            if host.contains("soundcloud.com"), let t = await oembed("https://soundcloud.com/oembed", link, extra: [URLQueryItem(name: "format", value: "json")]) {
                return t
            }
        }
        if let y = await yandex(title: title, artist: artist) { return y }
        return await deezer(title: title, artist: artist)
    }

    private struct YandexResp: Decodable {
        struct Result: Decodable { let tracks: Tracks? }
        struct Tracks: Decodable { let results: [Track]? }
        struct Track: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable { let coverUri: String? }
            let title: String
            let artists: [Artist]?
            let coverUri: String?
            let albums: [Album]?
        }
        let result: Result?
    }

    /// Поиск Яндекс Музыки: у русской музыки обложки находятся почти всегда.
    private static func yandex(title: String, artist: String) async -> String? {
        let bare = LyricsSearch.bareTitle(title), main = LyricsSearch.mainArtist(artist)
        guard !bare.isEmpty else { return nil }
        var c = URLComponents(string: "https://api.music.yandex.net/search")!
        c.queryItems = [URLQueryItem(name: "text", value: [main, bare].filter { !$0.isEmpty }.joined(separator: " ")),
                        URLQueryItem(name: "type", value: "track"), URLQueryItem(name: "page", value: "0")]
        guard let u = c.url, let (d, code) = try? await Net.get(u, attempts: 2), code == 200,
              let resp = try? JSONDecoder().decode(YandexResp.self, from: d) else { return nil }
        let best = (resp.result?.tracks?.results ?? []).first { t in
            let names = (t.artists ?? []).map(\.name).joined(separator: ", ")
            return LyricsSearch.similarity(t.title, bare) >= 0.8
                && (main.isEmpty || LyricsSearch.similarity(names, main) >= 0.5 || LyricsSearch.similarity(names, artist) >= 0.5)
        }
        guard let cover = best?.coverUri ?? best?.albums?.first?.coverUri, !cover.isEmpty else { return nil }
        return "https://" + cover.replacingOccurrences(of: "%%", with: "400x400")
    }

    private static func oembed(_ base: String, _ link: String, extra: [URLQueryItem] = []) async -> String? {
        var c = URLComponents(string: base)!
        c.queryItems = [URLQueryItem(name: "url", value: link)] + extra
        guard let u = c.url, let (d, code) = try? await Net.get(u, headers: ["User-Agent": WebSession.userAgent], attempts: 2),
              code == 200, let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return obj["thumbnail_url"] as? String
    }

    private struct DeezerResp: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable { let cover_xl: String?; let cover_big: String? }
            let title: String
            let artist: Artist
            let album: Album
        }
        let data: [Item]?
    }

    private static func deezer(title: String, artist: String) async -> String? {
        let bare = LyricsSearch.bareTitle(title), main = LyricsSearch.mainArtist(artist)
        guard !bare.isEmpty else { return nil }
        var c = URLComponents(string: "https://api.deezer.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: [main, bare].filter { !$0.isEmpty }.joined(separator: " ")),
                        URLQueryItem(name: "limit", value: "8")]
        guard let u = c.url, let (d, code) = try? await Net.get(u, attempts: 2), code == 200,
              let resp = try? JSONDecoder().decode(DeezerResp.self, from: d) else { return nil }
        let best = (resp.data ?? []).first { it in
            LyricsSearch.similarity(it.title, bare) >= 0.8
                && (main.isEmpty || LyricsSearch.similarity(it.artist.name, main) >= 0.5 || LyricsSearch.similarity(it.artist.name, artist) >= 0.5)
        }
        return best?.album.cover_xl ?? best?.album.cover_big
    }
}

// MARK: - Значки площадок: официальные иконки сайтов (как у закладок в браузере)

@MainActor
final class PlatformIcons: ObservableObject {
    static let shared = PlatformIcons()
    static let dir = supportDir("Icons")
    @Published private(set) var images: [Platform: NSImage] = [:]
    private var started = false

    func load() {
        guard !started else { return }
        started = true
        for p in Platform.allCases {
            let file = Self.dir.appendingPathComponent(p.rawValue + ".png")
            if let d = try? Data(contentsOf: file), let img = NSImage(data: d) {
                images[p] = img
                continue
            }
            Task {
                guard let d = await Self.fetch(p), let img = NSImage(data: d) else { return }
                try? d.write(to: file, options: .atomic)
                images[p] = img
            }
        }
    }

    private static func fetch(_ p: Platform) async -> Data? {
        for u in p.iconURLs {
            if let (d, code) = try? await Net.get(u, headers: ["User-Agent": WebSession.userAgent], attempts: 2),
               code == 200, let img = NSImage(data: d), img.size.width >= 16 { return d }
        }
        return nil
    }
}

/// Значок площадки: настоящая иконка сайта, а пока она не скачалась — буква в фирменном цвете.
struct PlatformBadge: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var icons = PlatformIcons.shared
    let platform: Platform
    var size: CGFloat = 20

    var body: some View {
        let r = theme.pixel ? 0 : size * 0.26
        Group {
            if let img = icons.images[platform] {
                ZStack {
                    // У Spotify прозрачная иконка — подкладываем тёмный фон, как в их приложении
                    if platform == .spotify { Color(hex: 0x121212) }
                    Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .padding(platform == .spotify ? size * 0.12 : 0)
                }
            } else {
                ZStack {
                    Color(hex: platform.color)
                    Text(platform.letter)
                        .font(.system(size: size * (platform.letter.count > 1 ? 0.42 : 0.55), weight: .black))
                        .foregroundStyle(Color(hex: platform.letterColor))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
    }
}
