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
    func goLogin() { loginFlow = true; webView.load(URLRequest(url: platform.login)) }

    /// Ссылка на трек, который играет (для любимых и плейлистов).
    func fetchLink(_ done: @escaping (String?) -> Void) {
        webView.evaluateJavaScript("window.__mc ? window.__mc.link() : null") { v, _ in
            MainActor.assumeIsolated { done(v as? String) }
        }
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
            if Date().timeIntervalSince(j.started) > 40 {
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

    static let hookJS = #"""
    (function () {
      if (window.__mc) return;
      var mc = window.__mc = { media: new Set(), handlers: {}, pos: null, timer: null, last: 0, volume: null, ap: null };
      var host = location.hostname;
      var P = /(^|\.)spotify\.com$/.test(host) ? 'spotify' : /(^|\.)soundcloud\.com$/.test(host) ? 'soundcloud'
            : /(^|\.)yandex\./.test(host) ? 'yandex' : /(^|\.)vk\.(ru|com)$/.test(host) ? 'vk' : 'other';
      function now() { return performance.now(); }
      function fold() {
        if (mc.pos && !mc.pos.frozen) { mc.pos.p += (now() - mc.pos.t) / 1000 * mc.pos.r; mc.pos.t = now(); }
      }
      function send(o) { try { window.webkit.messageHandlers.mc.postMessage(o); } catch (e) {} }
      function post() {
        if (mc.timer) return;
        var wait = Math.max(0, 120 - (now() - mc.last));
        mc.timer = setTimeout(function () { mc.timer = null; mc.last = now(); send(mc.state()); }, wait);
      }
      mc.post = post;
      function track(m) {
        if (!m || mc.media.has(m)) return;
        mc.media.add(m);
        m.addEventListener('pause', function () { fold(); if (mc.pos) mc.pos.frozen = true; post(); });
        m.addEventListener('playing', function () { if (mc.pos && mc.pos.frozen) { mc.pos.t = now(); mc.pos.frozen = false; } post(); });
        ['play', 'ended', 'loadedmetadata', 'durationchange', 'seeked', 'ratechange', 'emptied'].forEach(function (ev) {
          m.addEventListener(ev, post);
        });
        try { if (mc.volume !== null) m.volume = mc.volume; } catch (e) {}
      }
      var origPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function () { try { track(this); } catch (e) {} return origPlay.apply(this, arguments); };
      var ms = navigator.mediaSession;
      if (ms) {
        if (ms.setActionHandler) {
          var oh = ms.setActionHandler.bind(ms);
          ms.setActionHandler = function (a, h) { mc.handlers[a] = h; try { return oh(a, h); } catch (e) {} };
        }
        if (ms.setPositionState) {
          var op = ms.setPositionState.bind(ms);
          ms.setPositionState = function (s) {
            var m = mc.active();
            mc.pos = (s && s.duration) ? { d: s.duration, p: s.position || 0, r: s.playbackRate || 1, t: now(), frozen: m ? m.paused : false } : null;
            post();
            try { return op(s); } catch (e) {}
          };
        }
        try {
          var proto = Object.getPrototypeOf(ms);
          ['metadata', 'playbackState'].forEach(function (k) {
            var d = Object.getOwnPropertyDescriptor(proto, k);
            if (d && d.get && d.set) {
              Object.defineProperty(ms, k, {
                configurable: true, enumerable: true,
                get: function () { return d.get.call(ms); },
                set: function (v) { d.set.call(ms, v); post(); }
              });
            }
          });
        } catch (e) {}
      }

      // ---------- помощники ----------
      function q(s, r) { try { return (r || document).querySelector(s); } catch (e) { return null; } }
      function qa(s, r) { try { return Array.prototype.slice.call((r || document).querySelectorAll(s)); } catch (e) { return []; } }
      function txt(el) { return el ? String(el.textContent || '').replace(/\s+/g, ' ').trim() : ''; }
      function norm(s) {
        return String(s || '').toLowerCase().replace(/ё/g, 'е')
          .replace(/\s[-–—]\s[^-–—]*(remaster|version|edit|live|mono|stereo)[^-–—]*$/i, ' ')
          .replace(/\([^)]*\)|\[[^\]]*\]/g, ' ')
          .replace(/\s(feat\.?|ft\.)\s.*$/i, ' ')
          .replace(/[^\p{L}\p{N}]+/gu, ' ').replace(/\s+/g, ' ').trim();
      }
      function words(s) { return norm(s).split(' ').filter(Boolean); }
      function artistOk(text, artist) {
        if (!artist) return true;
        var t = ' ' + norm(text) + ' ';
        var parts = String(artist).split(/,|&|;|\/|\sx\s|\sи\s|\sfeat\.?\s|\sft\.\s/i).map(norm).filter(Boolean);
        if (!parts.length) return true;
        return parts.some(function (p) { return t.indexOf(' ' + p + ' ') >= 0; });
      }
      function parseTime(s) {
        var m = String(s || '').match(/(\d+):(\d{2})(?::(\d{2}))?/);
        if (!m) return 0;
        return m[3] ? (+m[1]) * 3600 + (+m[2]) * 60 + (+m[3]) : (+m[1]) * 60 + (+m[2]);
      }
      function abs(h) { try { return h ? new URL(h, location.href).href : null; } catch (e) { return null; } }
      function bgUrl(el) {
        if (!el) return null;
        var b = (el.style && el.style.backgroundImage) || '';
        if (!b) { try { b = getComputedStyle(el).backgroundImage || ''; } catch (e) {} }
        var m = /url\(["']?(.*?)["']?\)/.exec(b);
        return m ? m[1] : null;
      }

      // Что играет — по полоске плеера на самой странице (если сайт не сообщил это системе)
      mc.domNow = function () {
        var r = { title: '', artist: '', art: null, link: null, dur: 0 };
        try {
          if (P === 'soundcloud') {
            var a = q('.playbackSoundBadge__titleLink');
            if (a) { r.title = a.getAttribute('title') || txt(q('span[aria-hidden="true"]', a)) || txt(a); r.link = abs(a.getAttribute('href')); }
            var u = q('.playbackSoundBadge__lightLink');
            if (u) r.artist = u.getAttribute('title') || txt(u);
            var bu = bgUrl(q('.playbackSoundBadge .sc-artwork span') || q('.playbackSoundBadge span.image__full'));
            if (bu) r.art = bu.replace(/-t\d+x\d+\./, '-t500x500.');
            var d = q('.playbackTimeline__duration span[aria-hidden="true"]') || q('.playbackTimeline__duration');
            if (d) r.dur = parseTime(txt(d));
          } else if (P === 'spotify') {
            var w = q('[data-testid="now-playing-widget"]');
            if (w) {
              var t = q('[data-testid="context-item-info-title"] a', w) || q('a[data-testid="context-item-link"]', w);
              if (t) {
                r.title = txt(t);
                var h = t.getAttribute('href') || '', mm = /spotify:track:([A-Za-z0-9]+)/.exec(decodeURIComponent(h));
                r.link = mm ? 'https://open.spotify.com/track/' + mm[1] : (/\/track\//.test(h) ? abs(h) : null);
              }
              var ar = qa('[data-testid="context-item-info-artist"]', w).map(txt).filter(Boolean);
              if (ar.length) r.artist = ar.join(', ');
              var im = q('img', w);
              if (im && im.src) r.art = im.src;
            }
            var dd = q('[data-testid="playback-duration"]');
            if (dd) r.dur = parseTime(txt(dd));
          } else if (P === 'yandex') {
            var bar = q('[class*="PlayerBarDesktop"]') || q('section[aria-label="Плеер"]') || q('[class*="PlayerBar_root"]');
            if (bar) {
              var tl = q('a[href*="/track/"]', bar);
              var names = qa('[class*="trackNameText"], [class*="Meta_title"]', bar).map(txt).filter(Boolean);
              if (tl) { r.title = tl.getAttribute('title') || txt(tl); r.link = abs(tl.getAttribute('href')); }
              else if (names.length) r.title = names[0];
              var al = qa('a[href*="/artist/"]', bar).map(txt).filter(Boolean);
              if (al.length) r.artist = al.join(', '); else if (names.length > 1) r.artist = names[1];
              var ii = q('img', bar);
              if (ii && ii.src && ii.src.indexOf('data:') !== 0) r.art = ii.src;
              var tc = q('[class*="timecode"], [class*="Timecode"]', bar);
              if (tc) { var pp = txt(tc).split('/'); if (pp.length > 1) r.dur = parseTime(pp[1]); }
            }
          } else if (P === 'vk') {
            var vt = q('.top_audio_player_title') || q('[class*="AudioPlayer__title"]');
            if (vt) {
              var s = txt(vt), sp = s.split(/\s[–—-]\s/);
              if (sp.length > 1) { r.artist = sp[0]; r.title = sp.slice(1).join(' - '); } else r.title = s;
            }
          }
        } catch (e) {}
        return r;
      };

      mc.active = function () {
        document.querySelectorAll('audio,video').forEach(track);
        var best = null;
        function score(x) { return (x.paused ? 0 : 4) + (x.duration > 0 ? 2 : 0) + (x.isConnected ? 1 : 0); }
        mc.media.forEach(function (m) { if (!best || score(m) > score(best)) best = m; });
        return best;
      };

      mc.state = function () {
        var m = mc.active();
        var md = ms && ms.metadata;
        var playing = m ? !m.paused : !!(ms && ms.playbackState === 'playing');
        var pos = 0, dur = 0;
        if (mc.pos) {
          pos = mc.pos.p + ((playing && !mc.pos.frozen) ? (now() - mc.pos.t) / 1000 * mc.pos.r : 0);
          dur = mc.pos.d;
          pos = Math.min(pos, dur);
        } else if (m) {
          pos = m.currentTime || 0;
          dur = isFinite(m.duration) ? m.duration : 0;
        }
        var art = null, bw = -1;
        if (md && md.artwork) {
          for (var i = 0; i < md.artwork.length; i++) {
            var a = md.artwork[i];
            var w = parseInt(String(a.sizes || '0').split('x')[0], 10) || 0;
            if (w > bw) { bw = w; art = a.src; }
          }
        }
        var title = md ? (md.title || '') : '', artist = md ? (md.artist || '') : '', album = md ? (md.album || '') : '';
        if (!title || !art || !dur || P === 'soundcloud') {
          var dn = mc.domNow();
          if (!title && dn.title) { title = dn.title; artist = artist || dn.artist; }
          if (!art && dn.art) art = dn.art;
          // У SoundCloud длина из полоски плеера точнее, чем у потока
          if (dn.dur && (!dur || (P === 'soundcloud' && !mc.pos))) dur = dn.dur;
        }
        return JSON.stringify({
          title: title, artist: artist, album: album, art: art, pos: pos, dur: dur,
          paused: !playing, ended: m ? !!m.ended : false,
          rate: mc.pos ? mc.pos.r : (m ? m.playbackRate : 1)
        });
      };

      var buttons = {
        nexttrack: ['[data-testid="control-button-skip-forward"]', '.skipControl__next', '.top_audio_player_next',
                    '.audio_page_player_next', '[aria-label="Следующая песня"]', '[aria-label*="Следующ"]', '[aria-label*="Next"]'],
        previoustrack: ['[data-testid="control-button-skip-back"]', '.skipControl__previous', '.top_audio_player_prev',
                        '.audio_page_player_prev', '[aria-label="Предыдущая песня"]', '[aria-label*="Предыдущ"]', '[aria-label*="Previous"]'],
        play: ['[data-testid="control-button-playpause"]', '.playControl', '.top_audio_player_play',
               '[aria-label="Воспроизведение"]', '[aria-label="Воспроизвести"]', '[aria-label="Play"]'],
        pause: ['[data-testid="control-button-playpause"]', '.playControl', '.top_audio_player_play',
                '[aria-label="Пауза"]', '[aria-label="Pause"]']
      };
      mc.cmd = function (a, arg) {
        var m = mc.active();
        if (a === 'play' && m && !m.paused) return 'already';
        if (a === 'pause' && m && m.paused) return 'already';
        var h = mc.handlers[a];
        if (typeof h === 'function') {
          try { var d = { action: a }; if (a === 'seekto') { d.seekTime = arg; d.fastSeek = false; } h(d); return 'handler'; } catch (e) {}
        }
        var sel = buttons[a] || [];
        for (var i = 0; i < sel.length; i++) { var b = q(sel[i]); if (b) { b.click(); return 'click'; } }
        if (m) {
          if (a === 'play') { m.play(); return 'media'; }
          if (a === 'pause') { m.pause(); return 'media'; }
          if (a === 'seekto') { m.currentTime = arg; return 'media'; }
        }
        return 'none';
      };
      mc.setVolume = function (v) { mc.volume = v; mc.media.forEach(function (m) { try { m.volume = v; } catch (e) {} }); };

      mc.link = function () {
        var dn = mc.domNow();
        if (dn.link) return dn.link;
        var md = ms && ms.metadata;
        var want = norm(md && md.title ? md.title : dn.title);
        if (want) {
          var links = qa('a[href*="/track/"], a[href*="/tracks/"]');
          for (var i = 0; i < links.length; i++) {
            if (norm(links[i].getAttribute('title') || txt(links[i])) === want) return abs(links[i].getAttribute('href'));
          }
        }
        return null;
      };

      // ---------- поиск точной кнопки «играть» для нужного трека ----------
      function playLike(b) {
        var l = ((b.getAttribute('aria-label') || '') + ' ' + (b.getAttribute('title') || '')).toLowerCase();
        if (/pause|пауз|нрав|like|добав|add|меню|menu|трейлер|trailer|more|ещё|еще|скач|share|подел|репост|repost|очеред|queue/.test(l)) return false;
        var c = String(typeof b.className === 'string' ? b.className : '');
        return /play|включ|воспр|слуш|игра/.test(l) || /sc-button-play|audio_row__play_btn|play_btn/.test(c);
      }
      function playButtonsIn(el) {
        return qa('button, [role="button"], a.sc-button-play, .audio_row__play_btn', el).filter(playLike);
      }
      function area(el) { var r = el.getBoundingClientRect(); return r.width * r.height; }
      var noise = ['by', 'playlist', 'track', 'трек', 'песня', 'исполнителя', 'исполнитель', 'от', 'album', 'альбом',
                   'single', 'сингл', 'explicit', 'e', 'play', 'включить', 'слушать'];
      // Подпись карточки — это «исполнитель + название» и ничего лишнего
      function cardMatches(label, want, artist) {
        var nl = ' ' + norm(label) + ' ', w = ' ' + want + ' ';
        var i = nl.indexOf(w);
        if (i < 0) return false;
        var rest = (nl.slice(0, i) + ' ' + nl.slice(i + w.length)).split(' ').filter(Boolean);
        var ok = words(artist).concat(noise);
        return rest.every(function (t) { return ok.indexOf(t) >= 0; }) && artistOk(label, artist);
      }

      mc.findPlay = function (title, artist) {
        var want = norm(title), path = location.pathname;
        if (!want) return null;
        // 1) страница самого трека: большая кнопка
        if (P === 'spotify' && /^\/track\//.test(path)) {
          var h1 = q('[data-testid="entityTitle"] h1') || q('section[data-testid="track-page"] h1');
          if (h1 && norm(txt(h1)) === want) {
            var b1 = q('section[data-testid="track-page"] [data-testid="action-bar-row"] button[data-testid="play-button"]')
                  || q('section[data-testid="track-page"] button[data-testid="play-button"]');
            if (b1) return b1;
          }
        }
        if (P === 'soundcloud') {
          var h2 = q('.fullListenHero h1.soundTitle__title') || q('.fullHero h1');
          if (h2 && norm(txt(h2)) === want) {
            var b2 = q('.fullListenHero .soundTitle__playButtonHero .sc-button-play') || q('.fullHero .sc-button-play');
            if (b2) return b2;
          }
        }
        // 2) кнопка, в подписи которой назван трек: «Включить трек «X» исполнителя Y» / «Play X by Y»
        var labelled = qa('button[aria-label], [role="button"][aria-label]').filter(function (b) {
          if (!playLike(b)) return false;
          var l = b.getAttribute('aria-label') || '';
          var m = /[«"“]([^»"”]+)[»"”]/.exec(l) || /^play\s+(.+?)\s+by\s+/i.exec(l);
          return m && norm(m[1]) === want && artistOk(l, artist);
        });
        if (labelled.length) return labelled[0];
        // 3) карточка трека с подписью «исполнитель название» (Яндекс) или «… by исполнитель» (SoundCloud)
        var cards = qa('[aria-label]').filter(function (el) {
          if (el.tagName === 'BUTTON' || el.tagName === 'A') return false;
          var l = el.getAttribute('aria-label') || '';
          return l.length < 240 && cardMatches(l, want, artist);
        }).sort(function (a, b) { return area(a) - area(b); });
        for (var i = 0; i < cards.length; i++) {
          var pb = playButtonsIn(cards[i]);
          if (pb.length) return pb[0];
        }
        // 4) название трека → ближайший блок, где есть исполнитель и ровно одна кнопка «играть»
        var titles = qa('a[href*="/track/"], a.soundTitle__title, .soundTitle__title, .audio_row__title_inner, [class*="title"], [class*="Title"]')
          .filter(function (el) { return norm(el.getAttribute('title') || txt(el)) === want; }).slice(0, 12);
        for (var j = 0; j < titles.length; j++) {
          var el = titles[j];
          for (var k = 0; k < 8 && el; k++) {
            el = el.parentElement;
            if (!el || el === document.body) break;
            var pbs = playButtonsIn(el);
            if (pbs.length === 1 && artistOk(txt(el), artist)) return pbs[0];
            if (pbs.length > 1) break;
            if (P === 'vk' && /audio_row/.test(String(el.className)) && artistOk(txt(el), artist)) return el;
          }
        }
        return null;
      };

      // Нажать найденную кнопку. Если её ничего не закрывает — просим программу нажать по-настоящему
      // (сайт видит это как нажатие пользователя), иначе нажимаем из скрипта.
      function press(el) {
        try { el.scrollIntoView({ block: 'center', inline: 'center' }); } catch (e) {}
        mc.target = el;
        var r = el.getBoundingClientRect();
        var x = r.left + r.width / 2, y = r.top + r.height / 2;
        var top = document.elementFromPoint(x, y);
        if (r.width > 2 && r.height > 2 && top && (top === el || el.contains(top) || top.contains(el))) {
          send({ ev: 'autoplay', r: 'press', x: x, y: y, vw: window.innerWidth, vh: window.innerHeight });
        } else {
          mc.pressTarget();
        }
      }
      mc.pressTarget = function () { var el = mc.target; if (el) { try { el.click(); } catch (e) {} } };
      function playingTitle() {
        var md = ms && ms.metadata;
        return md && md.title ? md.title : mc.domNow().title;
      }
      // Кнопка уже показывает «пауза»/«загрузка» — значит, нажатие сработало, ждём звук
      function pressedAlready(el) {
        if (!el || !el.isConnected) return false;
        var l = ((el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('title') || '') + ' ' + (typeof el.className === 'string' ? el.className : '')).toLowerCase();
        return /pause|пауз|buffering|loading|загруз/.test(l);
      }

      // Помощник: ждёт, пока на странице появится нужный трек, нажимает ровно его и следит, что он заиграл
      mc.autoplayStop = function () { if (mc.ap) { clearInterval(mc.ap.timer); mc.ap = null; } };
      mc.autoplayStart = function (title, artist, limit) {
        mc.autoplayStop();
        var ap = mc.ap = { t0: Date.now(), clicks: 0, last: 0, limit: limit || 15000, want: norm(title), el: null };
        function tick() {
          if (mc.ap !== ap) return;
          var m = mc.active(), playing = !!(m && !m.paused), cur = playingTitle();
          if (playing && cur && norm(cur) === ap.want) { mc.autoplayStop(); post(); return; }
          if (Date.now() - ap.t0 > ap.limit) { mc.autoplayStop(); send({ ev: 'autoplay', r: 'timeout', clicks: ap.clicks }); return; }
          if (ap.clicks > 0) {
            if (Date.now() - ap.last < 5000) return;          // после нажатия даём сайту время
            if (playing && !cur) return;                      // что-то заиграло, но название ещё не пришло
            if (pressedAlready(ap.el)) return;                // кнопка уже «пауза» — не жмём повторно
          }
          if (ap.clicks >= 3) return;
          var b = mc.findPlay(title, artist);
          if (b) { ap.el = b; press(b); ap.clicks++; ap.last = Date.now(); send({ ev: 'autoplay', r: 'click', clicks: ap.clicks }); }
        }
        ap.timer = setInterval(tick, 350);
        tick();
        return 'started';
      };

      mc.whoami = function () {
        var list = ['[data-testid="user-widget-link"]', '.header__userNavUsernameButton .truncate', '.header__userNavUsername',
                    '.top_profile_name', '[data-test-id="USER_NAME"]', '.user-account__name'];
        for (var i = 0; i < list.length; i++) {
          var el = q(list[i]);
          if (!el) continue;
          var t = (el.getAttribute('aria-label') || el.textContent || '').trim();
          if (t) return t;
        }
        return '';
      };
    })();
    """#
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
