import SwiftUI
import UniformTypeIdentifiers

// MARK: - Корень: боковое меню, страница, плеер снизу

struct RootView: View {
    @EnvironmentObject var m: PlayerModel
    @State private var dropping = false

    var body: some View {
        let theme = m.themeValue
        ZStack {
            SceneView(background: m.background, paused: m.openAccountID != nil).ignoresSafeArea()
            if theme.id != .kitty {
                LinearGradient(colors: [.black.opacity(0.3), .clear, .clear, .black.opacity(0.18)],
                               startPoint: .leading, endPoint: .trailing)
                    .ignoresSafeArea().allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                if m.showSidebar {
                    Sidebar().frame(width: 240).padding(m.sidebarRounded ? Self.floating : EdgeInsets())
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    SidebarRail().frame(width: 64).padding(m.sidebarRounded ? Self.floating : EdgeInsets()).transition(.opacity)
                }
                VStack(spacing: 0) {
                    ZStack {
                        PageHost()
                        ForEach(m.loadedSessions, id: \.self) { id in
                            if let s = m.session(id) {
                                AccountBrowser(session: s, open: m.openAccountID == id)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    if theme.pixel {
                        HUD().padding(.bottom, 12)
                    } else {
                        PlayerBar().padding(.horizontal, Layout.side).padding(.bottom, Layout.bottom)
                    }
                }
            }

            ToastView()
            if m.showDebug { DebugOverlay() }
            if let md = m.modal { ModalHost(modal: md).transition(.opacity) }
            if dropping { DropOverlay() }
        }
        .environment(\.theme, theme)
        .environment(\.visual, m.visual)
        .environment(\.liquidGlass, m.liquidGlass)
        .animation(.easeOut(duration: 0.18), value: m.modal)
        .animation(.easeOut(duration: 0.2), value: m.page)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: m.showSidebar)
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            handleDrop(providers)
            return true
        }
        .onAppear { m.start() }
    }

    /// Закруглённое меню — отдельная карточка с отступом от краёв окна
    static let floating = EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 0)

    private func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let sorted = urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            MainActor.assumeIsolated { PlayerModel.shared.add(urls: sorted) }
        }
    }
}

struct PageHost: View {
    @EnvironmentObject var m: PlayerModel

    var body: some View {
        switch m.page {
        case .stage, .account:
            Stage().padding(.horizontal, Layout.side).padding(.top, Layout.top).padding(.bottom, 10)
        case .library:
            LibraryPage().pagePadding()
        case .playlist(let id):
            PlaylistPage(id: id).pagePadding()
        case .settings:
            SettingsPage().pagePadding()
        }
    }
}

extension View {
    func pagePadding() -> some View { padding(.horizontal, Layout.side).padding(.top, Layout.top).padding(.bottom, 12) }
}

/// Общие отступы, чтобы края страниц, браузера и плеера совпадали.
enum Layout {
    static let side: CGFloat = 16
    static let top: CGFloat = 40
    static let bottom: CGFloat = 14
}

// MARK: - Боковое меню

struct Sidebar: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: AppLogo.image).resizable().frame(width: 30, height: 30)
                if theme.pixel {
                    MCText("МУЗЫКА\nВ ОФЛАЙН", size: 7, color: 0xFFFFFF)
                } else {
                    Text("Музыка\nв офлайн").font(theme.title(13)).lineSpacing(0)
                        .foregroundStyle(Color(hex: theme.text))
                }
                Spacer(minLength: 0)
                TIconButton("sidebar.left", size: 28, tip: "Свернуть меню") { m.showSidebar = false }
            }
            .padding(.top, Layout.top - 6).padding(.leading, SidebarRow.hPad).padding(.trailing, 4).padding(.bottom, 14)

            Scrolling {
                SidebarContent().padding(.bottom, 10)
            }

            SidebarRow(symbol: "gearshape.fill", title: "Настройки", selected: m.page == .settings, dot: m.settingsDot) {
                m.toggleSettings()
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, Layout.bottom)
        .background(SidebarBackground())
    }
}

struct SidebarBackground: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    @Environment(\.visual) private var visual

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: m.sidebarRounded ? (theme.pixel ? 14 : 22) : 0, style: .continuous)
        if m.sidebarRounded {
            fill(shape)
                .overlay(shape.strokeBorder(border, lineWidth: theme.pixel ? 2 : 1))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        } else {
            fill(shape)
                .overlay(alignment: .trailing) { edge }
                .ignoresSafeArea()
        }
    }

    @ViewBuilder private func fill(_ shape: RoundedRectangle) -> some View {
        if m.liquidGlass {
            LiquidGlass(shape: shape, tint: theme.pixel ? Color.black.opacity(0.35) : Color(hex: theme.panel, alpha: 0.25))
        } else if theme.pixel {
            shape.fill(Color(hex: 0x141414, alpha: 0.72))
        } else {
            ZStack {
                if visual.glass { shape.fill(.ultraThinMaterial) }
                shape.fill(Color(hex: theme.panel, alpha: visual.glass ? theme.panelAlpha * 0.8 : min(0.94, theme.panelAlpha + 0.1)))
            }
        }
    }

    private var border: Color {
        if theme.pixel { return Color(hex: 0x5A5A5A) }
        return m.liquidGlass ? .white.opacity(0.3) : Color(hex: theme.border, alpha: 0.3)
    }

    @ViewBuilder private var edge: some View {
        if theme.pixel { Color(hex: 0x5A5A5A).frame(width: 2) } else { Color(hex: theme.border, alpha: 0.18).frame(width: 1) }
    }
}

