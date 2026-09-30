import SwiftUI
import AppKit
import WebKit

@main
struct MuzykaOfflineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = PlayerModel.shared
    @StateObject private var artwork = ArtworkLoader.shared

    init() { Fonts.register() }

    var body: some Scene {
        Window("Музыка в офлайн", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(artwork)
                .frame(minWidth: 1080, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть музыку…") { model.openPanel() }.keyboardShortcut("o")
                Button("Добавить папку…") { model.openFolderPanel() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Новый плейлист…") { model.modal = .newPlaylist(addCurrent: false) }.keyboardShortcut("n")
                Divider()
                Button("Сохранить копию библиотеки…") { model.exportLibrary() }
                Button("Загрузить копию библиотеки…") { model.importLibrary() }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Настройки…") { model.openSettings(.look) }.keyboardShortcut(",")
            }
            CommandMenu("Воспроизведение") {
                Button("Играть / пауза") { model.togglePlay() }
                Button("Следующий трек") { model.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Предыдущий трек") { model.prev() }.keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("В любимые / убрать") { model.toggleFavorite() }.keyboardShortcut("d", modifiers: .command)
                Button("Весь текст") { model.toggleLyrics() }.keyboardShortcut("l", modifiers: .command)
            }
            CommandMenu("Разделы") {
                Button("Сейчас играет") { model.show(.stage) }.keyboardShortcut("1", modifiers: .command)
                Button("Мои файлы") { model.show(.library) }.keyboardShortcut("e", modifiers: .command)
                Button("Любимые") { model.show(.playlist(Playlist.favoritesID)) }.keyboardShortcut("2", modifiers: .command)
                Button("Подключить площадку…") { model.modal = .addAccount }.keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Темы и фоны") { model.openSettings(.look) }.keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Производительность") { model.openSettings(.performance) }.keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button(model.showSidebar ? "Скрыть меню" : "Показать меню") { model.showSidebar.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            KeyMonitor.install()
            WindowWatcher.install()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// При выходе сохраняем всё сразу: что играло и где, плейлисты.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { PlayerModel.shared.saveSession() }
        LibraryStore.flushNow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { PlayerModel.shared.add(urls: urls, force: true) }
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
        let m = PlayerModel.shared
        if typingSomewhere() { return false }
        if NSApp.keyWindow?.title.hasSuffix(": вход") == true { return false }
        if !e.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        if e.keyCode == 53 { m.escape(); return true }                // Esc
        if m.openAccountID != nil { return false }                     // на сайте площадки клавиши — сайту
        switch e.keyCode {
        case 49: m.togglePlay()                                   // пробел
        case 123: m.seek(by: -5)                                  // ←
        case 124: m.seek(by: 5)                                   // →
        case 126: m.setVolume(m.volume + 0.05)                    // ↑
        case 125: m.setVolume(m.volume - 0.05)                    // ↓
        case 99: m.showDebug.toggle()                             // F3
        default:
            let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
            if let n = Int(ch), (1...9).contains(n) { m.hotbar(n - 1); return true }
            switch ch {
            case "e", "у": m.toggleLibrary()
            case "l", "д": m.toggleLyrics()
            case "n", "т": m.next()
            case "b", "и": m.prev()
            case "r", "к": m.cycleRepeat()
            case "s", "ы": m.toggleShuffle()
            default: return false
            }
        }
        return true
    }
}
