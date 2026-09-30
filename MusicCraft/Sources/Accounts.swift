import SwiftUI
import WebKit

// MARK: - Площадки и аккаунты

enum Platform: String, Codable, CaseIterable, Identifiable {
    case spotify, soundcloud, yandex, vk
    var id: String { rawValue }

    var title: String {
        switch self {
        case .spotify: return "Spotify"
        case .soundcloud: return "SoundCloud"
        case .yandex: return "Яндекс Музыка"
        case .vk: return "VK Музыка"
        }
    }

    var short: String {
        switch self {
        case .spotify: return "Spotify"
        case .soundcloud: return "SoundCloud"
        case .yandex: return "Яндекс"
        case .vk: return "VK"
        }
    }

    var letter: String {
        switch self {
        case .spotify: return "S"
        case .soundcloud: return "SC"
        case .yandex: return "Я"
        case .vk: return "VK"
        }
    }

    var color: UInt32 {
        switch self {
        case .spotify: return 0x1DB954
        case .soundcloud: return 0xFF5500
        case .yandex: return 0xFFCC00
        case .vk: return 0x0077FF
        }
    }

    /// Цвет буквы на значке площадки.
    var letterColor: UInt32 { self == .yandex ? 0x000000 : 0xFFFFFF }

    /// Сайт умеет переходить на страницу трека без перезагрузки (быстрее).
    var softNavigation: Bool { self != .vk }

    /// Официальные значки сайта (как у закладок в браузере).
    var iconURLs: [URL] {
        let list: [String]
        switch self {
        case .spotify: list = ["https://open.spotifycdn.com/cdn/images/favicon32.b64ecc03.png"]
        case .soundcloud: list = ["https://a-v2.sndcdn.com/assets/images/sc-icons/ios-a62dfc8fe7.png",
                                  "https://a-v2.sndcdn.com/assets/images/sc-icons/favicon-48x48-8466dd3758.png"]
        case .yandex: list = ["https://music.yandex.ru/apple-touch-icon.png", "https://music.yandex.ru/favicon-48x48.png"]
        case .vk: list = ["https://vk.ru/images/icons/pwa/apple/default.png?15"]
        }
        return list.compactMap(URL.init(string:))
    }

    var blurb: String {
        switch self {
        case .spotify: return "Треки, альбомы и твои плейлисты"
        case .soundcloud: return "Треки авторов, миксы и лайки"
        case .yandex: return "Моя волна, коллекция и подборки"
        case .vk: return "Моя музыка, плейлисты и рекомендации"
        }
    }

    var home: URL {
        switch self {
        case .spotify: return URL(string: "https://open.spotify.com/")!
        case .soundcloud: return URL(string: "https://soundcloud.com/discover")!
        case .yandex: return URL(string: "https://music.yandex.ru/")!
        case .vk: return URL(string: "https://vk.ru/audio")!
        }
    }

    var login: URL {
        switch self {
        case .spotify: return URL(string: "https://accounts.spotify.com/ru/login?continue=https%3A%2F%2Fopen.spotify.com%2F")!
        case .soundcloud: return URL(string: "https://soundcloud.com/signin")!
        case .yandex: return URL(string: "https://passport.yandex.ru/auth?retpath=https%3A%2F%2Fmusic.yandex.ru%2F")!
        // to = base64("/audio"): после входа VK сам вернёт в музыку
        case .vk: return URL(string: "https://vk.ru/login?u=2&to=L2F1ZGlv")!
        }
    }

    /// Поиск трека на площадке (когда у сохранённого трека нет прямой ссылки).
    func searchURL(_ q: String) -> URL {
        let query = q.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? q
        let path = q.addingPercentEncoding(withAllowedCharacters: .urlPathSegmentAllowed) ?? q
        switch self {
        case .spotify: return URL(string: "https://open.spotify.com/search/\(path)/tracks")!
        case .soundcloud: return URL(string: "https://soundcloud.com/search/sounds?q=\(query)")!
        case .yandex: return URL(string: "https://music.yandex.ru/search?text=\(query)&type=tracks")!
        case .vk: return URL(string: "https://vk.ru/audio?q=\(query)&section=search")!
        }
    }