/// Пункты меню отдельно: так их удобно рисовать и в проверочных снимках.
struct SidebarContent: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SidebarHeader(title: "Музыка")
            SidebarRow(symbol: "waveform", title: "Сейчас играет", selected: m.page == .stage,
                       playing: m.isPlaying) { m.show(.stage) }
            SidebarRow(symbol: "folder.fill", title: "Мои файлы", count: m.tracks.count,
                       selected: m.page == .library) { m.show(.library) }
            SidebarRow(symbol: "heart.fill", title: "Любимые", count: m.favorites.items.count,
                       selected: m.page == .playlist(Playlist.favoritesID)) { m.show(.playlist(Playlist.favoritesID)) }

            SidebarHeader(title: "Плейлисты", plusTip: "Новый плейлист") { m.modal = .newPlaylist(addCurrent: false) }
                .padding(.top, 12)
            ForEach(m.userPlaylists) { p in
                SidebarRow(symbol: "music.note.list", title: p.name, count: p.items.count,
                           selected: m.page == .playlist(p.id), playing: m.queue?.playlistID == p.id && m.isPlaying) {
                    m.show(.playlist(p.id))
                }
                .contextMenu {
                    Button("Слушать") { m.playPlaylist(p.id) }
                    Button("Вперемешку") { m.playPlaylist(p.id, shuffled: true) }
                    Button("Переименовать…") { PlaylistDialogs.rename(p) }
                    Divider()
                    Button("Удалить плейлист…") { PlaylistDialogs.remove(p) }
                }
            }
            if m.userPlaylists.isEmpty {
                SidebarRow(symbol: "plus.square.dashed", title: "Создать плейлист", dim: true) {
                    m.modal = .newPlaylist(addCurrent: false)
                }
            }

            SidebarHeader(title: "Аккаунты", plusTip: "Подключить площадку") { m.modal = .addAccount }
                .padding(.top, 12)
            ForEach(m.accounts) { a in
                AccountRow(account: a)
            }
            SidebarRow(symbol: "plus.circle.fill", title: m.accounts.isEmpty ? "Подключить площадку" : "Ещё аккаунт",
                       dim: true) { m.modal = .addAccount }
        }
    }
}

struct AccountRow: View {
    @EnvironmentObject var m: PlayerModel
    let account: Account

    var body: some View {
        let s = m.session(account.id)
        let playing = m.activeWebID == account.id && m.isPlaying
        SidebarRow(platform: account.platform, title: account.name, selected: m.openAccountID == account.id,
                   playing: playing, check: s?.loggedIn == true, sleeping: s == nil) {
            if m.openAccountID == account.id { m.closeBrowser() } else { m.openAccount(account.id) }
        }
        .contextMenu {
            Button("Открыть") { m.openAccount(account.id) }
            Button("Переименовать…") { AccountDialogs.rename(account) }
            Button("Обновить страницу") { m.reloadAccount(account.id) }
            if s != nil && m.activeWebID != account.id {
                Button("Выгрузить из памяти") { m.unloadSession(account.id) }
            }
            Divider()
            Button("Выйти и удалить…") { AccountDialogs.remove(account) }
        }
    }
}

/// Заголовок раздела в меню: подпись на линии значков пунктов и «+» над столбцом значков справа.
struct SidebarHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    var plusTip: String?
    var plus: (() -> Void)?
    @State private var hover = false

    init(title: String, plusTip: String? = nil, plus: (() -> Void)? = nil) {
        self.title = title; self.plusTip = plusTip; self.plus = plus
    }

    var body: some View {
        HStack(spacing: 0) {
            SectionLabel(text: title, onPanel: false)
            Spacer(minLength: 0)
            if let plus {
                Button(action: plus) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: theme.pixel ? 0xFFFF55 : theme.text, alpha: hover ? 1 : 0.8))
                        .frame(width: SidebarRow.trailingSlot, height: 16)
                        .background {
                            Circle().fill(Color(hex: theme.pixel ? 0xFFFFFF : theme.text, alpha: hover ? 0.14 : 0))
                                .frame(width: 24, height: 24)
                        }
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(PressStyle())
                .onHover { hover = $0 }
                .tip(plusTip ?? "", offset: -30)
            }
        }
        .padding(.horizontal, SidebarRow.hPad)
        .frame(height: 22)
        .padding(.bottom, 2)
    }
}

struct SidebarRow: View {
    static let hPad: CGFloat = 10
    static let trailingSlot: CGFloat = 16

    @Environment(\.theme) private var theme
    var symbol: String?
    var platform: Platform?
    let title: String
    var count: Int?
    var selected = false
    var playing = false
    var check = false
    var sleeping = false
    var dim = false
    var dot = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon.frame(width: 20, height: 20)
                label.frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if playing {
                        slot(Image(systemName: "waveform").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: textColor))
                            .symbolEffect(.variableColor.iterative, isActive: playing))
                    }
                    if check {
                        slot(Image(systemName: "checkmark.seal.fill").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: selected ? textColor : 0x3DDC84)))
                            .help("Вход выполнен")
                    }
                    if dot {
                        slot(Circle().fill(Color(hex: selected ? textColor : (theme.pixel ? 0x80FF20 : theme.accent))).frame(width: 8, height: 8))
                            .help("Есть новое")
                    }
                    if sleeping {
                        slot(Image(systemName: "moon.zzz.fill").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: textColor, alpha: 0.45)))
                            .help("Выгружен из памяти, загрузится при нажатии")
                    }
                    if let count, count > 0 {
                        Group {
                            if theme.pixel { MCText("\(count)", size: 7, color: 0xB4B4B4) } else {
                                Text("\(count)").font(theme.body(11).monospacedDigit())
                                    .foregroundStyle(Color(hex: textColor, alpha: 0.6))
                            }
                        }
                        .frame(minWidth: Self.trailingSlot, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, Self.hPad)
            .frame(height: 34)
            .background { background }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
    }

    private func slot<V: View>(_ v: V) -> some View {
        v.frame(width: Self.trailingSlot, height: 16)
    }

    private var textColor: UInt32 {
        if theme.pixel { return 0xFFFFFF }
        return selected ? theme.onAccent : theme.text
    }

    @ViewBuilder private var icon: some View {
        if let platform {
            PlatformBadge(platform: platform, size: 20)
        } else if let symbol {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(hex: textColor, alpha: dim ? 0.6 : 0.95))
        }
    }

    @ViewBuilder private var label: some View {
        if theme.pixel {
            MCText(title, size: 8, color: hover ? 0xFFFFA0 : (dim ? 0xB4B4B4 : 0xFFFFFF)).lineLimit(1)
        } else {
            Text(title.precomposedStringWithCanonicalMapping).font(theme.body(13)).lineLimit(1)
                .foregroundStyle(Color(hex: textColor, alpha: dim ? 0.65 : 1))
        }
    }

    @ViewBuilder private var background: some View {
        if theme.pixel {
            if selected { BevelBox(fill: 0x4F8A28, light: 0x8FD35A, dark: 0x2E5616) }
            else if hover { BevelBox(fill: 0x5C6394, light: 0x8F99D1, dark: 0x3C4170) }
        } else if selected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                     startPoint: .leading, endPoint: .trailing))
        } else if hover {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: theme.text, alpha: 0.09))
        }
    }
}

