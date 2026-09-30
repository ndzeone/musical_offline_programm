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