    /// Cookie, которая появляется только после входа в аккаунт.
    func isLoginCookie(_ c: HTTPCookie) -> Bool {
        switch self {
        case .spotify: return c.name == "sp_dc"
        case .soundcloud: return c.name == "oauth_token"
        case .yandex: return c.name == "Session_id" && c.domain.contains("yandex")
        case .vk: return c.name == "remixsid" || c.name == "remixnsid"
        }
    }

    /// Страница входа (для подсказки «войди»).
    func isLoginPage(_ u: URL) -> Bool {
        let h = u.host?.lowercased() ?? "", p = u.path.lowercased()
        switch self {
        case .vk: return h.hasPrefix("id.") || h.hasPrefix("oauth.") || p.hasPrefix("/login") || p == "/" || p.isEmpty
        default: return isAuthURL(u)
        }
    }

    /// Страницы входа, с которых после успешного входа уводим на главную музыки.
    func isAuthURL(_ u: URL) -> Bool {
        let h = u.host?.lowercased() ?? "", p = u.path.lowercased()
        switch self {
        case .spotify: return h.hasPrefix("accounts.") || h.hasPrefix("challenge.")
        case .soundcloud: return h.hasPrefix("secure.") || h.hasPrefix("api-auth.") || p.hasPrefix("/signin")
        case .yandex: return h.contains("passport.") || h.hasPrefix("sso.")
        case .vk: return h.hasPrefix("id.") || h.hasPrefix("oauth.") || p.hasPrefix("/login") || p == "/" || p.hasPrefix("/feed")
        }
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var s = CharacterSet.urlQueryAllowed
        s.remove(charactersIn: "&+=?#/")
        return s
    }()

    static let urlPathSegmentAllowed: CharacterSet = {
        var s = CharacterSet.urlPathAllowed
        s.remove(charactersIn: "/?#")
        return s
    }()
}

struct Account: Identifiable, Codable, Equatable {
    var id: UUID
    var platform: Platform
    var name: String
    var autoNamed = false

    enum CodingKeys: String, CodingKey { case id, platform, name, autoNamed }

    init(id: UUID, platform: Platform, name: String, autoNamed: Bool = false) {
        self.id = id; self.platform = platform; self.name = name; self.autoNamed = autoNamed
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        platform = try c.decode(Platform.self, forKey: .platform)
        name = try c.decode(String.self, forKey: .name)
        autoNamed = try c.decodeIfPresent(Bool.self, forKey: .autoNamed) ?? false
    }
}

struct WebState: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var position: Double = 0
    var duration: Double = 0
    var playing = false
    var ended = false
    var rate: Double = 1
    var stamp = Date()
}

private struct RawState: Decodable {
    let title: String?
    let artist: String?
    let album: String?
    let art: String?
    let pos: Double?
    let dur: Double?
    let paused: Bool?
    let ended: Bool?
    let rate: Double?
}

/// Сообщения от страницы. Слабая ссылка, чтобы страница не удерживала сессию в памяти.
@MainActor
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WebSession?
    init(_ t: WebSession) { target = t }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let s = message.body as? String {
            target?.receive(s)
        } else if let e = message.body as? [String: Any] {
            target?.receiveEvent(e)
        }
    }
}

// MARK: - Сессия аккаунта: официальный веб-плеер в своём изолированном хранилище

