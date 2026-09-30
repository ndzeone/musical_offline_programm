import AppKit
import SwiftUI

/// Выпуск на GitHub.
struct ReleaseInfo: Equatable {
    let version: String
    let page: URL
    let dmg: URL?
    let notes: String
}

enum UpdateState: Equatable {
    case idle
    case checking
    case latest(Date)
    case available(ReleaseInfo)
    case downloading
    case installing
    case failed(String)

    var busy: Bool {
        switch self {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }
}

/// Обновления с GitHub: проверка последнего выпуска, скачивание .dmg и замена программы на новую.
enum Updates {
    static let repo = "ndzeone/musical_offline_programm"
    static let latestAPI = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!

    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// 1 — a новее b, −1 — старее, 0 — одинаковые. «v2.10.1» и «2.4» тоже понимает.
    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(whereSeparator: { $0 == "." || $0 == "-" })
                .map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q ? 1 : -1 }
        }
        return 0
    }

    private struct GHRelease: Decodable {
        let tag_name: String
        let html_url: String?
        let body: String?
        let assets: [GHAsset]
    }
    private struct GHAsset: Decodable {
        let name: String
        let browser_download_url: String
    }

    static func fetchLatest() async throws -> ReleaseInfo {
        var req = URLRequest(url: latestAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MuzykaOffline/\(current) (Mac)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw NSError(domain: "Updates", code: code, userInfo: [NSLocalizedDescriptionKey:
                code == 403 ? "GitHub временно ограничил проверки, попробую позже" : "GitHub не ответил (\(code))"])
        }
        let r = try JSONDecoder().decode(GHRelease.self, from: data)
        let dmg = r.assets.first { $0.name.hasSuffix("-macOS.dmg") }.flatMap { URL(string: $0.browser_download_url) }
        return ReleaseInfo(version: r.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                           page: URL(string: r.html_url ?? "") ?? releasesPage, dmg: dmg, notes: r.body ?? "")
    }

    /// Заметки к выпуску без разметки — первые строки.
    static func plainNotes(_ md: String) -> String {
        md.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n").compactMap { raw -> String? in
            var l = raw.trimmingCharacters(in: .whitespaces)
            while l.hasPrefix("#") { l.removeFirst() }
            l = l.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "|", with: " ").trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
            if l.isEmpty || l.allSatisfy({ "-: ".contains($0) }) { return nil }
            return l
        }.prefix(8).joined(separator: "\n")
    }

    /// Скачать файл во временную папку (без пометки «из интернета» — URLSession её не ставит).
    static func download(_ url: URL, into dir: URL) async throws -> URL {
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.setValue("MuzykaOffline/\(current) (Mac)", forHTTPHeaderField: "User-Agent")
        let (tmp, resp) = try await URLSession.shared.download(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw err("Не получилось скачать обновление") }
        let dst = dir.appendingPathComponent(url.lastPathComponent.isEmpty ? "update.dmg" : url.lastPathComponent)
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.moveItem(at: tmp, to: dst)
        return dst
    }

    static func workDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("muzyka-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Достаёт программу из образа, кладёт рядом с текущей и запускает маленький сценарий:
    /// он дождётся закрытия программы (waitPID), поменяет старую на новую и откроет её.
    /// Если что-то пошло не так, старая программа возвращается на место.
    @discardableResult
    static func install(dmg: URL, replacing app: URL, work: URL, waitPID: Int32, relaunch: Bool) throws -> URL {
        let fm = FileManager.default
        guard app.pathExtension == "app" else { throw err("Программа лежит в необычном месте") }
        let mnt = work.appendingPathComponent("mnt")
        try fm.createDirectory(at: mnt, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-mountpoint", mnt.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mnt.path, "-force"]) }
        guard let src = try fm.contentsOfDirectory(at: mnt, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
            throw err("В образе нет программы")
        }
        let staged = app.deletingLastPathComponent().appendingPathComponent(".\(app.deletingPathExtension().lastPathComponent)-new.app")
        try? fm.removeItem(at: staged)
        try run("/usr/bin/ditto", [src.path, staged.path])
        let exe = staged.appendingPathComponent("Contents/MacOS/MuzykaOffline")
        guard fm.isExecutableFile(atPath: exe.path) else {
            try? fm.removeItem(at: staged)
            throw err("Новая программа повреждена")
        }
        let old = app.deletingLastPathComponent().appendingPathComponent(".\(app.deletingPathExtension().lastPathComponent)-old.app")
        let lsreg = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        #!/bin/sh
        APP=\(q(app.path))
        NEW=\(q(staged.path))
        OLD=\(q(old.path))
        i=0
        while kill -0 \(waitPID) 2>/dev/null && [ $i -lt 600 ]; do sleep 0.2; i=$((i+1)); done
        rm -rf "$OLD"
        if mv "$APP" "$OLD"; then
          if mv "$NEW" "$APP"; then rm -rf "$OLD"; else mv "$OLD" "$APP"; fi
        fi
        \(lsreg) -f "$APP" >/dev/null 2>&1
        \(relaunch ? "open \"$APP\"" : ":")
        rm -rf \(q(work.path))
        """
        let sh = work.appendingPathComponent("install.sh")
        try script.write(to: sh, atomically: true, encoding: .utf8)
        // Сценарий живёт дольше программы: запускаем его отдельно
        try run("/bin/sh", ["-c", "nohup /bin/sh \(q(sh.path)) >/dev/null 2>&1 &"])
        return sh
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else { throw err("\((tool as NSString).lastPathComponent): \(text.prefix(200))") }
        return text
    }

    static func err(_ s: String) -> NSError { NSError(domain: "Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }
}

/// Новые функции помечаются «Новое» на 240 минут после первого запуска версии, где они появились.
enum NewFeatures {
    static let minutes: Double = 240
    static let list: [String: String] = ["updates": "2.4.0", "roundSidebar": "2.4.0", "liquidGlass": "2.4.0",
                                          "tabs": "2.5.0", "profile": "2.5.0", "perf": "2.5.0", "keys": "2.5.0", "scan": "2.5.0", "vinyl": "2.5.0"]

    static func markLaunch() {
        let k = "seen-" + Updates.current
        if UserDefaults.standard.object(forKey: k) == nil { UserDefaults.standard.set(Date(), forKey: k) }
    }

    static func isNew(_ id: String) -> Bool {
        guard let v = list[id], let t = UserDefaults.standard.object(forKey: "seen-" + v) as? Date else { return false }
        return Date().timeIntervalSince(t) < minutes * 60
    }

    static var any: Bool { list.keys.contains(where: isNew) }
}

struct NewBadge: View {
    @Environment(\.theme) private var theme
    let feature: String

    var body: some View {
        if NewFeatures.isNew(feature) {
            if theme.pixel {
                MCText("НОВОЕ", size: 6, color: 0x3F3F15, shadow: false)
                    .padding(.horizontal, 5).padding(.vertical, 4)
                    .background(Color(hex: 0xFFFF55))
            } else {
                Text("Новое").font(theme.body(10)).foregroundStyle(Color(hex: theme.onAccent))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                                              startPoint: .leading, endPoint: .trailing)))
                    .shadow(color: Color(hex: theme.accent, alpha: 0.5), radius: 6)
            }
        }
    }
}

/// Жидкое стекло: на macOS 26 — настоящее системное, раньше — матовое стекло с бликом.
struct LiquidGlass<S: InsettableShape>: View {
    let shape: S
    var tint: Color
    /// Светлая тема: светлое стекло (иначе система рисует его тёмным, и тёмный текст не читается)
    var light = false

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                ZStack {
                    if light { shape.fill(Color.white.opacity(0.28)) }
                    Color.clear.glassEffect(.regular.tint(light ? Color.white.opacity(0.42) : tint), in: shape)
                }
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(light ? Color.white.opacity(0.5) : tint))
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(light ? 0.45 : 0.2), .white.opacity(light ? 0.1 : 0.02)], startPoint: .top, endPoint: .bottom)))
            }
        }
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(light ? 0.95 : 0.6), .white.opacity(light ? 0.4 : 0.08)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .environment(\.colorScheme, light ? .light : .dark)
    }
}

private struct LiquidGlassKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var liquidGlass: Bool {
        get { self[LiquidGlassKey.self] }
        set { self[LiquidGlassKey.self] = newValue }
    }
}