/// Свёрнутое меню: одни значки.
struct SidebarRail: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            TIconButton("sidebar.left", size: 34, tip: "Показать меню") { m.showSidebar = true }
                .padding(.top, 40)
            rail("waveform", m.page == .stage, "Сейчас играет") { m.show(.stage) }
            rail("folder.fill", m.page == .library, "Мои файлы") { m.show(.library) }
            rail("heart.fill", m.page == .playlist(Playlist.favoritesID), "Любимые") { m.show(.playlist(Playlist.favoritesID)) }
            ForEach(m.accounts) { a in
                Button { m.openAccount(a.id) } label: {
                    PlatformBadge(platform: a.platform, size: 28)
                        .overlay {
                            if m.openAccountID == a.id {
                                RoundedRectangle(cornerRadius: theme.pixel ? 0 : 9).strokeBorder(Color.white, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(PressStyle())
                .tip(a.name, offset: -34)
            }
            Spacer()
            rail("gearshape.fill", m.page == .settings, "Настройки") { m.toggleSettings() }
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(SidebarBackground())
    }

    private func rail(_ s: String, _ on: Bool, _ tip: String, _ a: @escaping () -> Void) -> some View {
        TIconButton(s, size: 36, active: on, tip: tip, action: a)
    }
}

enum AppLogo {
    static let image: NSImage = NSImage(cgImage: ArtKit.appIcon(size: 128), size: NSSize(width: 64, height: 64))
}

enum AccountDialogs {
    @MainActor static func rename(_ a: Account) {
        let alert = NSAlert()
        alert.messageText = "Название аккаунта"
        alert.informativeText = a.platform.title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = a.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn { PlayerModel.shared.renameAccount(a.id, field.stringValue) }
    }

    @MainActor static func remove(_ a: Account) {
        let alert = NSAlert()
        alert.messageText = "Выйти из «\(a.name)» и удалить?"
        alert.informativeText = "Вход в \(a.platform.title) для этого аккаунта будет стёрт из приложения. С самим аккаунтом на сайте ничего не случится."
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        if alert.runModal() == .alertFirstButtonReturn { PlayerModel.shared.removeAccount(a.id) }
    }
}

enum PlaylistDialogs {
    @MainActor static func rename(_ p: Playlist) {
        let alert = NSAlert()
        alert.messageText = "Название плейлиста"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = p.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn { PlayerModel.shared.renamePlaylist(p.id, field.stringValue) }
    }

    @MainActor static func remove(_ p: Playlist) {
        let alert = NSAlert()
        alert.messageText = "Удалить плейлист «\(p.name)»?"
        alert.informativeText = "Сами треки и файлы не удалятся."
        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")
        if alert.runModal() == .alertFirstButtonReturn { PlayerModel.shared.deletePlaylist(p.id) }
    }
}

// MARK: - Сцена: текст и обложка

struct Stage: View {
    @EnvironmentObject var m: PlayerModel

    var body: some View {
        if let np = m.nowPlaying {
            GeometryReader { g in
                let W = g.size.width, H = g.size.height
                switch m.stageLayout {
                case .side:
                    let side = min(max(min(W * 0.28, H * 0.56), 200), 420) * m.coverSize.factor
                    HStack(alignment: .center, spacing: max(36, min(80, W * 0.05))) {
                        LyricsColumn(np: np)
                            .frame(maxWidth: 860, maxHeight: .infinity)
                        CoverColumn(np: np, size: side)
                            .frame(width: side * 1.34)
                    }
                    .frame(maxWidth: min(W, 1420))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .center:
                    let side = min(max(H * 0.3, 150), 280) * m.coverSize.factor
                    VStack(spacing: 18) {
                        CoverColumn(np: np, size: side, compact: true)
                        LyricsColumn(np: np, centered: true)
                            .frame(maxWidth: 900)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .lyrics:
                    VStack(spacing: 10) {
                        NowLine(np: np)
                        LyricsColumn(np: np, centered: true, big: true)
                            .frame(maxWidth: 1100)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            Welcome()
        }
    }
}

/// Маленькая строка «исполнитель — название» над текстом (раскладка «Только текст»).
struct NowLine: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let np: NowPlaying

    var body: some View {
        HStack(spacing: 10) {
            if let a = m.nowArtwork {
                Image(nsImage: a).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: theme.pixel ? 0 : 8, style: .continuous))
            }
            TText((np.artist.isEmpty ? "" : np.artist + " — ") + np.title, size: 14, alpha: 0.85).lineLimit(1)
        }
    }
}

/// Текст песни. Номер текущей строки ищем ~12 раз в секунду, весь столбец перерисовываем
/// только когда строка сменилась. Закрашивание букв — отдельно, только у текущей строки.
struct LyricsColumn: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let np: NowPlaying
    var centered = false
    var big = false

    var body: some View {
        TimelineView(.animation(minimumInterval: m.isPlaying ? 1.0 / 12 : 0.5, paused: m.animationsPaused)) { _ in
            if let f = m.lyricFrame(time: m.currentTime()) {
                LyricsStack(index: f.index, lines: f.lines, synced: f.synced, centered: centered, big: big,
                            version: (m.lyricsEntry?.source ?? "") + "\(f.lines.count)")
                    .equatable()
            } else {
                noLyrics
            }
        }
    }

    private var noLyrics: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 14) {
            if !centered || big {
                TText(np.title, size: 40, title: true, align: centered ? .center : .leading).lineLimit(3)
                if !np.artist.isEmpty { TText(np.artist, size: 20, color: theme.dim) }
            }
            if np.loading {
                TText("Включаю трек на площадке…", size: 13, alpha: 0.85).padding(.top, 6)
            } else if !m.status.isEmpty {
                TText(m.status, size: 13, alpha: 0.85, align: centered ? .center : .leading).padding(.top, 6)
            }
            HStack(spacing: 8) {
                if m.lyricsOffline { TButton("Повторить", icon: "arrow.clockwise", prominent: true) { m.retryLyrics() } }
                TButton("Найти текст", icon: "magnifyingglass") { m.modal = .lyrics }
                TButton("Вставить свой", icon: "doc.on.clipboard") { m.modal = .pasteLyrics }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .center : .leading)
    }
}

struct LyricsStack: View, Equatable {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    @Environment(\.visual) private var visual
    let index: Int
    let lines: [LyricLine]
    let synced: Bool
    let centered: Bool
    let big: Bool
    let version: String

    static func == (a: LyricsStack, b: LyricsStack) -> Bool {
        a.index == b.index && a.synced == b.synced && a.centered == b.centered && a.big == b.big && a.version == b.version
    }

    var body: some View {
        let s = m.textScale * (big ? 1.25 : 1)
        let cur = max(index, 0)
        let lo = max(0, cur - 2), hi = min(lines.count - 1, cur + 4)
        let offset = m.lyricsEntry?.offset ?? 0
        let align: TextAlignment = centered ? .center : .leading
        VStack(alignment: centered ? .center : .leading, spacing: 18 * s) {
            if index < 0 { IntroDots() }
            ForEach(lines[lo...hi]) { line in
                let d = line.id - index
                Group {
                    if d == 0 {
                        KaraokeLine(line: line, next: line.id + 1 < lines.count ? lines[line.id + 1].time : nil,
                                    synced: synced, scale: s, align: align)
                    } else {
                        PlainLine(text: line.text, scale: s, align: align)
                    }
                }
                .opacity(d == 0 ? 1 : max(0.16, 0.62 - 0.11 * Double(abs(d) - 1)))
                .blur(radius: d == 0 || !visual.blurLines ? 0 : min(2.4, Double(abs(d)) * 0.5))
                .contentShape(Rectangle())
                .onTapGesture { if synced { m.seek(to: line.time - offset + 0.05) } }
            }
            if !synced {
                TText("текст без тайминга, строки идут примерно", size: 11, alpha: 0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .center : .leading)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: index)
    }
}

struct IntroDots: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: m.animationsPaused || !m.isPlaying)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color(hex: theme.pixel ? 0xFFFF55 : theme.sung))
                        .frame(width: 12, height: 12)
                        .scaleEffect(0.6 + 0.4 * max(0, sin(t * 4 - Double(i) * 0.7)))
                }
            }
            .padding(.bottom, 6)
        }
    }
}