@MainActor
final class WebSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let accountID: UUID
    let platform: Platform
    let webView: WKWebView
    private let store: WKWebsiteDataStore
    weak var model: PlayerModel?

    private(set) var state = WebState()
    private(set) var artwork: NSImage?
    private(set) var artURL: String?
    private(set) var loggedIn: Bool?
    private(set) var lastActivity = Date()
    /// Когда мы в последний раз сами управляли этим плеером (чтобы отличать это от самовольного запуска).
    private(set) var lastCommand = Date.distantPast
    private(set) var messages = 0
    private var timer: Timer?
    private var inFlightSince: Date?
    private var lastPoll = Date.distantPast
    private var popups: [NSWindow] = []
    private var loginFlow: Bool

    /// Трек, который мы включаем на этой площадке.
    private struct Job {
        var title: String
        var artist: String
        var url: URL
        var started = Date()
        var reloaded = false
        var loadAt = Date()
        var agentAt: Date?
    }
    private var job: Job?
    var hasJob: Bool { job != nil }

    nonisolated static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private static let artCache = NSCache<NSString, NSImage>()

    init(account: Account, model: PlayerModel, startAtLogin: Bool) {
        accountID = account.id
        platform = account.platform
        self.model = model
        loginFlow = startAtLogin
        let cfg = WKWebViewConfiguration()
        // У каждого аккаунта своё хранилище: свои cookies и свой вход
        store = WKWebsiteDataStore(forIdentifier: account.id)
        cfg.websiteDataStore = store
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Играющий плеер не должен «засыпать», даже если его не видно
        cfg.preferences.inactiveSchedulingPolicy = .none
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: Self.hookJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = ucc
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760), configuration: cfg)
        webView.customUserAgent = Self.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.isHidden = true
        super.init()
        ucc.add(MessageProxy(self), name: "mc")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: startAtLogin ? platform.login : platform.home))
        // Страница сама сообщает о каждом событии, а этот таймер лишь сверяет время
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.heartbeat() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
        checkLogin()
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
        job = nil
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mc")
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        popups.forEach { $0.close() }
        popups.removeAll()
    }

    var currentTime: Double {
        guard state.playing else { return state.position }
        let t = state.position + Date().timeIntervalSince(state.stamp) * state.rate
        return state.duration > 0 ? min(t, state.duration) : t
    }

    var isActive: Bool { model?.activeWebID == accountID }
    var isOpen: Bool { model?.openAccountID == accountID }

    /// Нужна подсказка «войди»: новый аккаунт или открыта страница входа, а входа не видно.
    var needsLogin: Bool {
        loginFlow || (loggedIn == false && (webView.url.map(platform.isLoginPage) ?? false))
    }

    /// Аккаунт только что открывали — не выгружать его сразу.
    func touch() { lastActivity = Date() }

    // MARK: Управление

    private func run(_ js: String) {
        lastActivity = Date()
        lastCommand = Date()
        webView.evaluateJavaScript("window.__mc && " + js, completionHandler: nil)
        // Страница пришлёт событие сама; на всякий случай сверимся чуть позже
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.poll(force: true) }
    }

    func toggle() { state.playing ? pause() : play() }

    func play() {
        run("__mc.cmd('play')")
        setOptimistic(playing: true)
    }

    func pause() {
        guard state.playing else { return }
        run("__mc.cmd('pause')")
        setOptimistic(playing: false)
    }

    /// Остановить без лишних вопросов (когда площадка заиграла сама, а её не просили).
    func forcePause() {
        webView.evaluateJavaScript("window.__mc && __mc.cmd('pause')", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.state.playing, !self.isActive else { return }
            self.webView.pauseAllMediaPlayback(completionHandler: nil)
        }
    }

    /// Сразу показываем нажатие, не дожидаясь ответа сайта.
    private func setOptimistic(playing: Bool) {
        guard state.playing != playing else { return }
        state.position = currentTime
        state.stamp = Date()
        state.playing = playing
        model?.webStateChanged(self, trackChanged: false, playingChanged: true)
    }

    func next() { run("__mc.cmd('nexttrack')") }
    func prev() { run("__mc.cmd('previoustrack')") }
    func setVolume(_ v: Double) { webView.evaluateJavaScript("window.__mc && __mc.setVolume(\(min(1, max(0, v))))", completionHandler: nil) }

    func seek(_ t: Double) {
        let v = max(0, t)
        run("__mc.cmd('seekto', \(v))")
        state.position = v
        state.stamp = Date()
    }

    func goHome() { webView.load(URLRequest(url: platform.home)) }
    func minimizePopups() { popups.forEach { if $0.isVisible { $0.miniaturize(nil) } } }
    func goLogin() { loginFlow = true; webView.load(URLRequest(url: platform.login)) }

    /// Ссылка на трек, который играет (для любимых и плейлистов).
    /// Страница может не ответить (занята или «уснула») — через 2 секунды сохраняем без ссылки, а не ждём вечно.
    func fetchLink(_ done: @escaping (String?) -> Void) {
        var answered = false
        let finish: (String?) -> Void = { v in
            guard !answered else { return }
            answered = true
            done(v)
        }
        webView.evaluateJavaScript("window.__mc ? window.__mc.link() : null") { v, _ in
            MainActor.assumeIsolated { finish(v as? String) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { finish(nil) } }
    }

    // MARK: Включить сохранённый трек

    /// Открыть страницу трека (или поиск, если ссылки нет) и включить его.
    /// На странице работает «помощник»: ждёт, пока появится нужная кнопка, и нажимает ровно её.
    func openTrack(link: String?, title: String, artist: String) {
        lastActivity = Date()
        lastCommand = Date()
        let q = [artist, title].filter { !$0.isEmpty }.joined(separator: " ")
        let target = link.flatMap(URL.init(string:)) ?? platform.searchURL(q)
        job = Job(title: title, artist: artist, url: target)
        if platform.softNavigation, let cur = webView.url, cur.host == target.host, !webView.isLoading {
            // Та же площадка: переходим внутри страницы, без перезагрузки плеера (быстрее)
            let path = Self.jsString(target.path + (target.query.map { "?" + $0 } ?? ""))
            let js = """
            (function (p) {
              if (window.next && window.next.router && window.next.router.push) { window.next.router.push(p); return 'next'; }
              history.pushState({}, '', p); window.dispatchEvent(new PopStateEvent('popstate', { state: {} })); return 'history';
            })(\(path))
            """
            wake(true)
            webView.evaluateJavaScript(js, completionHandler: nil)
            startAgent(limit: 7)
        } else {
            reloadJob()
        }
    }

    /// Бросить включение (очередь ушла на другой трек или площадку).
    func cancelAutoplay() {
        guard job != nil else { return }
        job = nil
        wake(false)
        webView.evaluateJavaScript("window.__mc && __mc.autoplayStop()", completionHandler: nil)
    }

    /// Пока включаем трек, страница «видимая» для WebKit (так сайты точно запускают плеер),
    /// но на экране её нет — она под прозрачным слоем. Потом снова спит и не рисуется.
    private func wake(_ on: Bool) {
        let hide = !(on || isOpen)
        if webView.isHidden != hide { webView.isHidden = hide }
    }

    /// Настоящее нажатие мыши в точку страницы (сайт видит его как нажатие пользователя).
    /// Фокус клавиатуры возвращаем туда, где он был, чтобы не сломать горячие клавиши.
    private func nativeClick(x: Double, y: Double, vw: Double, vh: Double) -> Bool {
        guard let win = webView.window, vw > 0, vh > 0, webView.bounds.width > 10, webView.bounds.height > 10 else { return false }
        let sx = webView.bounds.width / vw, sy = webView.bounds.height / vh
        let pView = NSPoint(x: x * sx, y: webView.isFlipped ? y * sy : webView.bounds.height - y * sy)
        let p = webView.convert(pView, to: nil)
        let t = ProcessInfo.processInfo.systemUptime
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: t,
                                            windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: [], timestamp: t + 0.04,
                                          windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
        else { return false }
        let responder = win.firstResponder
        webView.mouseDown(with: down)
        webView.mouseUp(with: up)
        if win.firstResponder !== responder { win.makeFirstResponder(responder) }
        return true
    }

    private func reloadJob() {
        guard var j = job else { return }
        j.reloaded = true
        j.loadAt = Date()
        j.agentAt = nil
        job = j
        wake(true)
        webView.load(URLRequest(url: j.url))
    }

    private func startAgent(limit: Double) {
        guard var j = job else { return }
        j.agentAt = Date()
        job = j
        let js = "window.__mc ? window.__mc.autoplayStart(\(Self.jsString(j.title)), \(Self.jsString(j.artist)), \(Int(limit * 1000))) : 'nohook'"
        webView.evaluateJavaScript(js) { [weak self] v, _ in
            MainActor.assumeIsolated {
                // Страница ещё не готова — heartbeat попробует снова
                if (v as? String) != "started", self?.job != nil { self?.job?.agentAt = nil }
            }
        }
    }

    fileprivate func receiveEvent(_ e: [String: Any]) {
        guard (e["ev"] as? String) == "autoplay", let j = job else { return }
        switch e["r"] as? String {
        case "press":
            lastCommand = Date()
            let x = (e["x"] as? Double) ?? 0, y = (e["y"] as? Double) ?? 0
            let vw = (e["vw"] as? Double) ?? 0, vh = (e["vh"] as? Double) ?? 0
            if !nativeClick(x: x, y: y, vw: vw, vh: vh) {
                webView.evaluateJavaScript("window.__mc && __mc.pressTarget()", completionHandler: nil)
            }
        case "click":
            lastCommand = Date()
        case "timeout":
            if !j.reloaded { reloadJob() } else { finishJob(ok: false) }
        default:
            break
        }
    }

    private func finishJob(ok: Bool) {
        job = nil
        wake(false)
        webView.evaluateJavaScript("window.__mc && __mc.autoplayStop()", completionHandler: nil)
        if !ok { model?.webAutoplayFailed(self) }
    }

    private func jobMatches() -> Bool {
        guard let j = job, state.playing else { return false }
        return PlayerModel.sameSong(state.title, state.artist, j.title, j.artist)
    }

    static func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let arr = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())
    }

    // MARK: Состояние плеера

    fileprivate func receive(_ json: String) {
        inFlightSince = nil
        messages += 1
        guard let d = json.data(using: .utf8), let raw = try? JSONDecoder().decode(RawState.self, from: d) else { return }
        apply(raw)
    }

    private func heartbeat() {
        // Играющий, открытый или активный плеер сверяем раз в секунду, остальные — раз в 6 секунд
        let busy = state.playing || isActive || isOpen || job != nil
        if busy || Date().timeIntervalSince(lastPoll) > 6 { poll() }
        if let j = job {
            if Date().timeIntervalSince(j.started) > 30 {
                finishJob(ok: jobMatches())
            } else if j.reloaded, j.agentAt == nil, Date().timeIntervalSince(j.loadAt) > 6 {
                // Страница долго «грузится» (фоновые запросы), а содержимое уже есть — начинаем
                startAgent(limit: 15)
            }
        }
        if loginFlow || loggedIn != true, Int(Date().timeIntervalSinceReferenceDate) % 4 == 0 { checkLogin() }
    }

    private func poll(force: Bool = false) {
        if !force, let since = inFlightSince, Date().timeIntervalSince(since) < 5 { return }
        inFlightSince = Date()
        lastPoll = Date()
        webView.evaluateJavaScript("window.__mc ? window.__mc.state() : ''") { [weak self] v, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.inFlightSince = nil
                guard let s = v as? String, !s.isEmpty, let d = s.data(using: .utf8),
                      let raw = try? JSONDecoder().decode(RawState.self, from: d) else { return }
                self.apply(raw)
            }
        }
    }

    private func apply(_ raw: RawState) {
        var n = state
        n.title = (raw.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        n.artist = (raw.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        n.album = raw.album ?? ""
        n.position = max(0, raw.pos ?? 0)
        n.duration = max(0, raw.dur ?? 0)
        n.playing = !(raw.paused ?? true)
        n.ended = raw.ended ?? false
        n.rate = raw.rate ?? 1
        n.stamp = Date()
        let trackChanged = n.title != state.title || n.artist != state.artist || abs(n.duration - state.duration) > 1
        let playChanged = n.playing != state.playing
        let endedChanged = n.ended != state.ended
        state = n
        if n.playing { lastActivity = Date() }
        if raw.art != artURL {
            artURL = raw.art
            loadArtwork()
        }
        if job != nil && jobMatches() { finishJob(ok: true) }
        if trackChanged || playChanged || endedChanged {
            model?.webStateChanged(self, trackChanged: trackChanged, playingChanged: playChanged)
        }
    }

    private func loadArtwork() {
        guard let s = artURL, let url = URL(string: s), url.scheme == "https" || url.scheme == "http" else {
            artwork = nil
            model?.webArtworkChanged(self)
            return
        }
        if let img = Self.artCache.object(forKey: s as NSString) {
            artwork = img
            model?.webArtworkChanged(self)
            return
        }
        Task {
            let data = try? await Net.session.data(from: url).0
            guard artURL == s else { return }
            artwork = data.flatMap { NSImage(data: $0) }
            if let a = artwork { Self.artCache.setObject(a, forKey: s as NSString) }
            model?.webArtworkChanged(self)
        }
    }

    // MARK: Вход в аккаунт

    func checkLogin() {
        store.httpCookieStore.getAllCookies { [weak self] cookies in
            MainActor.assumeIsolated {
                guard let self else { return }
                let ok = cookies.contains { self.platform.isLoginCookie($0) }
                let was = self.loggedIn
                self.loggedIn = ok
                if ok && was != true { self.didLogIn() }
                if was != ok { self.model?.objectWillChange.send() }
            }
        }
    }

    private func didLogIn() {
        guard loginFlow else { return }
        loginFlow = false
        // Уходим со страницы входа на главную музыки и узнаём имя аккаунта
        if let u = webView.url, platform.isAuthURL(u) { goHome() }
        Task { [weak self] in
            for _ in 0..<6 {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard let self else { return }
                if await self.detectName() { return }
            }
        }
        model?.webLoggedIn(self)
    }

    private func detectName() async -> Bool {
        let v = try? await webView.evaluateJavaScript("window.__mc ? window.__mc.whoami() : ''")
        guard let name = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count < 60 else {
            return false
        }
        model?.webDetectedName(self, name)
        return true
    }

    // MARK: Навигация, всплывающие окна входа, диалоги

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        if ["http", "https", "about", "blob", "data", "javascript", "file"].contains(scheme) || scheme.isEmpty {
            decisionHandler(.allow)
        } else {
            if let u = navigationAction.request.url { NSWorkspace.shared.open(u) }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkLogin()
        if let j = job, j.reloaded { startAgent(limit: 15) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 720), configuration: configuration)
        popup.customUserAgent = Self.userAgent
        popup.uiDelegate = self
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                           styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.title = "\(platform.title): вход"
        win.contentView = popup
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        popups.append(win)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let i = popups.firstIndex(where: { $0.contentView === webView }) {
            popups[i].close()
            popups.remove(at: i)
        }
        checkLogin()
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        let a = NSAlert()
        a.messageText = platform.title
        a.informativeText = message
        a.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = platform.title
        a.informativeText = message
        a.addButton(withTitle: "ОК")
        a.addButton(withTitle: "Отмена")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }

    // MARK: Скрипт на странице площадки: сообщает, что играет, и даёт кнопки управления

    /// Помощник на странице площадки — общий файл web/agent/site-agent.js (кладётся в программу при сборке).
    static let hookJS: String = {
        let candidates = [Bundle.main.url(forResource: "site-agent", withExtension: "js"),
                          URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                              .appendingPathComponent("../../web/agent/site-agent.js").standardizedFileURL]
        for u in candidates.compactMap({ $0 }) {
            if let s = try? String(contentsOf: u, encoding: .utf8), s.contains("window.__mc") { return s }
        }
        NSLog("site-agent.js не найден")
        return ""
    }()
}

