import SwiftUI
import AppKit
import WebKit

/// Горячая клавиша: код клавиши (не зависит от раскладки) и модификаторы.
struct KeyBind: Equatable, Codable {
    var code: UInt16
    var mods: UInt   // NSEvent.ModifierFlags: ⌘ ⌥ ⌃ ⇧

    static let none = KeyBind(code: 0xFFFF, mods: 0)
    var isNone: Bool { code == 0xFFFF }

    static let modMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var name: String {
        if isNone { return "—" }
        let f = NSEvent.ModifierFlags(rawValue: mods)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + (KeyBind.names[code] ?? "#\(code)")
    }

    /// Названия клавиш по коду (раскладка US; русские буквы на тех же местах работают так же)
    static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`", 36: "↩", 48: "⇥", 49: "Пробел", 51: "⌫", 53: "Esc", 117: "⌦", 115: "Home", 119: "End",
        116: "PgUp", 121: "PgDn", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
        97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        82: "Num 0", 83: "Num 1", 84: "Num 2", 85: "Num 3", 86: "Num 4", 87: "Num 5", 88: "Num 6", 89: "Num 7", 91: "Num 8", 92: "Num 9",
    ]
}

/// Действия, которым можно назначить свою клавишу.
enum KeyAction: String, CaseIterable, Identifiable {
    case toggle, seekBack, seekFwd, volUp, volDown, next, prev, repeatMode, shuffle, favorite, lyrics, library, accounts, minimize, debug
    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggle: return "Пауза / играть"
        case .seekBack: return "Назад на 5 секунд"
        case .seekFwd: return "Вперёд на 5 секунд"
        case .volUp: return "Громче"
        case .volDown: return "Тише"
        case .next: return "Следующий трек"
        case .prev: return "Предыдущий трек"
        case .repeatMode: return "Повтор"
        case .shuffle: return "Перемешать"
        case .favorite: return "В любимые"
        case .lyrics: return "Весь текст и поиск"
        case .library: return "Мои файлы"
        case .accounts: return "Открыть площадку"
        case .minimize: return "Свернуть все окна площадок"
        case .debug: return "Отладка: источник, нагрузка, текст"
        }
    }

    var defaultBind: KeyBind {
        switch self {
        case .toggle: return KeyBind(code: 49, mods: 0)
        case .seekBack: return KeyBind(code: 123, mods: 0)
        case .seekFwd: return KeyBind(code: 124, mods: 0)
        case .volUp: return KeyBind(code: 126, mods: 0)
        case .volDown: return KeyBind(code: 125, mods: 0)
        case .next: return KeyBind(code: 45, mods: 0)
        case .prev: return KeyBind(code: 11, mods: 0)
        case .repeatMode: return KeyBind(code: 15, mods: 0)
        case .shuffle: return KeyBind(code: 1, mods: 0)
        case .favorite: return KeyBind(code: 3, mods: 0)
        case .lyrics: return KeyBind(code: 37, mods: 0)
        case .library: return KeyBind(code: 14, mods: 0)
        case .accounts: return KeyBind(code: 35, mods: 0)
        case .minimize: return KeyBind(code: 46, mods: 0)
        case .debug: return KeyBind(code: 99, mods: 0)
        }
    }
}

/// Свои клавиши хранятся в настройках; всё, что не меняли, — по умолчанию.
@MainActor
final class KeyBinds: ObservableObject {
    static let shared = KeyBinds()
    @Published private(set) var own: [String: KeyBind] = [:]
    @Published var capturing: KeyAction?

    private init() {
        if let d = UserDefaults.standard.data(forKey: "keyBinds"), let v = try? JSONDecoder().decode([String: KeyBind].self, from: d) { own = v }
    }

    func bind(_ a: KeyAction) -> KeyBind { own[a.rawValue] ?? a.defaultBind }

    func set(_ a: KeyAction, _ b: KeyBind) {
        // клавиша уже занята другим действием — там она снимается
        for x in KeyAction.allCases where x != a && !b.isNone && bind(x) == b { own[x.rawValue] = KeyBind.none }
        own[a.rawValue] = b
        save()
    }

    func reset() { own = [:]; save() }

    private func save() {
        if let d = try? JSONEncoder().encode(own) { UserDefaults.standard.set(d, forKey: "keyBinds") }
    }

    func action(for e: NSEvent) -> KeyAction? {
        let b = KeyBind(code: e.keyCode, mods: e.modifierFlags.intersection(KeyBind.modMask).rawValue)
        return KeyAction.allCases.first { bind($0) == b }
    }
}

/// Горячие клавиши. Не мешают печатать в полях и на сайтах площадок.
enum KeyMonitor {
    @MainActor static func install() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            MainActor.assumeIsolated { handle(e) } ? nil : e
        }
    }

    @MainActor
    private static func typingSomewhere() -> Bool {
        guard let r = NSApp.keyWindow?.firstResponder else { return false }
        if r is NSText { return true }
        var v = r as? NSView
        while let x = v {
            if x is WKWebView { return true }
            v = x.superview
        }
        return false
    }

    @MainActor
    private static func handle(_ e: NSEvent) -> Bool {
        let m = PlayerModel.shared, kb = KeyBinds.shared
        // ждём новую клавишу для действия
        if let a = kb.capturing {
            kb.capturing = nil
            if e.keyCode == 53 { return true }                              // Esc — отмена
            let mods = e.modifierFlags.intersection(KeyBind.modMask).rawValue
            kb.set(a, e.keyCode == 51 && mods == 0 ? KeyBind.none : KeyBind(code: e.keyCode, mods: mods))
            return true
        }
        if typingSomewhere() { return false }
        if NSApp.keyWindow?.title.hasSuffix(": вход") == true { return false }
        if e.keyCode == 53 && e.modifierFlags.intersection(KeyBind.modMask).isEmpty { m.escape(); return true }
        if m.openAccountID != nil { return false }                     // на сайте площадки клавиши — сайту
        if let a = kb.action(for: e) { run(a, m); return true }
        // 1–9 — кнопки хотбара в теме «Майнкрафт»
        if e.modifierFlags.intersection(KeyBind.modMask).isEmpty, let ch = e.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n) {
            m.hotbar(n - 1); return true
        }
        return false
    }

    @MainActor
    static func run(_ a: KeyAction, _ m: PlayerModel) {
        switch a {
        case .toggle: m.togglePlay()
        case .seekBack: m.seek(by: -5)
        case .seekFwd: m.seek(by: 5)
        case .volUp: m.setVolume(m.volume + 0.05)
        case .volDown: m.setVolume(m.volume - 0.05)
        case .next: m.next()
        case .prev: m.prev()
        case .repeatMode: m.cycleRepeat()
        case .shuffle: m.toggleShuffle()
        case .favorite: m.toggleFavorite()
        case .lyrics: m.toggleLyrics()
        case .library: m.toggleLibrary()
        case .accounts:
            if let id = m.activeWebID ?? m.lastWebAccount ?? m.accounts.first?.id { m.openAccount(id) } else { m.modal = .addAccount }
        case .minimize: m.minimizeAllSites()
        case .debug: m.showDebug.toggle()
        }
    }
}