struct PlainLine: View {
    @Environment(\.theme) private var theme
    let text: String
    let scale: Double
    let align: TextAlignment

    var body: some View {
        let t = text.isEmpty ? (theme.pixel ? "* * *" : "♪ ♪ ♪") : text.precomposedStringWithCanonicalMapping
        if theme.pixel {
            MCText(t, size: (11 * scale).rounded(), color: 0xE0E0E0, align: align)
        } else {
            Text(t)
                .font(theme.body(theme.lyricSize * 0.6 * scale))
                .foregroundStyle(Color(hex: theme.text))
                .multilineTextAlignment(align)
                .shadow(color: .black.opacity(theme.textShadow ? 0.25 : 0), radius: 3, y: 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Текущая строка: пропетые буквы закрашиваются. Обновляется ~30 раз в секунду только эта строка.
struct KaraokeLine: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    @Environment(\.visual) private var visual
    let line: LyricLine
    let next: Double?
    let synced: Bool
    let scale: Double
    let align: TextAlignment

    var body: some View {
        if synced && m.karaokeMode == .line && !visual.bassPulse {
            content(sung: Int.max, pulse: 0)
        } else if synced {
            let interval = !m.isPlaying ? 0.5 : (visual.bassPulse ? (m.frameInterval ?? 1.0 / 120) : 1.0 / 30)
            TimelineView(.animation(minimumInterval: interval, paused: m.animationsPaused)) { _ in
                content(sung: sung(), pulse: visual.bassPulse ? Visuals.shared.bass : 0)
            }
        } else {
            content(sung: 0, pulse: 0)
        }
    }

    private func sung() -> Int {
        let text = line.text.isEmpty ? "..." : line.text
        if m.karaokeMode == .line { return text.count }
        let tm = m.currentTime() + (m.lyricsEntry?.offset ?? 0)
        let end = next ?? line.time + 5
        let dur = min(max(end - line.time, 0.3), 10)
        let p = min(1, max(0, (tm - line.time) / (dur * 0.85)))
        return Int((p * Double(text.count)).rounded())
    }

    @ViewBuilder private func content(sung: Int, pulse: Double) -> some View {
        let t = line.text.isEmpty ? (theme.pixel ? "* * *" : "♪ ♪ ♪") : line.text.precomposedStringWithCanonicalMapping
        let anchor: UnitPoint = align == .center ? .center : .leading
        if theme.pixel {
            KaraokeText(text: t, sung: synced ? sung : 0, size: (19 * scale).rounded(), align: align)
                .scaleEffect(1 + pulse * pulse * 0.04, anchor: anchor)
        } else {
            Text(karaoke(t, sung))
                .font(theme.title(theme.lyricSize * scale))
                .lineSpacing(6)
                .multilineTextAlignment(align)
                .shadow(color: visual.glow ? (theme.glow.map { Color(hex: $0, alpha: 0.75) } ?? .clear) : .clear, radius: 16)
                .shadow(color: .black.opacity(theme.textShadow ? 0.3 : 0), radius: 4, y: 2)
                .fixedSize(horizontal: false, vertical: true)
                .scaleEffect(1 + pulse * pulse * 0.045, anchor: anchor)
        }
    }

    private func karaoke(_ t: String, _ sung: Int) -> AttributedString {
        let chars = Array(t)
        let n = synced ? min(max(0, sung), chars.count) : 0
        var a = AttributedString(String(chars[..<n]))
        a.foregroundColor = Color(hex: theme.sung)
        var b = AttributedString(String(chars[n...]))
        b.foregroundColor = Color(hex: theme.text, alpha: synced ? theme.unsungAlpha : 1)
        return a + b
    }
}

/// Строка караоке для пиксельной темы: пропетые буквы жёлтые, с тенью Minecraft.
struct KaraokeText: View {
    let text: String
    let sung: Int
    let size: CGFloat
    var align: TextAlignment = .center

    private func attr(shadow: Bool) -> AttributedString {
        let chars = Array(text.precomposedStringWithCanonicalMapping)
        let n = min(max(0, sung), chars.count)
        let gold: UInt32 = 0xFFFF55, white: UInt32 = 0xFFFFFF
        var a = AttributedString(String(chars[..<n]))
        a.foregroundColor = Color(hex: shadow ? mcShadow(gold) : gold)
        var b = AttributedString(String(chars[n...]))
        b.foregroundColor = Color(hex: shadow ? mcShadow(white) : white)
        return a + b
    }

    var body: some View {
        Text(attr(shadow: false)).font(.mc(size)).multilineTextAlignment(align).lineSpacing(size * 0.45)
            .background(alignment: .topLeading) {
                Text(attr(shadow: true)).font(.mc(size)).multilineTextAlignment(align).lineSpacing(size * 0.45)
                    .offset(x: size / 8, y: size / 8)
            }
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Обложка, пластинка, кнопки и «далее»

final class Spinner {
    var angle = 0.0
    var last = 0.0
    func advance(_ t: Double, _ playing: Bool) -> Double {
        if playing && last > 0 { angle += min(0.1, max(0, t - last)) * 42 }
        last = t
        return angle
    }
}

struct CoverColumn: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    @Environment(\.visual) private var visual
    let np: NowPlaying
    let size: CGFloat
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 12 : 20) {
            ZStack(alignment: .leading) {
                VinylDisc(size: size * 0.94, playing: m.isPlaying, colors: m.palette)
                    .offset(x: m.isPlaying ? size * 0.34 : size * 0.1)
                CoverArt(size: size)
            }
            .frame(width: size * 1.32, height: size, alignment: .leading)
            .animation(.spring(response: 0.7, dampingFraction: 0.78), value: m.isPlaying)

            VStack(spacing: 8) {
                TText(np.title, size: compact ? 18 : 22, title: true, align: .center).lineLimit(2)
                if !np.artist.isEmpty {
                    TText(np.artist, size: compact ? 13 : 15, color: theme.dim, align: .center).lineLimit(1)
                }
                SourceBadge(np: np)
            }
            .frame(width: size * 1.25)

            if !compact {
                TrackActions(np: np)
                UpNextCard().frame(width: size * 1.2)
            }
        }
    }
}

struct CoverArt: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.visual) private var visual
    let size: CGFloat