// MARK: - Встраивание веб-плеера в SwiftUI

final class WebHostView: NSView {
    var interactive = true
    override func hitTest(_ point: NSPoint) -> NSView? { interactive ? super.hitTest(point) : nil }
}

/// Плеер площадки. Когда он не открыт, веб-вид скрыт: сайт не рисуется и не тратит процессор,
/// но музыка продолжает играть.
struct WebBrowserView: NSViewRepresentable {
    let webView: WKWebView
    let visible: Bool
    /// Пока включается трек, страница «видимая» для WebKit, но на экране её нет.
    var awake = false

    func makeNSView(context: Context) -> WebHostView {
        let v = WebHostView()
        // Сайт никогда не диктует размер: берём ровно то место, которое дали
        for o in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            v.setContentHuggingPriority(.defaultLow, for: o)
            v.setContentCompressionResistancePriority(.defaultLow, for: o)
        }
        attach(to: v)
        return v
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WebHostView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 600)
    }

    func updateNSView(_ v: WebHostView, context: Context) {
        v.interactive = visible
        if webView.superview !== v { attach(to: v) }
        let hide = !(visible || awake)
        if webView.isHidden != hide { webView.isHidden = hide }
    }

    private func attach(to v: NSView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            webView.topAnchor.constraint(equalTo: v.topAnchor),
            webView.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
    }
}
