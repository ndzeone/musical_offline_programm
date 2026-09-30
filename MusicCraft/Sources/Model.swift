import SwiftUI
import AVFoundation
import MediaPlayer
import UniformTypeIdentifiers
import WebKit

enum RepeatMode: String { case all, one, none }

/// Окна поверх экрана.
enum Modal: Equatable {
    case lyrics
    case addAccount
    case pasteLyrics
    case newPlaylist(addCurrent: Bool)
    case update
}

struct Track: Identifiable {
    let id = UUID()
    let url: URL
    var title: String
    var artist: String
    var duration: Double = 0
    var artwork: NSImage?
    var color: Int
    var embeddedLyrics: String?
    var metaLoaded = false
    var key: String { "file:" + url.standardizedFileURL.path }
}

/// Текст одной песни (файла или трека из аккаунта).
struct SongLyrics {
    var lyrics: Lyrics?
    var plain: Lyrics?          // исходный текст без тайминга, чтобы пересчитать под длину песни
    var source = ""
    var offset: Double = 0
    var results: [LrcResult] = []
    var resultIndex = 0
}

/// Что играет сейчас: файл или трек из подключённого аккаунта.
struct NowPlaying: Equatable {
    enum Origin: Equatable { case local(UUID), web(UUID) }
    var origin: Origin
    var key: String
    var title: String
    var artist: String
    var duration: Double
    var sourceLabel: String
    var sourceColor: UInt32?
    var loading = false
    var isWeb: Bool { if case .web = origin { return true } else { return false } }
}

struct LyricFrame {
    var index: Int
    var lines: [LyricLine]
    var sung: Int
    var synced: Bool
}

/// Трек из плейлиста, который мы включили на площадке и ждём, когда он заиграет.
struct WebExpect {
    var title: String
    var artist: String
    var duration: Double
    var artURL: String?
    var session: UUID
    var started: Date
    var confirmed: Bool
}