    var body: some View {
        if visual.bassPulse {
            TimelineView(.animation(minimumInterval: m.frameInterval, paused: !m.isPlaying || m.animationsPaused)) { _ in
                let b = Visuals.shared.bass
                CoverFrame(image: m.nowArtwork, size: size).scaleEffect(1 + b * b * 0.025)
            }
        } else {
            CoverFrame(image: m.nowArtwork, size: size)
        }
    }
}

struct CoverFrame: View {
    @Environment(\.theme) private var theme
    @Environment(\.visual) private var visual
    let image: NSImage?
    let size: CGFloat

    private var picture: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color(hex: theme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }

    var body: some View {
        let g = visual.glow
        switch theme.id {
        case .minecraft:
            picture
                .padding(10)
                .background(Color(hex: 0xB98A55))
                .overlay(Rectangle().strokeBorder(Color(hex: 0x7A5230), lineWidth: 6).padding(3))
                .overlay(Rectangle().strokeBorder(Color(hex: 0x2C1C0C), lineWidth: 3))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.5), radius: 0, x: 6, y: 6)
        case .dora:
            picture
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color(hex: 0xFF7BCB), lineWidth: 3))
                .shadow(color: Color(hex: 0xFF2DAA, alpha: g ? 0.65 : 0.3), radius: g ? 28 : 8)
                .overlay(alignment: .topTrailing) { sticker("sparkle", 0xFFE66B, 34).offset(x: 14, y: -16) }
                .overlay(alignment: .bottomLeading) { sticker("heart.fill", 0xFF4FB8, 30).offset(x: -12, y: 12) }
                .overlay(alignment: .topLeading) { sticker("star.fill", 0xB36BFF, 22).offset(x: -8, y: -8) }
        case .kitty:
            picture
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.white))
                .shadow(color: Color(hex: 0xFF7EB3, alpha: g ? 0.55 : 0.3), radius: g ? 22 : 8, y: 8)
                .overlay(alignment: .topLeading) { BowShape().frame(width: 74, height: 52).offset(x: -18, y: -22) }
                .frame(width: size, height: size)
        case .neon:
            picture
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x00F0FF), lineWidth: 2))
                .shadow(color: Color(hex: 0x00D5FF, alpha: g ? 0.8 : 0.35), radius: g ? 18 : 6)
                .shadow(color: Color(hex: 0xFF2BD6, alpha: g ? 0.5 : 0), radius: 40)
        case .minimal:
            picture
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: g ? 30 : 12, y: 14)
        }
    }

    private func sticker(_ symbol: String, _ color: UInt32, _ s: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: s, weight: .black))
            .foregroundStyle(Color(hex: color))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            .rotationEffect(.degrees(-12))
    }
}

struct BowShape: View {
    var body: some View {
        Canvas { ctx, s in
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let b = Shapes.bow(c, s.width * 0.95)
            ctx.fill(b, with: .color(Color(hex: 0xE8374F)))
            ctx.stroke(b, with: .color(Color(hex: 0xA81A36)), lineWidth: 2.5)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - s.width * 0.1, y: c.y - s.height * 0.16, width: s.width * 0.2, height: s.height * 0.32)),
                     with: .color(Color(hex: 0xC92440)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - s.width * 0.34, y: c.y - s.height * 0.22, width: s.width * 0.1, height: s.height * 0.12)),
                     with: .color(.white.opacity(0.45)))
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        .rotationEffect(.degrees(-14))
    }
}

/// Пластинка: картинка рисуется один раз, а вращается только поворотом (почти бесплатно).
struct VinylDisc: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.visual) private var visual
    let size: CGFloat
    let playing: Bool
    let colors: [UInt32]
    @State private var spin = Spinner()

    var body: some View {
        let img = ArtKit.vinylImage(size: Int(size * 2), label: (colors.first ?? 0xFF4F9A, colors.count > 1 ? colors[1] : 0xFFD36B))
        let pic = Image(decorative: img, scale: 2).resizable().frame(width: size, height: size)
        Group {
            if visual.vinylSpin {
                TimelineView(.animation(minimumInterval: max(m.frameInterval ?? 0, 1.0 / 60),
                                        paused: !playing || m.animationsPaused)) { tl in
                    pic.rotationEffect(.degrees(spin.advance(tl.date.timeIntervalSinceReferenceDate, playing)))
                }
            } else {
                pic
            }
        }
        .shadow(color: .black.opacity(visual.glow ? 0.4 : 0.25), radius: visual.glow ? 14 : 6, y: 6)
    }
}

struct SourceBadge: View {
    @Environment(\.theme) private var theme
    let np: NowPlaying

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: np.sourceColor ?? theme.accent)).frame(width: 8, height: 8)
            let label = np.sourceLabel + (np.loading ? " · загрузка…" : "")
            if theme.pixel {
                MCText(label, size: 7, color: 0xE0E0E0)
            } else {
                Text(label).font(theme.body(11)).foregroundStyle(Color(hex: theme.panelText, alpha: 0.9))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background {
            if theme.pixel { Color.black.opacity(0.45) } else {
                Capsule().fill(Color(hex: theme.panel, alpha: 0.6))
            }
        }
    }
}

/// Сердечко, «в плейлист» и «весь текст» под обложкой.
struct TrackActions: View {
    @EnvironmentObject var m: PlayerModel
    let np: NowPlaying

    var body: some View {
        HStack(spacing: 12) {
            HeartButton(on: m.isFavorite(np), size: 40, filledBackground: true) { m.toggleFavorite() }
            AddToPlaylistMenu(size: 40, filledBackground: true)
            RoundAction(symbol: "quote.bubble", size: 40, active: m.modal == .lyrics, tip: "Весь текст и поиск") { m.toggleLyrics() }
        }
    }
}

