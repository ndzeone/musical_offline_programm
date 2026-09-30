import SwiftUI
import WebKit

/// Профиль «Музыка в офлайн»: на всех устройствах видно, какие сервисы уже подключены.
/// На сервер уходит только почта, имя, пароль профиля и отметки «есть / нет активации».
/// Пароли и вход в Spotify, Яндекс Музыку, VK и SoundCloud остаются на этом Mac.
struct ProfileUser: Codable, Equatable {
    var id: Int
    var email: String
    var name: String
}

struct ServiceMark: Codable, Equatable {
    var active: Bool
    var devices: [String]
    var updated: String?
}

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    static let configURL = URL(string: "https://raw.githubusercontent.com/ndzeone/musical_offline_programm/main/server.json")!
    static let device = "Mac"

    private struct Saved: Codable {
        var token = ""
        var user: ProfileUser?
        var services: [String: ServiceMark] = [:]
        var syncedAt: Date?
        var api = ""
        var apiAt: Date?
    }

    @Published private(set) var user: ProfileUser?
    @Published private(set) var services: [String: ServiceMark] = [:]
    @Published private(set) var syncedAt: Date?
    @Published var busy = false
    @Published var error = ""
    /// Вход в площадки на этом Mac (по cookie каждого аккаунта)
    @Published private(set) var here: [Platform: Bool] = [:]
    private var saved = Saved()

    var signedIn: Bool { !saved.token.isEmpty && user != nil }
    var ownServer: String {
        get { UserDefaults.standard.string(forKey: "syncServer") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespaces), forKey: "syncServer"); saved.api = ""; persist() }
    }

    private static var file: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MusicCraft", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("profile.json")
    }

    private init() {
        if let d = try? Data(contentsOf: Self.file), let s = try? JSONDecoder().decode(Saved.self, from: d) { saved = s }
        user = saved.user
        services = saved.services
        syncedAt = saved.syncedAt
    }

    private func persist() {
        saved.user = user
        saved.services = services
        saved.syncedAt = syncedAt
        guard let d = try? JSONEncoder().encode(saved) else { return }
        try? d.write(to: Self.file, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.file.path)
    }

    func start() {
        Task {
            await refreshHere()
            if signedIn { await refresh(); await sync() }
        }
    }

    // MARK: Адрес сервера

    private func api() async throws -> URL {
        let own = ownServer
        var s = own
        if s.isEmpty {
            if !saved.api.isEmpty, let at = saved.apiAt, Date().timeIntervalSince(at) < 12 * 3600 {
                s = saved.api
            } else {
                var req = URLRequest(url: Self.configURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                req.setValue("MuzykaOffline/\(Updates.current) (Mac)", forHTTPHeaderField: "User-Agent")
                if let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let a = o["api"] as? String, !a.isEmpty {
                    saved.api = a
                    saved.apiAt = Date()
                    persist()
                }
                s = saved.api
            }
        }
        guard let u = URL(string: s), let sc = u.scheme, sc == "https" || u.host == "localhost" || u.host == "127.0.0.1" else {
            throw err(s.isEmpty ? "Сервер профилей ещё не подключён. Скоро заработает!" : "Сервер должен работать по https")
        }
        return u
    }

    private func call(_ action: String, _ body: [String: Any]?, get: Bool = false) async throws -> [String: Any] {
        let base = try await api()
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "action", value: action)]
        var req = URLRequest(url: c.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.httpMethod = get ? "GET" : "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("MuzykaOffline/\(Updates.current) (Mac)", forHTTPHeaderField: "User-Agent")
        if !saved.token.isEmpty {
            req.setValue("Bearer " + saved.token, forHTTPHeaderField: "Authorization")
            req.setValue(saved.token, forHTTPHeaderField: "X-Auth-Token")
        }
        if let body, !get { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) } catch { throw err("Нет связи с сервером профилей") }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if code == 401 && action != "login" { forget(); throw err("Вход устарел — войди в профиль снова") }
        if code >= 400 || (o["ok"] as? Bool) == false { throw err(o["error"] as? String ?? "Сервер ответил ошибкой \(code)") }
        return o
    }

    private func accept(_ o: [String: Any]) {
        if let t = o["token"] as? String { saved.token = t }
        if let u = o["user"], let d = try? JSONSerialization.data(withJSONObject: u), let v = try? JSONDecoder().decode(ProfileUser.self, from: d) { user = v }
        if let s = o["services"], let d = try? JSONSerialization.data(withJSONObject: s), let v = try? JSONDecoder().decode([String: ServiceMark].self, from: d) { services = v }
        persist()
    }

    private func err(_ s: String) -> NSError { NSError(domain: "Profile", code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }

    private func run(_ f: @escaping () async throws -> Void) async -> Bool {
        busy = true
        error = ""
        defer { busy = false }
        do { try await f(); return true } catch { self.error = error.localizedDescription; return false }
    }

    // MARK: Действия

    @discardableResult
    func register(email: String, name: String, password: String, agree: Bool) async -> Bool {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard e.contains("@"), e.contains(".") else { error = "Проверь почту"; return false }
        guard password.count >= 8 else { error = "Пароль — от 8 символов"; return false }
        guard agree else { error = "Нужно согласие с условиями хранения данных"; return false }
        let ok = await run {
            let o = try await self.call("register", ["email": e, "name": name, "password": password, "device": Self.device, "agree": true])
            self.accept(o)
        }
        if ok { await sync() }
        return ok
    }

    @discardableResult
    func login(email: String, password: String) async -> Bool {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard e.contains("@"), !password.isEmpty else { error = "Введи почту и пароль"; return false }
        let ok = await run {
            let o = try await self.call("login", ["email": e, "password": password, "device": Self.device])
            self.accept(o)
        }
        if ok { await sync() }
        return ok
    }

    func logout() async {
        if !saved.token.isEmpty { _ = try? await call("logout", [:]) }
        forget()
    }

    @discardableResult
    func remove(password: String) async -> Bool {
        let ok = await run { _ = try await self.call("delete", ["password": password]) }
        if ok { forget() }
        return ok
    }

    func refresh() async {
        guard signedIn else { return }
        do { accept(try await call("me", nil, get: true)) } catch { self.error = error.localizedDescription }
    }

    func forget() {
        saved.token = ""
        user = nil
        services = [:]
        syncedAt = nil
        persist()
    }

    /// Отметки этого Mac → на сервер (только «активирован / нет»)
    func sync() async {
        await refreshHere()
        guard signedIn else { return }
        var marks: [String: Bool] = [:]
        for p in Platform.allCases { marks[p.rawValue] = here[p] ?? false }
        do {
            let o = try await call("services", ["device": Self.device, "services": marks])
            accept(o)
            syncedAt = Date()
            persist()
        } catch { self.error = error.localizedDescription }
    }

    /// Вход в каждую площадку — по cookie, которые появляются только после входа (у каждого аккаунта своё хранилище)
    func refreshHere() async {
        var out: [Platform: Bool] = [:]
        for a in PlayerModel.shared.accounts {
            if out[a.platform] == true { continue }
            if let s = PlayerModel.shared.session(a.id), let l = s.loggedIn { if l { out[a.platform] = true }; continue }
            let store = WKWebsiteDataStore(forIdentifier: a.id)
            let cookies: [HTTPCookie] = await withCheckedContinuation { c in store.httpCookieStore.getAllCookies { c.resume(returning: $0) } }
            if cookies.contains(where: { a.platform.isLoginCookie($0) }) { out[a.platform] = true }
        }
        here = out
    }

    /// Для экрана: вход здесь / активирован на другом устройстве / нет
    func status(_ p: Platform) -> (on: Bool, text: String) {
        let s = services[p.rawValue], mine = here[p] == true
        if mine {
            let others = (s?.devices ?? []).filter { $0 != Self.device }
            return (true, others.isEmpty ? "на этом Mac" : "на этом Mac и ещё: " + others.joined(separator: ", "))
        }
        if let s, s.active { return (true, "на устройствах: " + s.devices.joined(separator: ", ")) }
        return (false, "нигде не подключён")
    }
}