@MainActor
final class PlayerModel: ObservableObject {
    static let shared = PlayerModel()
    static let audioExt: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "aifc", "flac", "caf", "alac",
                                        "mp4", "m4b", "ogg", "opus"]
    static let d = UserDefaults.standard

    let audio = AudioEngine()

    // Файлы
    @Published var tracks: [Track] = [] { didSet { Self.d.set(tracks.map(\.url.path), forKey: "playlist") } }
    @Published var currentID: UUID?

    // Что играет
    @Published var isPlaying = false
    @Published var nowPlaying: NowPlaying?
    @Published var nowArtwork: NSImage?
    @Published var palette: [UInt32] = ArtKit.defaultPalette
    @Published var lyricsDB: [String: SongLyrics] = [:]
    @Published var status = ""
    @Published var searchQuery = ""
    @Published var lyricsOffline = false
    /// Текст этой песни точно не нашёлся (показываем пластинку посередине)
    @Published var lyricsMissing = false
    /// Поиск всей музыки на Mac
    @Published var scanning = false
    @Published var scanResult: ScanResult?

    // Навигация
    @Published var page: Page = .stage
    @Published var modal: Modal?
    @Published var settingsTab: SettingsTab = .look
    @Published var toast = ""
    @Published var toastOn = false
    @Published var showDebug = false
    @Published var windowVisible = true

    // Аккаунты
    @Published var accounts: [Account] = [] {
        didSet { if let data = try? JSONEncoder().encode(accounts) { Self.d.set(data, forKey: "accounts") } }
    }
    @Published var loadedSessions: [UUID] = []
    @Published var activeWebID: UUID?
    private(set) var sessions: [UUID: WebSession] = [:]

    // Плейлисты
    @Published var playlists: [Playlist] = [] { didSet { LibraryStore.save(playlists) } }
    @Published var queue: PlayQueue?
    var webExpect: WebExpect?
    /// Сколько треков очереди подряд не удалось включить (чтобы не пропускать по кругу бесконечно).
    var queueFailures = 0
    /// Что играло до выхода (трек с площадки): показываем «Продолжить».
    @Published var resumeTrack: SavedTrack?
    /// Сдвиг текста для каждой песни — запоминается между запусками.
    var lyricOffsets: [String: Double] = (UserDefaults.standard.dictionary(forKey: "lyricOffsets") as? [String: Double]) ?? [:] {
        didSet { if lyricOffsets.count <= 4000 { Self.d.set(lyricOffsets, forKey: "lyricOffsets") } }
    }
    private var sessionTimer: Timer?

    // Настройки
    @Published var theme: ThemeID { didSet { Self.d.set(theme.rawValue, forKey: "theme") } }
    @Published var background: BackgroundID { didSet { Self.d.set(background.rawValue, forKey: "background") } }
    @Published var volume: Double {
        didSet {
            audio.volume = Float(volume)
            Self.d.set(volume, forKey: "volume")
            activeSession?.setVolume(volume)
        }
    }
    @Published var bass: Double { didSet { applyEQ(); Self.d.set(bass, forKey: "bass") } }
    @Published var bassFreq: Double { didSet { applyEQ(); Self.d.set(bassFreq, forKey: "bassFreq") } }
    @Published var treble: Double { didSet { applyEQ(); Self.d.set(treble, forKey: "treble") } }
    @Published var textScale: Double { didSet { Self.d.set(textScale, forKey: "textScale") } }
    @Published var repeatMode: RepeatMode { didSet { Self.d.set(repeatMode.rawValue, forKey: "repeat") } }
    @Published var shuffle: Bool { didSet { Self.d.set(shuffle, forKey: "shuffle") } }
    @Published var visual: VisualPrefs { didSet { saveVisual() } }
    @Published var stageLayout: StageLayout { didSet { Self.d.set(stageLayout.rawValue, forKey: "stageLayout") } }
    @Published var showSidebar: Bool { didSet { Self.d.set(showSidebar, forKey: "showSidebar") } }
    @Published var pauseHidden: Bool { didSet { Self.d.set(pauseHidden, forKey: "pauseHidden") } }
    @Published var unloadAfter: Int { didSet { Self.d.set(unloadAfter, forKey: "unloadAfter") } }
    @Published var preloadLast: Bool { didSet { Self.d.set(preloadLast, forKey: "preloadLast") } }
    @Published var alwaysOnTop: Bool { didSet { Self.d.set(alwaysOnTop, forKey: "alwaysOnTop"); applyWindowLevel() } }
    @Published var trackToasts: Bool { didSet { Self.d.set(trackToasts, forKey: "trackToasts") } }
    @Published var autoLyrics: Bool { didSet { Self.d.set(autoLyrics, forKey: "autoLyrics") } }
    @Published var coverSize: CoverSize { didSet { Self.d.set(coverSize.rawValue, forKey: "coverSize") } }
    @Published var karaokeMode: KaraokeMode { didSet { Self.d.set(karaokeMode.rawValue, forKey: "karaokeMode") } }
    // 2.4: закруглённое меню, жидкое стекло, обновления с GitHub
    @Published var sidebarRounded: Bool { didSet { Self.d.set(sidebarRounded, forKey: "sidebarRounded") } }
    @Published var liquidGlass: Bool { didSet { Self.d.set(liquidGlass, forKey: "liquidGlass") } }
    @Published var autoUpdates: Bool { didSet { Self.d.set(autoUpdates, forKey: "autoUpdates") } }
    @Published var updateState: UpdateState = .idle
    var updateTimer: Timer?
    var lastWebAccount: UUID? {
        get { Self.d.string(forKey: "lastWebAccount").flatMap(UUID.init(uuidString:)) }
        set { Self.d.set(newValue?.uuidString, forKey: "lastWebAccount") }
    }

    private var toastTask: Task<Void, Never>?
    /// Найденные в интернете обложки для треков без картинки: ключ трека → адрес.
    var artMap: [String: String] = (UserDefaults.standard.dictionary(forKey: "artMap") as? [String: String]) ?? [:] {
        didSet { if artMap.count <= 800 { Self.d.set(artMap, forKey: "artMap") } }
    }
    var artResolving = Set<String>()
    var lyricsLoading: Set<String> = []
    private var artSource: NSImage?
    private var housekeeping: Timer?

    private init() {
        let d = Self.d
        theme = ThemeID(rawValue: d.string(forKey: "theme") ?? "") ?? .minecraft
        background = BackgroundID(rawValue: d.string(forKey: "background") ?? "") ?? .minecraft
        volume = d.object(forKey: "volume") as? Double ?? 0.7
        bass = d.object(forKey: "bass") as? Double ?? 6
        bassFreq = d.object(forKey: "bassFreq") as? Double ?? 100
        treble = d.object(forKey: "treble") as? Double ?? 0
        textScale = d.object(forKey: "textScale") as? Double ?? 1
        repeatMode = RepeatMode(rawValue: d.string(forKey: "repeat") ?? "") ?? .all
        shuffle = d.bool(forKey: "shuffle")
        visual = Self.loadVisual()
        stageLayout = StageLayout(rawValue: d.string(forKey: "stageLayout") ?? "") ?? .side
        showSidebar = d.object(forKey: "showSidebar") as? Bool ?? true
        pauseHidden = d.object(forKey: "pauseHidden") as? Bool ?? true
        unloadAfter = d.object(forKey: "unloadAfter") as? Int ?? 20
        preloadLast = d.object(forKey: "preloadLast") as? Bool ?? true
        alwaysOnTop = d.bool(forKey: "alwaysOnTop")
        trackToasts = d.object(forKey: "trackToasts") as? Bool ?? true
        autoLyrics = d.object(forKey: "autoLyrics") as? Bool ?? true
        coverSize = CoverSize(rawValue: d.string(forKey: "coverSize") ?? "") ?? .medium
        karaokeMode = KaraokeMode(rawValue: d.string(forKey: "karaokeMode") ?? "") ?? .letters
        sidebarRounded = d.bool(forKey: "sidebarRounded")
        liquidGlass = d.bool(forKey: "liquidGlass")
        autoUpdates = d.object(forKey: "autoUpdates") as? Bool ?? true
        if let data = d.data(forKey: "accounts"), let list = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = list
        }
        playlists = LibraryStore.load()

        audio.volume = Float(volume)
        applyEQ()
        audio.onEnded = { [weak self] in Task { @MainActor in self?.trackEnded() } }
        setupRemoteCommands()

        let saved = (d.stringArray(forKey: "playlist") ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !saved.isEmpty { add(urls: saved, playFirst: false, quiet: true) }
    }

    /// Запуск после появления окна: предзагрузка аккаунта и уборка неактивных сессий.
    func start() {
        guard housekeeping == nil else { return }
        PlatformIcons.shared.load()
        DispatchQueue.main.async { self.applyWindowLevel() }
        if preloadLast, let id = lastWebAccount, account(id) != nil { ensureSession(id) }
        let t = Timer(timeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { PlayerModel.shared.unloadIdleSessions() }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        housekeeping = t
        restoreSession()
        verifyArtOnce()
        startUpdateChecks()
        ProfileStore.shared.start()
        let st = Timer(timeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { let m = PlayerModel.shared; if m.isPlaying { m.saveSession() }; m.checkWebExpect() }
        }
        st.tolerance = 2
        RunLoop.main.add(st, forMode: .common)
        sessionTimer = st
    }

    // MARK: - Продолжить с того же места после перезапуска

    /// Запомнить, что играет и где. Вызывается при смене трека, паузе, раз в 10 секунд и при выходе.
    func saveSession() {
        guard let np = nowPlaying, !np.key.hasPrefix("web-unknown") else { return }
        var track: SavedTrack?
        switch np.origin {
        case .local(let id):
            if let t = self.track(id) {
                track = SavedTrack(source: .file(path: t.url.standardizedFileURL.path), title: t.title, artist: t.artist,
                                   duration: t.duration, artURL: artMap[t.key])
            }
        case .web(let aid):
            if let a = account(aid) {
                let q = queue?.current
                let link = q?.key == np.key ? q?.link : nil
                track = SavedTrack(source: .web(platform: a.platform, account: aid, link: link), title: np.title,
                                   artist: np.artist, duration: np.duration, artURL: activeSession?.artURL ?? artMap[np.key])
            }
        }
        guard let track else { return }
        let s = LastSession(track: track, position: currentTime(), queue: queue)
        if let d = try? JSONEncoder().encode(s) { Self.d.set(d, forKey: "lastSession") }
    }

    private func restoreSession() {
        guard let d = Self.d.data(forKey: "lastSession"), let s = try? JSONDecoder().decode(LastSession.self, from: d),
              nowPlaying == nil else { return }
        if let q = s.queue, !q.items.isEmpty { queue = q }
        switch s.track.source {
        case .file(let path):
            guard FileManager.default.fileExists(atPath: path), let id = ensureTrack(URL(fileURLWithPath: path)) else { return }
            prepare(id: id, at: s.position)
        case .web:
            resumeTrack = s.track
        }
    }

    /// Открыть файл на нужном месте, не включая звук (после перезапуска).
    func prepare(id: UUID, at position: Double) {
        guard let i = tracks.firstIndex(where: { $0.id == id }), let d = try? audio.load(url: tracks[i].url), d > 0 else { return }
        tracks[i].duration = d
        currentID = id
        activeWebID = nil
        if position > 1 && position < d - 2 { audio.seek(to: position) }
        isPlaying = false
        refreshNowPlaying()
        Task { await loadMeta(id) }
        updateNowPlayingInfo()
    }

    /// «Продолжить» трек с площадки, который играл до выхода.
    func resume() {
        guard let t = resumeTrack else { return }
        resumeTrack = nil
        if let q = queue, q.current?.key == t.key { startQueueItem() } else { playSaved(t) }
    }

    // MARK: - Копия библиотеки (перенос между Mac, Android и Windows)

    func exportLibrary() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "Музыка в офлайн — библиотека.json"
        p.allowedContentTypes = [.json]
        p.message = "Копия плейлистов и «Любимых». Её можно открыть в версии для Android или Windows."
        guard p.runModal() == .OK, let u = p.url, let d = LibraryStore.encode(playlists) else { return }
        do {
            try d.write(to: u, options: .atomic)
            announce("Копия библиотеки сохранена")
        } catch {
            announce("Не получилось сохранить копию: \(error.localizedDescription)")
        }
    }

    func importLibrary() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        p.message = "Выбери копию библиотеки (с этого Mac, Android или Windows)"
        guard p.runModal() == .OK, let u = p.url else { return }
        guard let d = try? Data(contentsOf: u), let list = LibraryStore.decode(d) else {
            announce("В этом файле нет библиотеки")
            return
        }
        let (np, nt) = mergeLibrary(list)
        announce("Добавлено: плейлистов \(np), треков \(nt)")
    }

    /// Объединить с библиотекой: одинаковые плейлисты сливаются, треки не повторяются.
    @discardableResult
    func mergeLibrary(_ list: [Playlist]) -> (Int, Int) {
        var newPlaylists = 0, newTracks = 0
        for p in list {
            if let i = playlists.firstIndex(where: { $0.id == p.id || ($0.isFavorites && p.isFavorites) || (!$0.isFavorites && !p.isFavorites && $0.name == p.name) }) {
                for it in p.items where !playlists[i].items.contains(where: { $0.key == it.key }) {
                    playlists[i].items.append(it)
                    newTracks += 1
                }
            } else {
                playlists.append(p)
                newPlaylists += 1
                newTracks += p.items.count
            }
        }
        return (newPlaylists, newTracks)
    }

    var themeValue: Theme { Theme.get(theme) }

    /// «Поверх всех окон»: главное окно (не окна входа) держим над остальными.
    func applyWindowLevel() {
        for w in NSApp.windows where !(w is NSPanel) && !w.title.hasSuffix(": вход") && w.contentView != nil {
            w.level = alwaysOnTop ? .floating : .normal
        }
    }

    func setTheme(_ t: ThemeID) {
        theme = t
        background = Theme.get(t).background
    }

    // MARK: - Производительность

    private static func loadVisual() -> VisualPrefs {
        let d = Self.d
        var v = PerfMode.balanced.preset
        if let x = d.object(forKey: "fps") as? Int { v.fps = x }
        if let x = d.object(forKey: "liveBackground") as? Bool { v.liveBackground = x }
        if let x = d.object(forKey: "glass") as? Bool { v.glass = x }
        if let x = d.object(forKey: "glow") as? Bool { v.glow = x }
        if let x = d.object(forKey: "blurLines") as? Bool { v.blurLines = x }
        if let x = d.object(forKey: "bassPulse") as? Bool { v.bassPulse = x }
        if let x = d.object(forKey: "vinylSpin") as? Bool { v.vinylSpin = x }
        if let x = d.object(forKey: "particles") as? Bool { v.particles = x }
        if let x = d.object(forKey: "idleSlow") as? Bool { v.idleSlow = x }
        if let x = d.object(forKey: "bgQuality") as? Double { v.quality = x }
        // 2.5: режимы «Баланс» и «Красота» раньше рисовали фон в полном разрешении — переводим на новые наборы
        if d.object(forKey: "bgQuality") == nil, let mode = PerfMode.allCases.first(where: { var p = $0.preset; p.idleSlow = v.idleSlow; p.quality = v.quality; return p == v }) {
            v = mode.preset
        }
        return v
    }

    private func saveVisual() {
        let d = Self.d, v = visual
        d.set(v.fps, forKey: "fps")
        d.set(v.liveBackground, forKey: "liveBackground")
        d.set(v.glass, forKey: "glass")
        d.set(v.glow, forKey: "glow")
        d.set(v.blurLines, forKey: "blurLines")
        d.set(v.bassPulse, forKey: "bassPulse")
        d.set(v.vinylSpin, forKey: "vinylSpin")
        d.set(v.particles, forKey: "particles")
        d.set(v.idleSlow, forKey: "idleSlow")
        d.set(v.quality, forKey: "bgQuality")
    }

    var perfMode: PerfMode? { PerfMode.allCases.first { $0.preset == visual } }

    func applyPerf(_ mode: PerfMode) {
        visual = mode.preset
        announce("Режим «\(mode.title)»")
    }

    /// Интервал кадра для анимаций (nil — как у экрана).
    var frameInterval: Double? { visual.fps > 0 ? 1.0 / Double(visual.fps) : nil }

    /// Окно не видно — ничего не рисуем.
    var animationsPaused: Bool { pauseHidden && !windowVisible }

    // MARK: - Доступ

    var currentIndex: Int? { tracks.firstIndex { $0.id == currentID } }
    var current: Track? { currentIndex.map { tracks[$0] } }
    var activeSession: WebSession? { activeWebID.flatMap { sessions[$0] } }
    var openAccountID: UUID? { if case .account(let id) = page { return id } else { return nil } }
    func track(_ id: UUID) -> Track? { tracks.first { $0.id == id } }
    func update(_ id: UUID, _ f: (inout Track) -> Void) {
        if let i = tracks.firstIndex(where: { $0.id == id }) { f(&tracks[i]) }
    }
    func account(_ id: UUID) -> Account? { accounts.first { $0.id == id } }
    func session(_ id: UUID) -> WebSession? { sessions[id] }

    func setSession(_ s: WebSession?, for id: UUID) {
        sessions[id] = s
        if s != nil {
            if !loadedSessions.contains(id) { loadedSessions.append(id) }
        } else {
            loadedSessions.removeAll { $0 == id }
        }
    }

    func currentTime() -> Double {
        if let s = activeSession { return s.currentTime }
        return audio.currentTime
    }

    var duration: Double { nowPlaying?.duration ?? 0 }

    var lyricsEntry: SongLyrics? { nowPlaying.flatMap { lyricsDB[$0.key] } }

    nonisolated static func webKey(artist: String, title: String) -> String {
        "web:" + (artist + "|" + title).lowercased()
    }

    /// Это одна и та же песня? Сравниваем без регистра, скобок и приписок.
    /// Название без регистра, «ё», скобок и приписок вроде «(feat. …)» или «- Remastered».
    nonisolated static func songKey(_ t: String) -> String {
        LyricsSearch.norm(LyricsSearch.bareTitle(clean(t)))
    }

    /// Это одна и та же песня? Название должно совпасть полностью (иначе «Трек» и «Трек - Piano» спутаются),
    /// исполнитель — хотя бы частично.
    nonisolated static func sameSong(_ t1: String, _ a1: String, _ t2: String, _ a2: String) -> Bool {
        let x = songKey(t1), y = songKey(t2)
        guard !x.isEmpty, x == y else { return false }
        if a1.isEmpty || a2.isEmpty { return true }
        return LyricsSearch.similarity(LyricsSearch.mainArtist(a1), LyricsSearch.mainArtist(a2)) > 0.3
            || LyricsSearch.similarity(a1, a2) > 0.3
    }

    // MARK: - Ввод для живого фона

    func sceneInput(now: Double) -> SceneInput {
        let binHz = audio.sampleRate / Double(AudioEngine.fftSize)
        let d = duration
        let progress: Double? = nowPlaying != nil && d > 0 ? min(1, currentTime() / d) : nil
        if activeSession != nil {
            let playing = isPlaying
            return SceneInput(progress: progress, playing: playing,
                              spectrum: playing ? Ambient.spectrum(t: now, binHz: binHz) : [], binHz: binHz,
                              level: playing ? 0.45 + 0.15 * sin(now * 2.1) : 0, particles: visual.particles, palette: palette)
        }
        return SceneInput(progress: progress, playing: audio.isPlaying,
                          spectrum: audio.isPlaying ? audio.spectrumSnapshot() : [], binHz: binHz,
                          level: Double(audio.levelSnapshot()), particles: visual.particles, palette: palette)
    }

    static func previewInput(now: Double) -> SceneInput {
        let binHz = 44100.0 / Double(AudioEngine.fftSize)
        return SceneInput(progress: (now / 40).truncatingRemainder(dividingBy: 1), playing: true,
                          spectrum: Ambient.spectrum(t: now, binHz: binHz), binHz: binHz, level: 0.5,
                          particles: true, palette: ArtKit.defaultPalette)
    }

    // MARK: - Добавление файлов

    /// `force`: включить первый файл, даже если что-то уже играет (открытие из Finder).
    func add(urls: [URL], playFirst: Bool = true, quiet: Bool = false, force: Bool = false) {
        var audioURLs: [URL] = [], lrcs: [URL] = []
        for u in urls { collect(u, &audioURLs, &lrcs) }
        var newIDs: [UUID] = []
        var firstRequested: UUID?
        for u in audioURLs {
            let path = u.standardizedFileURL.path
            if let old = tracks.first(where: { $0.url.standardizedFileURL.path == path }) {
                if firstRequested == nil { firstRequested = old.id }
                continue
            }
            let (artist, title) = Self.parseName(u.deletingPathExtension().lastPathComponent)
            let t = Track(url: u, title: title, artist: artist, color: tracks.count % Art.discColors.count)
            tracks.append(t)
            newIDs.append(t.id)
            if firstRequested == nil { firstRequested = t.id }
        }
        for l in lrcs { attachLRC(l, newIDs: newIDs) }
        for id in newIDs { Task { await loadMeta(id) } }
        if !quiet && !newIDs.isEmpty { announce("Добавлено треков: \(newIDs.count)") }
        if playFirst, let first = firstRequested, force || !isPlaying { play(id: first) }
    }

    /// Файл из плейлиста: добавляем в «Мои файлы», если его там нет.
    func ensureTrack(_ url: URL) -> UUID? {
        let path = url.standardizedFileURL.path
        if let t = tracks.first(where: { $0.url.standardizedFileURL.path == path }) { return t.id }
        add(urls: [url], playFirst: false, quiet: true)
        return tracks.first(where: { $0.url.standardizedFileURL.path == path })?.id
    }

    private func collect(_ u: URL, _ audio: inout [URL], _ lrcs: inout [URL]) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            var found: [URL] = []
            while let f = e?.nextObject() as? URL { found.append(f) }
            found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            for f in found where Self.audioExt.contains(f.pathExtension.lowercased()) { audio.append(f) }
        } else {
            let ext = u.pathExtension.lowercased()
            if Self.audioExt.contains(ext) { audio.append(u) } else if ext == "lrc" || ext == "txt" { lrcs.append(u) }
        }
    }

    private func attachLRC(_ url: URL, newIDs: [UUID]) {
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        var target = tracks.first { $0.url.deletingPathExtension().lastPathComponent.lowercased() == base }
        if target == nil {
            target = newIDs.count == 1 ? track(newIDs[0]) : (newIDs.isEmpty ? current : nil)
        }
        guard let t = target, let text = readText(url), let l = LyricsParser.parse(text) else { return }
        LyricsCache.save(text, for: t.url)
        setLyrics(t.key, l, "файл \(url.lastPathComponent)", duration: t.duration)
    }

    nonisolated private static let domain = #"(?:www\.)?[\w-]+\.(?:me|net|com|ru|org|fm|io|cc|biz|info|pro|club|online|site|top|xyz|su|mobi|tv)"#

    /// Убирает приписки сайтов: «[drivemusic.me]», «(zaycev.net)», «muzofond.fm» и т.п.
    nonisolated static func clean(_ input: String) -> String {
        var s = input.precomposedStringWithCanonicalMapping
        s = s.replacingOccurrences(of: #"\s*[\(\[\{][^\)\]\}]*\b"# + domain + #"\b[^\)\]\}]*[\)\]\}]"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\b"# + domain + #"\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " -–—|_"))
    }

    nonisolated static func parseName(_ b: String) -> (String, String) {
        var s = clean(b.replacingOccurrences(of: "_", with: " "))
        s = s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*(?i:official|video|audio|lyric|клип|текст|hd|hq|mp3|remaster|премьера)[^\)\]]*[\)\]]"#,
                                   with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\d{1,3}[\s.\-_]+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let parts = s.components(separatedBy: " - ").flatMap { $0.components(separatedBy: " – ") }
            .flatMap { $0.components(separatedBy: " — ") }
        if parts.count >= 2 { return (parts[0], parts.dropFirst().joined(separator: " - ")) }
        return ("", s)
    }

    func loadMeta(_ id: UUID) async {
        guard let t = track(id), !t.metaLoaded else { return }
        let asset = AVURLAsset(url: t.url)
        var title: String?, artist: String?, art: NSImage?, lyr: String?
        if let items = try? await asset.load(.commonMetadata) {
            for it in items {
                switch it.commonKey {
                case .commonKeyTitle?: title = try? await it.load(.stringValue)
                case .commonKeyArtist?: artist = try? await it.load(.stringValue)
                case .commonKeyArtwork?: if let data = try? await it.load(.dataValue) { art = NSImage(data: data) }
                default: break
                }
            }
        }
        if let l = try? await asset.load(.lyrics), !l.isEmpty { lyr = l }
        if lyr == nil, let all = try? await asset.load(.metadata) {
            let ids: [AVMetadataIdentifier] = [.id3MetadataUnsynchronizedLyric, .iTunesMetadataLyrics]
            for id in ids {
                if let it = AVMetadataItem.metadataItems(from: all, filteredByIdentifier: id).first,
                   let s = try? await it.load(.stringValue), !s.isEmpty { lyr = s; break }
            }
        }
        let dur = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        update(id) { t in
            if let title, case let c = Self.clean(title), !c.isEmpty { t.title = c }
            if let artist, case let c = Self.clean(artist), !c.isEmpty { t.artist = c }
            if let art { t.artwork = art }
            if dur.isFinite, dur > 0, t.duration == 0 { t.duration = dur }
            t.embeddedLyrics = lyr
            t.metaLoaded = true
        }
        if currentID == id && activeWebID == nil { refreshNowPlaying() }
    }

    // MARK: - Управление (файлы, аккаунты, очередь плейлиста)

    /// `fromQueue`: трек включён очередью плейлиста; иначе пользователь выбрал его сам и очередь заканчивается.
    func play(id: UUID, fromQueue: Bool = false) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        let url = tracks[i].url
        do {
            let d = try audio.load(url: url)
            guard d > 0 else {
                audio.unload()
                currentID = nil
                isPlaying = false
                refreshNowPlaying()
                announce("Файл пустой или повреждён: \(url.lastPathComponent)")
                return
            }
            tracks[i].duration = d
        } catch {
            announce("Не могу открыть: \(url.lastPathComponent)")
            return
        }
        if !fromQueue { queue = nil }
        webExpect = nil
        resumeTrack = nil
        queueFailures = 0
        pauseAllWeb()
        activeWebID = nil
        currentID = id
        audio.play()
        isPlaying = true
        refreshNowPlaying()
        Task { await loadMeta(id) }
        updateNowPlayingInfo()
    }

    func togglePlay() {
        if let s = activeSession { s.toggle(); return }
        if currentID == nil, resumeTrack != nil { resume(); return }
        guard currentID != nil else {
            if let q = queue, q.current != nil { startQueueItem(); return }
            if tracks.isEmpty { openPanel() } else { play(id: tracks[0].id) }
            return
        }
        if audio.isPlaying {
            audio.pause()
        } else {
            pauseAllWeb()
            if audio.currentTime >= audio.duration - 0.1 { audio.seek(to: 0) }
            audio.play()
        }
        isPlaying = audio.isPlaying
        updateNowPlayingInfo()
    }

    func stop() {
        if let s = activeSession { s.pause(); s.seek(0); return }
        audio.pause()
        audio.seek(to: 0)
        isPlaying = false
        updateNowPlayingInfo()
    }

    func next(auto: Bool = false) {
        if queue != nil { advanceQueue(1, auto: auto); return }
        if !auto, let s = activeSession { s.next(); return }
        guard !tracks.isEmpty else { return }
        guard let i = currentIndex else { play(id: tracks[0].id); return }
        if shuffle && tracks.count > 1 {
            var r = i
            while r == i { r = Int.random(in: 0..<tracks.count) }
            play(id: tracks[r].id)
        } else if i + 1 < tracks.count {
            play(id: tracks[i + 1].id)
        } else if !auto || repeatMode == .all {
            play(id: tracks[0].id)
        } else {
            isPlaying = false
            updateNowPlayingInfo()
        }
    }

    func prev() {
        if currentTime() > 3 && nowPlaying?.loading != true { seek(to: 0); return }
        if queue != nil { advanceQueue(-1, auto: false); return }
        if let s = activeSession { s.prev(); return }
        guard !tracks.isEmpty else { return }
        guard let i = currentIndex else { play(id: tracks[0].id); return }
        play(id: tracks[i > 0 ? i - 1 : tracks.count - 1].id)
    }

    private func trackEnded() {
        guard activeWebID == nil else { return }
        if repeatMode == .one {
            audio.seek(to: 0); audio.play(); isPlaying = true
        } else {
            next(auto: true)
        }
    }

    func seek(to t: Double) {
        if let s = activeSession { s.seek(t); return }
        audio.seek(to: max(0, t))
        updateNowPlayingInfo()
    }

    func seek(by dt: Double) { seek(to: currentTime() + dt) }

    func cycleRepeat() {
        repeatMode = [.all: .one, .one: .none, .none: .all][repeatMode]!
        announce(["all": "Повтор: весь список", "one": "Повтор: один трек", "none": "Повтор: выключен"][repeatMode.rawValue]!)
    }

    func toggleShuffle() {
        shuffle.toggle()
        announce(shuffle ? "Перемешивание: включено" : "Перемешивание: выключено")
    }

    // MARK: - Навигация

    func show(_ p: Page) {
        if p != .settings && page == .settings { modal = nil }
        page = p
        if case .account = p {} else { NSApp.keyWindow?.makeFirstResponder(nil) }
    }

    func toggleLibrary() { show(page == .library ? .stage : .library) }
    func toggleLyrics() { modal = modal == .lyrics ? nil : .lyrics }

    func openSettings(_ tab: SettingsTab) {
        settingsTab = tab
        modal = nil
        page = .settings
    }

    func toggleSettings() {
        if page == .settings { show(.stage) } else { openSettings(settingsTab) }
    }

    /// Esc: закрыть окно поверх, иначе вернуться к тексту, иначе открыть настройки.
    func escape() {
        if modal != nil { modal = nil } else if page != .stage { show(.stage) } else { openSettings(settingsTab) }
    }

    /// Слоты хотбара, клавиши 1–9.
    func hotbar(_ i: Int) {
        switch i {
        case 0: prev()
        case 1: togglePlay()
        case 2: next()
        case 3: toggleFavorite()
        case 4: cycleRepeat()
        case 5: toggleShuffle()
        case 6: toggleLibrary()
        case 7: toggleLyrics()
        case 8: toggleSettings()
        default: break
        }
    }

    func setVolume(_ v: Double) { volume = min(1, max(0, (v * 20).rounded() / 20)) }

    private func applyEQ() {
        audio.setEQ(bass: Float(bass), bassFreq: Float(bassFreq), treble: Float(treble))
    }

    func remove(id: UUID) {
        if id == currentID {
            audio.unload(); currentID = nil
            if activeWebID == nil { isPlaying = false }
            refreshNowPlaying()
        }
        tracks.removeAll { $0.id == id }
    }

    func clear() {
        audio.unload()
        currentID = nil
        if activeWebID == nil { isPlaying = false }
        tracks.removeAll()
        refreshNowPlaying()
    }

    func announce(_ text: String) {
        toast = text
        toastOn = true
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if !Task.isCancelled { toastOn = false }
        }
    }

    // MARK: - «Что играет» и обложка

    func refreshNowPlaying() {
        var np: NowPlaying?
        var art: NSImage?
        if let wid = activeWebID, let s = sessions[wid], let a = account(wid) {
            let label = "\(a.platform.title) · \(a.name)"
            if let e = webExpect, e.session == wid, !e.confirmed,
               !Self.sameSong(s.state.title, s.state.artist, e.title, e.artist) {
                // Трек из плейлиста ещё загружается: сразу показываем его и ищем текст заранее
                np = NowPlaying(origin: .web(wid), key: Self.webKey(artist: e.artist, title: e.title),
                                title: e.title, artist: e.artist, duration: e.duration,
                                sourceLabel: label, sourceColor: a.platform.color, loading: true)
                art = ArtworkLoader.shared.image(e.artURL)
            } else if !s.state.title.isEmpty {
                let title = Self.clean(s.state.title), artist = Self.clean(s.state.artist)
                np = NowPlaying(origin: .web(wid), key: Self.webKey(artist: artist, title: title),
                                title: title, artist: artist, duration: s.state.duration,
                                sourceLabel: label, sourceColor: a.platform.color)
                art = s.artwork
            } else if s.state.playing || s.state.position > 0 {
                // Музыка идёт, а название сайт ещё не сообщил — не пишем «ничего не играет»
                np = NowPlaying(origin: .web(wid), key: "web-unknown:" + wid.uuidString,
                                title: "Играет в \(a.platform.title)", artist: a.name, duration: s.state.duration,
                                sourceLabel: label, sourceColor: a.platform.color)
            }
        } else if let t = current {
            np = NowPlaying(origin: .local(t.id), key: t.key, title: t.title, artist: t.artist, duration: t.duration,
                            sourceLabel: "Файл · " + t.url.pathExtension.uppercased(), sourceColor: nil)
            art = t.artwork
        }
        let old = nowPlaying
        let keyChanged = np?.key != old?.key
        if np != old { nowPlaying = np }
        if keyChanged, np != nil { resumeTrack = nil; DispatchQueue.main.async { self.saveSession() } }

        if keyChanged || art !== artSource || (nowArtwork == nil && np != nil) {
            artSource = art
            let img = art ?? np.map { ArtKit.placeholder(seed: $0.artist + $0.title) }
            nowArtwork = img
            palette = art.map { ArtKit.palette($0) } ?? ArtKit.defaultPalette
            // Площадка не дала обложку — ищем настоящую
            if art == nil, let np { resolveNowArt(np) }
        }

        guard let np else { status = ""; return }
        if keyChanged || np.title != old?.title || np.artist != old?.artist {
            searchQuery = [np.artist, np.title].filter { !$0.isEmpty }.joined(separator: " ")
        }
        if keyChanged {
            status = ""
            lyricsOffline = false
            lyricsMissing = false
            Task {
                // Для файла сначала дочитываем теги, чтобы объявить настоящее название
                if case .local(let id) = np.origin { await loadMeta(id) }
                guard trackToasts, let cur = nowPlaying, cur.key == np.key, !cur.loading,
                      !cur.key.hasPrefix("web-unknown") else { return }
                announce("Сейчас играет: " + (cur.artist.isEmpty ? "" : cur.artist + " - ") + cur.title)
            }
        }
        // Текст без тайминга растягиваем, когда стала известна длина песни
        if var e = lyricsDB[np.key], let plain = e.plain, np.duration > 0,
           abs((e.lyrics?.lines.last?.time ?? 0) - np.duration * 0.93) > 5 {
            e.lyrics = plain.estimated(duration: np.duration)
            lyricsDB[np.key] = e
        }
        if !np.key.hasPrefix("web-unknown") { ensureLyrics(np) }
    }

    /// Настоящая обложка для трека без картинки: по названию (Deezer) или по ссылке на трек.
    func resolveNowArt(_ np: NowPlaying) {
        guard !np.key.hasPrefix("web-unknown"), !np.title.isEmpty, !artResolving.contains(np.key) else { return }
        if case .local = np.origin, np.artist.isEmpty { return }      // у файла без исполнителя легко промахнуться
        let key = np.key
        artResolving.insert(key)
        Task {
            var url = artMap[key]
            if url == nil {
                url = await ArtResolver.resolve(title: np.title, artist: np.artist, link: nil)
                if let url { artMap[key] = url }
            }
            let img = await ArtworkLoader.shared.fetch(url)
            artResolving.remove(key)
            guard let img, nowPlaying?.key == key, artSource == nil else { return }
            nowArtwork = img
            palette = ArtKit.palette(img)
            if case .local(let id) = np.origin { update(id) { $0.artwork = img } }
        }
    }

    // MARK: - Диалоги

    func openPanel() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.message = "Выбери музыку (можно папку). Файлы .lrc с тем же именем подтянутся сами."
        p.prompt = "Добавить"
        if p.runModal() == .OK { add(urls: p.urls) }
    }

    func openFolderPanel() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.prompt = "Добавить папку"
        if p.runModal() == .OK { add(urls: p.urls) }
    }

    // MARK: - Медиаклавиши и «Сейчас играет» в macOS

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in PlayerModel.shared.togglePlay() }; return .success }
        cc.playCommand.addTarget { _ in
            Task { @MainActor in let m = PlayerModel.shared; if !m.isPlaying { m.togglePlay() } }; return .success
        }
        cc.pauseCommand.addTarget { _ in
            Task { @MainActor in let m = PlayerModel.shared; if m.isPlaying { m.togglePlay() } }; return .success
        }
        cc.nextTrackCommand.addTarget { _ in Task { @MainActor in PlayerModel.shared.next() }; return .success }
        cc.previousTrackCommand.addTarget { _ in Task { @MainActor in PlayerModel.shared.prev() }; return .success }
        cc.changePlaybackPositionCommand.addTarget { e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in PlayerModel.shared.seek(to: t) }
            return .success
        }
    }

    func updateNowPlayingInfo() {
        guard activeWebID == nil else { return }
        let c = MPNowPlayingInfoCenter.default()
        guard let t = current else { c.nowPlayingInfo = nil; c.playbackState = .stopped; return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyPlaybackDuration: t.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: audio.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let art = t.artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        c.nowPlayingInfo = info
        c.playbackState = isPlaying ? .playing : .paused
    }
}