/// Кнопка «+» с меню плейлистов.
struct AddToPlaylistMenu: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    var size: CGFloat = 32
    var filledBackground = false
    @State private var hover = false

    var body: some View {
        Menu {
            Button("Новый плейлист…") { m.modal = .newPlaylist(addCurrent: true) }
            if !m.userPlaylists.isEmpty { Divider() }
            ForEach(m.userPlaylists) { p in
                Button((m.contains(p.id, m.nowPlaying) ? "✓ " : "") + p.name) { m.addCurrent(to: p.id) }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Color(hex: theme.pixel ? 0xFFFFFF : theme.panelText))
                .frame(width: size, height: size)
                .background { if filledBackground || theme.pixel { RoundBackground(hover: hover) } }
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hover = $0 }
        .disabled(m.nowPlaying == nil)
        .help("Добавить в плейлист")
    }
}

/// Что будет дальше в плейлисте.
struct UpNextCard: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        if let q = m.queue, let next = q.upNext, let p = m.playlist(q.playlistID) {
            HStack(spacing: 10) {
                SavedArtwork(item: next, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    TText("Далее · \(p.name)", size: 10, alpha: 0.7).lineLimit(1)
                    TText(next.title, size: 13, title: false).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let pl = next.platform { PlatformBadge(platform: pl, size: 16) }
                TIconButton("forward.fill", size: 28, tip: "Следующий") { m.next() }
            }
            .padding(10)
            .background {
                if theme.pixel { Color.black.opacity(0.45) } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: theme.panel, alpha: 0.55))
                }
            }
        }
    }
}

/// Обложка трека из плейлиста: для файла — из тегов, для площадки — по адресу картинки.
struct SavedArtwork: View {
    @EnvironmentObject var m: PlayerModel
    @EnvironmentObject var art: ArtworkLoader
    @Environment(\.theme) private var theme
    let item: SavedTrack
    let size: CGFloat
    var rounded = true

    var body: some View {
        let img: NSImage = {
            if let url = item.fileURL {
                if let t = m.tracks.first(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }),
                   let a = t.artwork { return a }
                if let a = art.image(url.absoluteString) { return a }
            }
            if let a = art.image(item.artURL ?? m.artMap[item.key]) { return a }
            return ArtKit.placeholder(seed: item.artist + item.title, size: 200)
        }()
        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: theme.pixel || !rounded ? 0 : size * 0.2, style: .continuous))
    }
}

// MARK: - Приветствие

/// «Продолжить»: трек с площадки, который играл до выхода.
struct ResumeCard: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let track: SavedTrack

    var body: some View {
        Button { m.resume() } label: {
            HStack(spacing: 12) {
                SavedArtwork(item: track, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    TText("Продолжить", size: 11, alpha: 0.7, onPanel: true)
                    TText((track.artist.isEmpty ? "" : track.artist + " — ") + track.title, size: 14, title: true, onPanel: true)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let p = track.platform { PlatformBadge(platform: p, size: 22) }
                Image(systemName: "play.fill").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: theme.pixel ? 0xFFFFFF : theme.accent))
            }
            .padding(12)
            .frame(width: 470)
            .background(PanelBackground(radius: theme.pixel ? 0 : 18, shadow: false))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

struct Welcome: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    @State private var splash = [
        "Басы на максимум!", "Теперь с текстом!", "Криперы одобряют!", "100% пикселей!", "Громче!",
        "Блочный звук!", "Не буди эндермена!", "Караоке в шахте!", "Сделано из блоков!", "Звук с алмазами!",
    ].randomElement()!

    var body: some View {
        VStack(spacing: 30) {
            if theme.pixel {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        ForEach([(0x2B2B2B, 12.0), (0x4F4F4F, 8.0), (0x8A8A8A, 4.0)], id: \.1) { c, off in
                            Text("МУЗЫКА В ОФЛАЙН").font(.mc(36)).foregroundStyle(Color(hex: UInt32(c))).offset(y: off)
                        }
                        Text("МУЗЫКА В ОФЛАЙН").font(.mc(36)).foregroundStyle(
                            LinearGradient(colors: [Color(hex: 0xEDEDED), Color(hex: 0xB5B5B5)], startPoint: .top, endPoint: .bottom))
                    }
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: m.animationsPaused)) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        MCText(splash, size: 12, color: 0xFFFF55)
                            .fixedSize()
                            .scaleEffect(1.0 + 0.08 * abs(sin(t * 2 * .pi)))
                            .rotationEffect(.degrees(-18))
                    }
                    .offset(x: 110, y: 26)
                }
            } else {
                VStack(spacing: 14) {
                    Text("Музыка в офлайн")
                        .font(theme.title(58))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                                        startPoint: .leading, endPoint: .trailing))
                        .shadow(color: theme.glow.map { Color(hex: $0, alpha: 0.6) } ?? .black.opacity(0.3), radius: 18)
                    TText("Твоя музыка, тексты песен и живые фоны", size: 17, alpha: 0.9)
                }
            }
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TButton("Открыть файлы", icon: "folder.fill", prominent: true, width: 230) { m.openPanel() }
                    TButton("Подключить аккаунт", icon: "person.crop.circle.badge.plus", width: 230) { m.modal = .addAccount }
                }
                HStack(spacing: 10) {
                    TButton("Любимые и плейлисты", icon: "heart.fill", width: 230) { m.show(.playlist(Playlist.favoritesID)) }
                    TButton("Темы и фоны", icon: "paintpalette.fill", width: 230) { m.openSettings(.look) }
                }
            }
            TText("или перетащи файлы и папки прямо в окно", size: 12, alpha: 0.75, align: .center)
            if let t = m.resumeTrack { ResumeCard(track: t) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Плеер снизу (гладкие темы)

struct PlayerBar: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        let web = m.activeWebID != nil
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                MiniNow()
                if let np = m.nowPlaying {
                    HeartButton(on: m.isFavorite(np), size: 30) { m.toggleFavorite() }
                    AddToPlaylistMenu(size: 30)
                }
            }
            .frame(minWidth: 220, maxWidth: 360, alignment: .leading)

            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    TIconButton("shuffle", size: 30, active: m.shuffle, tip: m.shuffle ? "Перемешка: вкл" : "Перемешка: выкл") { m.toggleShuffle() }
                    TIconButton("backward.fill", size: 36, tip: "Назад") { m.prev() }
                    TIconButton(m.isPlaying ? "pause.fill" : "play.fill", size: 50, prominent: true, tip: "Играть / пауза") { m.togglePlay() }
                    TIconButton("forward.fill", size: 36, tip: "Вперёд") { m.next() }
                    TIconButton(m.repeatMode == .one ? "repeat.1" : "repeat", size: 30, active: m.repeatMode != .none,
                                tip: ["all": "Повтор: весь список", "one": "Повтор: один трек", "none": "Повтор: выкл"][m.repeatMode.rawValue]!) {
                        m.cycleRepeat()
                    }
                }
                Scrubber()
            }
            .frame(maxWidth: 620)

            HStack(spacing: 12) {
                TIconButton("quote.bubble.fill", size: 30, active: m.modal == .lyrics, tip: "Весь текст") { m.toggleLyrics() }
                MiniSlider(symbol: "speaker.wave.2.fill", value: $m.volume, range: 0...1,
                           tipText: "Громкость: \(Int((m.volume * 100).rounded()))%")
                MiniSlider(symbol: "waveform.path", value: $m.bass, range: -10...24,
                           tipText: web ? "Басы работают для файлов" : (m.bass == 0 ? "Басы: выкл" : String(format: "Басы: %+.0f дБ", m.bass)),
                           disabled: web)
            }
            .frame(minWidth: 220, maxWidth: 360, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(PanelBackground(radius: min(theme.radius + 6, 26), glassy: true))
    }
}

/// Полоса перемотки. Обновляется 4 раза в секунду — глазу незаметно, процессору легко.
struct Scrubber: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    @State private var drag: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let d = m.duration
            let t = drag ?? m.currentTime()
            HStack(spacing: 10) {
                Text(fmtTime(t)).font(theme.body(11).monospacedDigit()).foregroundStyle(Color(hex: theme.panelText, alpha: 0.8))
                    .frame(width: 40, alignment: .trailing)
                GeometryReader { g in
                    let p = d > 0 ? min(1, t / d) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: theme.panelText, alpha: 0.16)).frame(height: 5)
                        Capsule().fill(LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                                      startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(5, g.size.width * p), height: 5)
                        Circle().fill(Color.white).frame(width: 12, height: 12)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .offset(x: p * (g.size.width - 12))
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in if d > 0 { drag = max(0, min(1, v.location.x / g.size.width)) * d } }
                        .onEnded { _ in if let x = drag { m.seek(to: x) }; drag = nil })
                }
                .frame(height: 14)
                Text(fmtTime(d)).font(theme.body(11).monospacedDigit()).foregroundStyle(Color(hex: theme.panelText, alpha: 0.8))
                    .frame(width: 40, alignment: .leading)
            }
        }
    }
}

struct MiniNow: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let a = m.nowArtwork {
                    Image(nsImage: a).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(hex: theme.panelText, alpha: 0.12)
                        .overlay(Image(systemName: "music.note").foregroundStyle(Color(hex: theme.panelText)))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: min(theme.radius * 0.5, 10), style: .continuous))
            .onTapGesture { m.show(.stage) }
            VStack(alignment: .leading, spacing: 3) {
                Text(m.nowPlaying?.title ?? "Ничего не играет").font(theme.body(13)).lineLimit(1)
                    .foregroundStyle(Color(hex: theme.panelText))
                Text(m.nowPlaying.map { $0.artist.isEmpty ? $0.sourceLabel : $0.artist } ?? "Открой файлы или аккаунт")
                    .font(theme.body(11)).lineLimit(1)
                    .foregroundStyle(Color(hex: theme.panelDim))
            }
        }
    }
}

struct MiniSlider: View {
    @Environment(\.theme) private var theme
    let symbol: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var tipText = ""
    var disabled = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: theme.panelText))
            SmoothTrack(value: $value, range: range, height: 4, thumb: 12).frame(width: 78)
        }
        .opacity(disabled ? 0.4 : 1)
        .allowsHitTesting(!disabled)
        .tip(tipText, offset: -34)
    }
}

// MARK: - Нижний HUD Майнкрафта: сердца, еда, опыт, хотбар

private let slotSize: CGFloat = 50
private let hudWidth: CGFloat = slotSize * 9 + 4

struct HUD: View {
    @EnvironmentObject var m: PlayerModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom) {
                Hearts()
                Spacer()
                Hunger()
            }
            .frame(width: hudWidth)
            XPBar().frame(width: hudWidth)
            Hotbar()
        }
        .overlay(alignment: .trailing) {
            if m.nowPlaying != nil {
                VStack(spacing: 6) {
                    AddToPlaylistMenu(size: 36)
                }
                .offset(x: 52, y: 28)
            }
        }
    }
}

struct Hearts: View {
    @EnvironmentObject var m: PlayerModel

    var body: some View {
        let v = m.volume * 10
        HStack(spacing: 1) {
            ForEach(0..<10, id: \.self) { i in
                PixelImage(v >= Double(i) + 1 ? Art.heartFull : v >= Double(i) + 0.5 ? Art.heartHalf : Art.heartEmpty, width: 18)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            let x = Double(g.location.x)
            m.setVolume(((x / 19) * 2).rounded(.up) / 2 / 10)
        })
        .tip("Громкость: \(Int((m.volume * 100).rounded()))%", offset: -44)
    }
}

struct Hunger: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.visual) private var visual

    var body: some View {
        let level = max(0, m.bass) / 24 * 10
        let web = m.activeWebID != nil
        Group {
            if visual.bassPulse && m.isPlaying && !web {
                TimelineView(.animation(minimumInterval: m.frameInterval, paused: m.animationsPaused)) { _ in
                    row(level: level, jump: Visuals.shared.bass)
                }
            } else {
                row(level: level, jump: 0)
            }
        }
        .opacity(web ? 0.5 : 1)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            guard !web else { return }
            let lv = ((189 - g.location.x) / 19 * 2).rounded(.up) / 2
            m.bass = (min(10, max(0, lv)) / 10 * 24).rounded()
        })
        .tip(web ? "Басы работают для файлов" : (m.bass == 0 ? "Басы: выкл" : String(format: "Басы: %+.0f дБ", m.bass)), offset: -44)
    }

    private func row(level: Double, jump: Double) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<10, id: \.self) { i in
                let k = Double(9 - i)
                PixelImage(level >= k + 1 ? Art.meatFull : level >= k + 0.5 ? Art.meatHalf : Art.meatEmpty, width: 18)
                    .offset(y: level > k ? -CGFloat(jump * jump * (i % 2 == 0 ? 5 : 3)) : 0)
            }
        }
    }
}

struct XPBar: View {
    @EnvironmentObject var m: PlayerModel
    @State private var drag: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let d = m.duration
            let t = drag ?? m.currentTime()
            let p = d > 0 ? min(1, t / d) : 0
            ZStack {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Color(hex: 0x1B1B1B)
                        LinearGradient(colors: [Color(hex: 0xC3FF78), Color(hex: 0x80FF20), Color(hex: 0x3D9A0C)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(width: g.size.width * p)
                        HStack(spacing: 0) {
                            ForEach(1..<18, id: \.self) { _ in
                                Spacer(minLength: 0)
                                Color.black.frame(width: 2)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in if d > 0 { drag = max(0, min(1, v.location.x / g.size.width)) * d } }
                        .onEnded { _ in if let x = drag { m.seek(to: x) }; drag = nil })
                }
                .frame(height: 12)
                OutlinedText(text: "\(fmtTime(t))/\(fmtTime(d))", size: 7)
                    .offset(y: -17)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct Hotbar: View {
    @EnvironmentObject var m: PlayerModel
    @State private var hovered: Int?

    private var items: [(CGImage, String, Bool)] {
        let fav = m.isFavorite(m.nowPlaying)
        return [
            (Art.prev, "Назад (1)", false),
            (m.isPlaying ? Art.pause : Art.play, m.isPlaying ? "Пауза (Пробел / 2)" : "Играть (Пробел / 2)", false),
            (Art.next, "Вперёд (3)", false),
            (fav ? Art.heartFull : Art.heartEmpty, fav ? "Убрать из любимых (4)" : "В любимые (4)", fav),
            (m.repeatMode == .one ? Art.repeatOne : Art.repeatAll,
             ["all": "Повтор: весь список (5)", "one": "Повтор: один трек (5)", "none": "Повтор: выкл (5)"][m.repeatMode.rawValue]!,
             m.repeatMode != .none),
            (Art.shuffle, m.shuffle ? "Перемешка: вкл (6)" : "Перемешка: выкл (6)", m.shuffle),
            (Art.chest, "Мои файлы (E / 7)", m.page == .library),
            (Art.book, "Весь текст (L / 8)", m.modal == .lyrics),
            (Art.gear, "Настройки (Esc / 9)", m.page == .settings),
        ]
    }

    var body: some View {
        let list = items
        HStack(spacing: 0) {
            ForEach(0..<list.count, id: \.self) { i in
                let (icon, tipText, active) = list[i]
                ZStack {
                    Rectangle().strokeBorder(Color(hex: 0x8B8B8B, alpha: 0.55), lineWidth: 2)
                    if active { Color(hex: 0x80FF20, alpha: 0.2).padding(2) }
                    PixelImage(icon, width: icon.width == 16 ? 32 : 27)
                }
                .frame(width: slotSize, height: slotSize)
                .overlay {
                    if hovered == i {
                        ZStack {
                            Rectangle().strokeBorder(Color.white, lineWidth: 3)
                            Rectangle().strokeBorder(Color(hex: 0x8B8B8B), lineWidth: 2).padding(3)
                        }
                        .padding(-3)
                    }
                }
                .overlay(alignment: .top) {
                    if hovered == i { TooltipBox(tipText).offset(y: -46).allowsHitTesting(false) }
                }
                .contentShape(Rectangle())
                .onTapGesture { m.hotbar(i) }
                .onHover { h in if h { hovered = i } else if hovered == i { hovered = nil } }
                .zIndex(hovered == i ? 1 : 0)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.55))
        .overlay(Rectangle().strokeBorder(Color(hex: 0x2A2A2A), lineWidth: 2))
    }
}

// MARK: - Сообщения, перетаскивание, F3

struct ToastView: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack {
            Spacer()
            Group {
                if theme.pixel {
                    if m.toastOn {
                        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: m.animationsPaused)) { tl in
                            MCText(m.toast, size: 10, color: hueHex(tl.date.timeIntervalSinceReferenceDate * 0.35), align: .center)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text(m.toast)
                        .font(theme.body(13))
                        .foregroundStyle(Color(hex: theme.panelText))
                        .lineLimit(1)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(Color(hex: theme.panel, alpha: 0.94)))
                        .overlay(Capsule().strokeBorder(Color(hex: theme.border, alpha: 0.5), lineWidth: 1))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
            }
            .padding(.bottom, theme.pixel ? 160 : 130)
            .opacity(m.toastOn ? 1 : 0)
            .offset(y: m.toastOn ? 0 : 10)
            .animation(.easeInOut(duration: 0.4), value: m.toastOn)
        }
        .allowsHitTesting(false)
    }
}

struct DropOverlay: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
            RoundedRectangle(cornerRadius: theme.pixel ? 0 : 30, style: .continuous)
                .strokeBorder(Color(hex: theme.pixel ? 0xFFFF55 : theme.accent), style: StrokeStyle(lineWidth: 5, dash: [18, 12]))
                .padding(24)
            TText("Брось музыку сюда!", size: 34, title: true, color: theme.pixel ? 0xFFFF55 : 0xFFFFFF, align: .center)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct DebugOverlay: View {
    @EnvironmentObject var m: PlayerModel
    @StateObject private var load = ResourceMonitor()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let f = m.audio.file
            let lines = [
                "Музыка в офлайн 2.1 (F3)",
                "Источник: \(m.nowPlaying?.sourceLabel ?? "-")",
                f.map { "Формат файла: \(Int($0.fileFormat.sampleRate)) Гц, \($0.fileFormat.channelCount) кан." } ?? "Формат файла: -",
                String(format: "Позиция: %.1f / %.1f с", m.currentTime(), m.duration),
                String(format: "Басы: %+.0f дБ @ %.0f Гц, высокие %+.0f дБ", m.bass, m.bassFreq, m.treble),
                "Тема: \(m.themeValue.name), фон: \(m.background.title)",
                "Режим: \(m.perfMode?.title ?? "свой"), кадров: \(m.visual.fps == 0 ? "как у экрана" : "\(m.visual.fps)")",
                "Процессор: \(load.cpuText), память: \(load.memText)",
                "Текст: \(m.lyricsEntry?.source ?? "-")",
                "Аккаунтов: \(m.accounts.count), загружено: \(m.loadedSessions.count)",
            ]
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { l in
                    MCText(l, size: 8, color: 0xE0E0E0).padding(3).background(Color(hex: 0x505050, alpha: 0.55))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 40).padding(.leading, m.showSidebar ? 252 : 76)
            .allowsHitTesting(false)
        }
        .onAppear { load.start() }
        .onDisappear { load.stop() }
    }
}
