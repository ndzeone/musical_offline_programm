import SwiftUI
import WebKit

// MARK: - Карточка страницы

struct PageCard<Header: View, Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header()
            content()
        }
        .padding(theme.pixel ? 18 : 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelBackground())
    }
}

struct PageTitle: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TText(title, size: theme.pixel ? 18 : 28, title: true, onPanel: true).lineLimit(1)
            if let subtitle {
                TText(subtitle, size: 12, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
            }
        }
    }
}

// MARK: - Мои файлы

struct LibraryPage: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        PageCard {
            HStack(alignment: .bottom) {
                PageTitle(title: theme.pixel ? "Сундук с пластинками" : "Мои файлы",
                          subtitle: m.tracks.isEmpty ? "Музыка с диска" : "Треков: \(m.tracks.count) · \(fmtLong(m.tracks.reduce(0) { $0 + $1.duration }))")
                Spacer()
                TButton("Файлы", icon: "plus", prominent: true) { m.openPanel() }
                TButton("Папка", icon: "folder.badge.plus") { m.openFolderPanel() }
                if !m.tracks.isEmpty { TButton("Очистить", icon: "trash") { m.clear() } }
            }
        } content: {
            ScrollViewReader { proxy in
                Scrolling {
                    LibraryList().padding(theme.pixel ? 4 : 2)
                }
                .background { if theme.pixel { Color(hex: 0x8B8B8B) } }
                .overlay { if theme.pixel { Rectangle().strokeBorder(Color(hex: 0x373737), lineWidth: 2) } }
                .onAppear { if let id = m.currentID { proxy.scrollTo(id, anchor: .center) } }
            }
            TText("Правый клик по треку: в любимые, в плейлист, показать в Finder. Файл .lrc с тем же именем подхватится сам.",
                  size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
        }
    }
}

struct LibraryList: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        LazyVStack(spacing: theme.pixel ? 3 : 4) {
            ForEach(m.tracks) { t in
                TrackRow(track: t, active: t.id == m.currentID && m.activeWebID == nil).id(t.id)
            }
            if m.tracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.house.fill").font(.system(size: 40))
                        .foregroundStyle(Color(hex: theme.pixel ? 0x3F3F3F : theme.panelDim))
                    TText("Пусто. Добавь музыку кнопками сверху или перетащи файлы в окно.",
                          size: 13, onPanel: true, align: .center)
                }
                .padding(40)
            }
        }
    }
}

/// Размер по-русски: «0 КБ», «226 КБ», «1,4 МБ».
func fmtBytes(_ b: Int) -> String {
    if b < 1024 * 1024 { return "\(Int((Double(b) / 1024).rounded())) КБ" }
    let mb = Double(b) / 1024 / 1024
    return String(format: "%.1f МБ", mb).replacingOccurrences(of: ".", with: ",")
}

func fmtLong(_ s: Double) -> String {
    let m = Int(s / 60)
    if m >= 60 { return "\(m / 60) ч \(m % 60) мин" }
    return "\(m) мин"
}

struct TrackRow: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let track: Track
    let active: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let a = track.artwork {
                    Image(nsImage: a).resizable().aspectRatio(contentMode: .fill)
                } else if theme.pixel {
                    PixelImage(Art.discs[track.color % Art.discs.count], width: 36)
                } else {
                    Image(nsImage: ArtKit.placeholder(seed: track.artist + track.title, size: 200)).resizable()
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: theme.pixel ? 0 : 8, style: .continuous))
            VStack(alignment: .leading, spacing: theme.pixel ? 7 : 3) {
                if theme.pixel {
                    MCText(track.title, size: 9).lineLimit(1)
                    MCText(track.artist.isEmpty ? "Неизвестный исполнитель" : track.artist, size: 7, color: 0xE0E0E0).lineLimit(1)
                } else {
                    Text(track.title).font(theme.body(14)).lineLimit(1)
                        .foregroundStyle(Color(hex: active ? theme.onAccent : theme.panelText))
                    Text(track.artist.isEmpty ? "Неизвестный исполнитель" : track.artist).font(theme.body(11)).lineLimit(1)
                        .foregroundStyle(Color(hex: active ? theme.onAccent : theme.panelDim, alpha: 0.9))
                }
            }
            Spacer(minLength: 8)
            if active && m.isPlaying {
                Image(systemName: "waveform").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: theme.pixel ? 0xFFFFFF : theme.onAccent))
                    .symbolEffect(.variableColor.iterative)
            }
            if m.favorites.items.contains(where: { $0.key == track.key }) {
                Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: theme.pixel ? 0xE3201B : (active ? theme.onAccent : theme.accent)))
            }
            if theme.pixel {
                MCText(fmtTime(track.duration), size: 8)
            } else {
                Text(fmtTime(track.duration)).font(theme.body(11).monospacedDigit())
                    .foregroundStyle(Color(hex: active ? theme.onAccent : theme.panelDim))
            }
        }
        .padding(theme.pixel ? 6 : 8)
        .background {
            if theme.pixel {
                BevelBox(fill: active ? 0x5B8C32 : hover ? 0xA5A5A5 : 0x8B8B8B, light: 0x373737, dark: 0xFFFFFF, border: nil)
            } else {
                RoundedRectangle(cornerRadius: min(theme.radius * 0.6, 14), style: .continuous)
                    .fill(active ? AnyShapeStyle(LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                                               startPoint: .leading, endPoint: .trailing))
                                 : AnyShapeStyle(Color(hex: theme.panelText, alpha: hover ? 0.1 : 0.04)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { m.play(id: track.id) }
        .onHover { hover = $0 }
        .contextMenu {
            Button("Играть") { m.play(id: track.id) }
            Button("В любимые ♥") { m.play(id: track.id); m.toggleFavorite() }
            if !m.userPlaylists.isEmpty {
                Menu("Добавить в плейлист") {
                    ForEach(m.userPlaylists) { p in
                        Button(p.name) { m.addFile(track, to: p.id) }
                    }
                }
            }
            Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([track.url]) }
            Divider()
            Button("Убрать из списка") { m.remove(id: track.id) }
        }
    }
}

extension PlayerModel {
    /// Добавить файл в плейлист, не включая его.
    func addFile(_ t: Track, to playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let s = SavedTrack(source: .file(path: t.url.standardizedFileURL.path), title: t.title, artist: t.artist, duration: t.duration)
        if playlists[i].items.contains(where: { $0.key == s.key }) { announce("Уже есть в «\(playlists[i].name)»"); return }
        playlists[i].items.append(s)
        announce("Добавлено в «\(playlists[i].name)»")
    }
}

// MARK: - Плейлист (и «Любимые»)

struct PlaylistPage: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let id: UUID

    var body: some View {
        if let p = m.playlist(id) {
            PageCard {
                PlaylistHeader(p: p)
            } content: {
                Scrolling {
                    PlaylistList(p: p).padding(theme.pixel ? 4 : 2)
                }
                .background { if theme.pixel { Color(hex: 0x8B8B8B) } }
                .overlay { if theme.pixel { Rectangle().strokeBorder(Color(hex: 0x373737), lineWidth: 2) } }
            }
            .onAppear { m.resolveMissingArt(id) }
            .onChange(of: id) { _, new in m.resolveMissingArt(new) }
        } else {
            Color.clear.onAppear { m.show(.stage) }
        }
    }
}

struct PlaylistHeader: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let p: Playlist

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            PlaylistCover(p: p, size: 104)
            VStack(alignment: .leading, spacing: 10) {
                PageTitle(title: p.name, subtitle: p.items.isEmpty ? "Пока пусто"
                          : "Треков: \(p.items.count) · \(fmtLong(p.duration)) · \(sourcesText)")
                HStack(spacing: 8) {
                    TButton("Слушать", icon: "play.fill", prominent: true) { m.playPlaylist(p.id, shuffled: false) }
                    TButton("Вперемешку", icon: "shuffle") { m.playPlaylist(p.id, shuffled: true) }
                    if !p.items.isEmpty {
                        TButton("Обложки", icon: "photo.on.rectangle.angled") { m.refreshArt(p.id) }
                            .help("Найти обложки заново")
                    }
                    if !p.isFavorites {
                        TButton("Имя", icon: "pencil") { PlaylistDialogs.rename(p) }
                        TButton("Удалить", icon: "trash") { PlaylistDialogs.remove(p) }
                    }
                }
                .disabled(p.items.isEmpty && p.isFavorites)
            }
            Spacer(minLength: 0)
        }
    }

    private var sourcesText: String {
        var names: [String] = []
        if p.items.contains(where: { $0.fileURL != nil }) { names.append("файлы") }
        for pl in Platform.allCases where p.items.contains(where: { $0.platform == pl }) { names.append(pl.title) }
        return names.joined(separator: ", ")
    }
}

/// Обложка плейлиста: мозаика из обложек первых треков.
struct PlaylistCover: View {
    @Environment(\.theme) private var theme
    let p: Playlist
    let size: CGFloat

    var body: some View {
        let items = Array(p.items.prefix(4))
        Group {
            if items.count >= 4 {
                VStack(spacing: 0) {
                    HStack(spacing: 0) { SavedArtwork(item: items[0], size: size / 2, rounded: false); SavedArtwork(item: items[1], size: size / 2, rounded: false) }
                    HStack(spacing: 0) { SavedArtwork(item: items[2], size: size / 2, rounded: false); SavedArtwork(item: items[3], size: size / 2, rounded: false) }
                }
            } else if let f = items.first {
                SavedArtwork(item: f, size: size, rounded: false)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: p.symbol).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: theme.pixel ? 0 : 18, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if p.isFavorites && !items.isEmpty {
                Image(systemName: "heart.fill").font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                    .padding(7).background(Circle().fill(Color(hex: 0xFF4D6D))).offset(x: 6, y: 6)
            }
        }
    }
}

struct PlaylistList: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let p: Playlist

    var body: some View {
        LazyVStack(spacing: theme.pixel ? 3 : 4) {
            ForEach(Array(p.items.enumerated()), id: \.element.id) { i, item in
                SavedRow(p: p, item: item, index: i)
            }
            if p.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: p.isFavorites ? "heart" : "music.note.list").font(.system(size: 40))
                        .foregroundStyle(Color(hex: theme.pixel ? 0x3F3F3F : theme.panelDim))
                    TText(p.isFavorites
                          ? "Нажми ♥ у играющего трека — он появится здесь. Можно сохранять и файлы, и треки со всех площадок."
                          : "Добавляй сюда треки кнопкой «+» у играющей песни. Файлы и треки с разных площадок можно смешивать.",
                          size: 13, onPanel: true, align: .center)
                        .frame(maxWidth: 460)
                }
                .padding(40)
            }
        }
    }
}

struct SavedRow: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let p: Playlist
    let item: SavedTrack
    let index: Int
    @State private var hover = false

    var body: some View {
        let active = m.queue?.playlistID == p.id && m.isQueued(item.id)
        HStack(spacing: 12) {
            ZStack {
                if active && m.isPlaying {
                    Image(systemName: "waveform").font(.system(size: 12, weight: .bold)).symbolEffect(.variableColor.iterative)
                } else if hover {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                } else if theme.pixel {
                    MCText("\(index + 1)", size: 7, color: 0x3F3F3F, shadow: false)
                } else {
                    Text("\(index + 1)").font(theme.body(12).monospacedDigit())
                }
            }
            .foregroundStyle(Color(hex: active ? theme.onAccent : theme.panelDim))
            .frame(width: 24)
            SavedArtwork(item: item, size: 40)
            VStack(alignment: .leading, spacing: theme.pixel ? 7 : 3) {
                if theme.pixel {
                    MCText(item.title, size: 9).lineLimit(1)
                    MCText(item.artist.isEmpty ? "Неизвестный исполнитель" : item.artist, size: 7, color: 0xE0E0E0).lineLimit(1)
                } else {
                    Text(item.title).font(theme.body(14)).lineLimit(1)
                        .foregroundStyle(Color(hex: active ? theme.onAccent : theme.panelText))
                    Text(item.artist.isEmpty ? "Неизвестный исполнитель" : item.artist).font(theme.body(11)).lineLimit(1)
                        .foregroundStyle(Color(hex: active ? theme.onAccent : theme.panelDim, alpha: 0.9))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SourceTag(item: item, active: active)
            if theme.pixel {
                MCText(fmtTime(item.duration), size: 8)
            } else {
                Text(fmtTime(item.duration)).font(theme.body(11).monospacedDigit())
                    .foregroundStyle(Color(hex: active ? theme.onAccent : theme.panelDim))
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(theme.pixel ? 6 : 8)
        .background {
            if theme.pixel {
                BevelBox(fill: active ? 0x5B8C32 : hover ? 0xA5A5A5 : 0x8B8B8B, light: 0x373737, dark: 0xFFFFFF, border: nil)
            } else {
                RoundedRectangle(cornerRadius: min(theme.radius * 0.6, 14), style: .continuous)
                    .fill(active ? AnyShapeStyle(LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                                               startPoint: .leading, endPoint: .trailing))
                                 : AnyShapeStyle(Color(hex: theme.panelText, alpha: hover ? 0.1 : 0.04)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { m.playPlaylist(p.id, at: index, shuffled: false) }
        .onHover { hover = $0 }
        .contextMenu {
            Button("Играть отсюда") { m.playPlaylist(p.id, at: index, shuffled: false) }
            Button("Выше") { m.moveItem(item.id, in: p.id, by: -1) }.disabled(index == 0)
            Button("Ниже") { m.moveItem(item.id, in: p.id, by: 1) }.disabled(index == p.items.count - 1)
            let others = m.playlists.filter { $0.id != p.id }
            if !others.isEmpty {
                Menu("Копировать в плейлист") {
                    ForEach(others) { o in
                        Button(o.name) { m.copy(item, to: o.id) }
                    }
                }
            }
            if let u = item.fileURL {
                Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
            }
            if case .web(_, _, let link?) = item.source, let u = URL(string: link) {
                Button("Открыть страницу трека в браузере") { NSWorkspace.shared.open(u) }
            }
            Divider()
            Button(p.isFavorites ? "Убрать из любимых" : "Убрать из плейлиста") { m.removeItem(item.id, from: p.id) }
        }
    }
}

extension PlayerModel {
    func copy(_ item: SavedTrack, to playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        if playlists[i].items.contains(where: { $0.key == item.key }) { announce("Уже есть в «\(playlists[i].name)»"); return }
        var c = item
        c.id = UUID()
        c.added = Date()
        playlists[i].items.append(c)
        announce("Добавлено в «\(playlists[i].name)»")
    }
}

/// Откуда трек: «Файл · MP3» или «Spotify · мой спотик».
struct SourceTag: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let item: SavedTrack
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            switch item.source {
            case .file(let path):
                Image(systemName: "doc.fill").font(.system(size: 10, weight: .bold))
                label("Файл · " + URL(fileURLWithPath: path).pathExtension.uppercased())
            case .web(let pl, let acc, _):
                PlatformBadge(platform: pl, size: 16)
                label(pl.title + (acc.flatMap { m.account($0)?.name }.map { " · " + $0 } ?? ""))
            }
        }
        .foregroundStyle(Color(hex: active ? theme.onAccent : theme.panelDim))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background {
            if !theme.pixel { Capsule().fill(Color(hex: active ? 0xFFFFFF : theme.panelText, alpha: active ? 0.2 : 0.07)) }
        }
        .frame(maxWidth: 230, alignment: .trailing)
    }

    @ViewBuilder private func label(_ s: String) -> some View {
        if theme.pixel { MCText(s, size: 7, color: 0x2B2B2B, shadow: false).lineLimit(1) } else {
            Text(s).font(theme.body(11)).lineLimit(1)
        }
    }
}

// MARK: - Настройки

struct SettingsPage: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        PageCard {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(title: "Настройки", subtitle: "Оформление, скорость работы и звук")
                HStack(spacing: 8) {
                    ForEach(SettingsTab.allCases) { t in
                        TButton(t.title, icon: t.symbol, prominent: m.settingsTab == t) { m.settingsTab = t }
                    }
                }
            }
        } content: {
            Scrolling {
                SettingsBody().padding(.trailing, 8).padding(.bottom, 10)
            }
        }
    }
}

struct SettingsBody: View {
    @EnvironmentObject var m: PlayerModel

    var body: some View {
        switch m.settingsTab {
        case .general: GeneralSettings()
        case .look: LookSettings()
        case .performance: PerformanceSettings()
        case .sound: SoundSettings()
        case .keys: KeysSettings()
        }
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Окно и уведомления")
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    TToggle(title: "Поверх всех окон", subtitle: "Плеер не прячется за другими программами", isOn: $m.alwaysOnTop)
                    TToggle(title: "Сообщать о новом треке", subtitle: "Короткая надпись «Сейчас играет» внизу", isOn: $m.trackToasts)
                }
                GridRow {
                    TToggle(title: "Искать текст песен сам", subtitle: "Выключи, чтобы искать только по кнопке", isOn: $m.autoLyrics)
                    TToggle(title: "Загружать последний аккаунт", subtitle: "Музыка из него включается без ожидания", isOn: $m.preloadLast)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            SectionLabel(text: "Библиотека").padding(.top, 6)
            HStack(spacing: 10) {
                TButton("Сохранить копию…", icon: "square.and.arrow.up") { m.exportLibrary() }
                TButton("Загрузить копию…", icon: "square.and.arrow.down") { m.importLibrary() }
                Spacer()
            }
            TText("Плейлисты и «Любимые» сохраняются сами, а прошлая версия всегда остаётся резервной копией. Копию библиотеки можно открыть в версии для Android или Windows.",
                  size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
                .fixedSize(horizontal: false, vertical: true)
            SectionLabel(text: "Размер обложки").padding(.top, 6)
            TSegmented(options: CoverSize.allCases.map { ($0, $0.title) }, value: $m.coverSize)
            SectionLabel(text: "Подсветка текста песни").padding(.top, 6)
            TSegmented(options: KaraokeMode.allCases.map { ($0, $0.title) }, value: $m.karaokeMode)
            TText("«По буквам» — как в караоке, буквы закрашиваются по ходу песни. «Строка целиком» — текущая строка сразу яркая.",
                  size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
        }
    }
}

struct LookSettings: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Тема — меняет всё оформление")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(Theme.all, id: \.id) { t in
                    ThemeCard(t: t, selected: m.theme == t.id) { m.setTheme(t.id) }
                }
            }
            SectionLabel(text: "Живой фон").padding(.top, 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(BackgroundID.allCases) { b in
                    BackgroundCard(bg: b, selected: m.background == b) { m.background = b }
                }
            }
            SectionLabel(text: "Раскладка экрана").padding(.top, 8)
            HStack(spacing: 12) {
                ForEach(StageLayout.allCases) { l in
                    OptionCard(symbol: l.symbol, title: l.title, subtitle: l.subtitle, selected: m.stageLayout == l) { m.stageLayout = l }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            SectionLabel(text: "Красота").padding(.top, 8)
            TSlider(value: $m.textScale, range: 0.6...1.6, step: 0.1) { "Размер текста песни: \(Int(($0 * 100).rounded()))%" }
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    TToggle(title: "Свечение текста и обложки", subtitle: "Мягкий неоновый ореол", isOn: $m.visual.glow)
                    TToggle(title: "Стеклянные панели", subtitle: "Размытие фона под меню и плеером", isOn: $m.visual.glass)
                }
                GridRow {
                    TToggle(title: "Размытие соседних строк", subtitle: "Фокус на текущей строке", isOn: $m.visual.blurLines)
                    TToggle(title: "Пульс под басы", subtitle: "Текст и обложка «дышат» в такт", isOn: $m.visual.bassPulse)
                }
                GridRow {
                    TToggle(title: "Крутящаяся пластинка", subtitle: "Выезжает из-за обложки", isOn: $m.visual.vinylSpin)
                    TToggle(title: "Ноты, сердечки и молнии", subtitle: "Вспышки на ударах", isOn: $m.visual.particles)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            TText("Для музыки из аккаунтов фон двигается плавно сам: звук сайтов приложению недоступен.",
                  size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
        }
    }
}

struct OptionCard: View {
    @Environment(\.theme) private var theme
    let symbol: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(hex: selected ? (theme.pixel ? 0x80FF20 : theme.accent) : (theme.pixel ? 0x3F3F3F : theme.panelText)))
                TText(title, size: 14, title: true, onPanel: true)
                TText(subtitle, size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 92)
            .padding(12)
            .background {
                if theme.pixel {
                    BevelBox(fill: selected ? 0xA8D58A : (hover ? 0xB9C3F7 : 0xB5B5B5), light: 0xE0E0E0, dark: 0x6F6F6F, border: nil)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: theme.panelText, alpha: hover ? 0.1 : 0.05))
                }
            }
            .overlay {
                if !theme.pixel {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: selected ? theme.accent : theme.border, alpha: selected ? 1 : 0.2), lineWidth: selected ? 2.5 : 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
    }
}

struct PerformanceSettings: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    @StateObject private var load = ResourceMonitor()
    @State private var cacheSize = LyricsCache.size()
    @State private var artSize = ArtworkLoader.diskSize()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Режим")
            HStack(spacing: 12) {
                ForEach(PerfMode.allCases) { p in
                    OptionCard(symbol: p.symbol, title: p.title, subtitle: p.subtitle, selected: m.perfMode == p) { m.applyPerf(p) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if m.perfMode == nil {
                TText("Сейчас свой набор настроек.", size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
            }

            SectionLabel(text: "Анимация").padding(.top, 6)
            TSegmented(options: [(30, "30 кадров"), (60, "60 кадров"), (0, "Как у экрана")], value: $m.visual.fps)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    TToggle(title: "Живой фон", subtitle: "Выключи, и фон станет картинкой", isOn: $m.visual.liveBackground)
                    TToggle(title: "Пауза, когда окна не видно", subtitle: "Свернул или закрыл другими окнами — не рисуем", isOn: $m.pauseHidden)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            SectionLabel(text: "Аккаунты").padding(.top, 6)
            TText("Каждый загруженный аккаунт — это отдельный сайт в памяти (обычно 200–500 МБ). Неактивные можно выгружать: вход сохранится, аккаунт загрузится снова, когда нажмёшь на него.",
                  size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
            TSegmented(options: [(0, "Не выгружать"), (5, "Через 5 мин"), (20, "Через 20 мин"), (60, "Через час")], value: $m.unloadAfter)
            TToggle(title: "Загружать последний аккаунт при запуске",
                    subtitle: "Тогда музыка из него включается сразу, без ожидания", isOn: $m.preloadLast)

            SectionLabel(text: "Нагрузка сейчас").padding(.top, 6)
            HStack(spacing: 12) {
                stat("Процессор", load.cpuText, "gauge.with.dots.needle.33percent")
                stat("Память", load.memText, "memorychip")
                stat("Аккаунтов в памяти", "\(m.loadedSessions.count) из \(m.accounts.count)", "person.2.fill")
            }
            HStack(spacing: 10) {
                TText("Сохранённые тексты: \(fmtBytes(cacheSize))",
                      size: 12, onPanel: true)
                Spacer()
                TButton("Очистить тексты", icon: "trash") { LyricsCache.clear(); cacheSize = LyricsCache.size() }
            }
            HStack(spacing: 10) {
                TText("Сохранённые обложки: \(fmtBytes(artSize))",
                      size: 12, onPanel: true)
                Spacer()
                TButton("Очистить обложки", icon: "trash") { ArtworkLoader.clearDisk(); artSize = ArtworkLoader.diskSize() }
            }
        }
        .onAppear { load.start() }
        .onDisappear { load.stop() }
    }

    private func stat(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(hex: theme.pixel ? 0x3F3F3F : theme.accent))
            TText(value, size: 18, title: true, onPanel: true)
            TText(title, size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            if theme.pixel { BevelBox(fill: 0xB5B5B5, light: 0x8B8B8B, dark: 0xE0E0E0, border: nil) } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: theme.panelText, alpha: 0.05))
            }
        }
    }
}

/// Сколько тратит сама программа: процессор (в % одного ядра) и память.
@MainActor
final class ResourceMonitor: ObservableObject {
    @Published var cpu: Double = -1
    @Published var mem: Double = 0
    private var timer: Timer?
    private var lastCPU = 0.0
    private var lastTime = Date()

    var cpuText: String { cpu < 0 ? "…" : String(format: "%.0f%%", cpu) }
    var memText: String { mem <= 0 ? "…" : String(format: "%.0f МБ", mem) }

    func start() {
        guard timer == nil else { return }
        sample()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        var ru = rusage()
        getrusage(RUSAGE_SELF, &ru)
        let t = Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6
            + Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6
        let now = Date()
        let dt = now.timeIntervalSince(lastTime)
        if lastCPU > 0 && dt > 0.5 { cpu = max(0, (t - lastCPU) / dt * 100) }
        lastCPU = t
        lastTime = now

        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kr == KERN_SUCCESS { mem = Double(info.phys_footprint) / 1_048_576 }
    }
}

struct SoundSettings: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    TSlider(value: $m.volume, range: 0...1, step: 0.05) { "Громкость: \(Int(($0 * 100).rounded()))%" }
                    TSlider(value: $m.bass, range: -10...24, step: 1) { $0 == 0 ? "Басы: выкл" : String(format: "Басы: %+.0f дБ", $0) }
                }
                GridRow {
                    TSlider(value: $m.bassFreq, range: 40...250, step: 5) { "Частота басов: \(Int($0)) Гц" }
                    TSlider(value: $m.treble, range: -10...12, step: 1) { $0 == 0 ? "Высокие: норма" : String(format: "Высокие: %+.0f дБ", $0) }
                }
            }
            SectionLabel(text: "Басы, быстрый выбор").padding(.top, 6)
            HStack(spacing: 8) {
                ForEach([("Выкл", 0.0), ("Лёгкие", 6.0), ("Мощные", 12.0), ("Землетрясение", 20.0)], id: \.1) { name, v in
                    TButton(name, prominent: m.bass == v, width: 160) { m.bass = v }
                }
            }
            TText("Басы и эквалайзер работают для файлов. Музыку из аккаунтов играют сами сайты, и её звук приложение не меняет.",
                  size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
        }
    }
}

struct KeysSettings: View {
    @Environment(\.theme) private var theme

    private let keys: [(String, String)] = [
        ("Пробел", "пауза / играть"), ("← →", "перемотка на 5 секунд"), ("↑ ↓", "громкость"),
        ("N / B", "следующий / предыдущий трек"), ("R / S", "повтор / перемешка"), ("E", "мои файлы"),
        ("L", "весь текст и поиск"), ("Esc", "закрыть окно / назад / настройки"), ("1–9", "кнопки хотбара (в теме «Майнкрафт»)"),
        ("F3", "отладка: источник, нагрузка, текст"), ("⌘O / ⇧⌘O", "открыть файлы / папку"), ("⌘ ← / ⌘ →", "предыдущий / следующий трек"),
        ("⇧⌘A", "подключить площадку"), ("⌘ ,", "настройки"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(keys, id: \.0) { k, v in
                HStack(spacing: 14) {
                    TText(k, size: 13, title: true, onPanel: true).frame(width: 150, alignment: .leading)
                    TText(v, size: 13, color: theme.pixel ? 0x3F3F3F : theme.panelDim, onPanel: true)
                }
            }
            TText("Клавиши не мешают печатать: когда открыт сайт площадки или поле ввода, они работают как обычно.",
                  size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true).padding(.top, 8)
        }
    }
}

struct ThemeCard: View {
    let t: Theme
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: t.preview.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text("Аа")
                        .font(t.title(30))
                        .foregroundStyle(Color(hex: t.pixel ? 0xFFFF55 : t.sung))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .padding(10)
                }
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: t.pixel ? 0 : 12, style: .continuous))
                Text(t.name).font(t.title(15)).foregroundStyle(Color.primary)
                Text(t.tagline).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.secondary).lineLimit(2)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .windowBackgroundColor).opacity(0.92)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Color(hex: t.accent) : Color.white.opacity(hover ? 0.4 : 0.12), lineWidth: selected ? 3 : 1.5))
            .scaleEffect(hover ? 1.02 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .environment(\.colorScheme, .dark)
    }
}

struct BackgroundCard: View {
    let bg: BackgroundID
    let selected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                SceneView(background: bg, preview: true, paused: !(hover || selected))
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: theme.pixel ? 0 : 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: theme.pixel ? 0 : 12, style: .continuous)
                        .strokeBorder(selected ? Color(hex: theme.pixel ? 0x80FF20 : theme.accent) : .clear, lineWidth: 3))
                TText(bg.title, size: 12, onPanel: true, align: .center).lineLimit(1)
            }
            .scaleEffect(hover ? 1.03 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

// MARK: - Окна поверх

struct ModalHost: View {
    @EnvironmentObject var m: PlayerModel
    let modal: Modal

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { m.modal = nil }
            switch modal {
            case .lyrics: LyricsPanel()
            case .addAccount: AddAccountSheet()
            case .pasteLyrics: PasteLyricsSheet()
            case .newPlaylist(let add): NewPlaylistSheet(addCurrent: add)
            }
        }
    }
}

// MARK: - Весь текст и поиск

struct LyricsPanel: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    private var offset: Binding<Double> {
        Binding(get: { m.lyricsEntry?.offset ?? 0 }, set: { m.setOffset($0) })
    }

    var body: some View {
        let title = m.nowPlaying.map { ($0.artist.isEmpty ? "" : $0.artist + " - ") + $0.title } ?? "Текст песни"
        TPanel(title: title, width: 720, height: 640, onClose: { m.modal = nil }) {
            LyricsPage()
            HStack(spacing: 8) {
                TField(text: $m.searchQuery, placeholder: "Исполнитель Название") { m.searchManual() }
                TButton("Найти", icon: "magnifyingglass", prominent: true) { m.searchManual() }
                TButton("Другой", icon: "arrow.triangle.2.circlepath") { m.nextResult() }
            }
            HStack(spacing: 8) {
                TSlider(value: offset, range: -5...5, step: 0.1) { String(format: "Сдвиг текста: %+.1f с", $0) }
                TButton("Вставить свой", icon: "doc.on.clipboard") { m.modal = .pasteLyrics }
                TButton("Файл .lrc", icon: "doc.text") { m.chooseLRC() }
            }
            HStack(spacing: 8) {
                TText(m.status, size: 11, color: theme.pixel ? 0x3F3F3F : theme.panelDim, onPanel: true).lineLimit(2)
                Spacer()
                if m.lyricsOffline { TButton("Повторить", icon: "arrow.clockwise") { m.retryLyrics() } }
                TButton("Искать в интернете", icon: "safari") { m.searchLyricsInBrowser() }
            }
        }
    }
}

struct LyricsPage: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        let paper = theme.pixel
        Group {
            if let l = m.lyricsEntry?.lyrics {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let idx = m.lyricFrame(time: m.currentTime())?.index ?? -1
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: paper ? 9 : 10) {
                                ForEach(l.lines) { line in
                                    lineView(line, active: line.id == idx)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if l.synced { m.seek(to: line.time - (m.lyricsEntry?.offset ?? 0) + 0.05) }
                                        }
                                        .id(line.id)
                                }
                            }
                            .padding(.trailing, 10)
                        }
                        .onChange(of: idx) { _, new in
                            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(new, anchor: .center) }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    TText(m.nowPlaying == nil ? "Сначала включи песню." : (m.status.isEmpty ? "Текста пока нет." : m.status),
                          size: 14, color: paper ? 0x3F2A14 : nil, onPanel: true, align: .center)
                        .frame(maxWidth: .infinity)
                    if m.nowPlaying != nil {
                        TText("Если текста нет ни в одной базе: найди его в интернете, скопируй и нажми «Вставить свой».",
                              size: 11, color: paper ? 0x5A4A2A : theme.panelDim, onPanel: true, align: .center)
                            .frame(maxWidth: 480)
                    }
                    Spacer()
                }
            }
        }
        .padding(paper ? 20 : 14)
        .frame(maxWidth: .infinity)
        .frame(height: 330)
        .background {
            if paper {
                ZStack {
                    Color(hex: 0xF3E6C0)
                    Rectangle().strokeBorder(Color(hex: 0xD9C79B), lineWidth: 2).padding(8)
                }
                .overlay(Rectangle().strokeBorder(Color(hex: 0x6B4A2B), lineWidth: 5))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: theme.panelText, alpha: 0.05))
            }
        }
    }

    @ViewBuilder private func lineView(_ line: LyricLine, active: Bool) -> some View {
        let text = line.text.isEmpty ? "..." : line.text
        if theme.pixel {
            MCText(text, size: 9, color: active ? 0xAA0000 : 0x2B2B2B, shadow: false)
        } else {
            Text(text)
                .font(active ? theme.title(17) : theme.body(15))
                .foregroundStyle(Color(hex: active ? theme.accent : theme.panelText, alpha: active ? 1 : 0.75))
        }
    }
}

// MARK: - Вставить свой текст

struct PasteLyricsSheet: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    @State private var text = ""
    @State private var error = ""

    var body: some View {
        TPanel(title: "Свой текст песни", width: 640, height: 600, onClose: { m.modal = nil }) {
            TText("Вставь текст песни (⌘V). Если в нём есть время строк вида [01:23.45], текст пойдёт точно под музыку. Если нет — строки распределятся по длине песни, а сдвиг можно подправить.",
                  size: 12, color: theme.pixel ? 0x3F3F3F : theme.panelDim, onPanel: true)
            TextEditor(text: $text)
                .font(theme.pixel ? .system(size: 13, design: .monospaced) : theme.body(14))
                .scrollContentBackground(.hidden)
                .foregroundStyle(Color(hex: theme.pixel ? 0xE0E0E0 : theme.panelText))
                .padding(10)
                .background {
                    if theme.pixel { Color.black } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: theme.panelText, alpha: 0.08))
                    }
                }
                .frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                TButton("Вставить из буфера", icon: "doc.on.clipboard") {
                    if let s = NSPasteboard.general.string(forType: .string) { text = s }
                }
                TButton("Искать в интернете", icon: "safari") { m.searchLyricsInBrowser() }
                Spacer()
                if !error.isEmpty { TText(error, size: 11, color: 0xFF5C5C, onPanel: true) }
                TButton("Сохранить", icon: "checkmark", prominent: true) {
                    if m.pasteLyrics(text) { m.modal = nil } else { error = m.nowPlaying == nil ? "Сначала включи песню" : "Здесь нет текста" }
                }
            }
        }
    }
}

// MARK: - Новый плейлист

struct NewPlaylistSheet: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let addCurrent: Bool
    @State private var name = ""

    var body: some View {
        TPanel(title: "Новый плейлист", width: 480, onClose: { m.modal = nil }) {
            TField(text: $name, placeholder: "Название, например «В дорогу»") { create() }
            if addCurrent, let np = m.nowPlaying {
                TText("Сразу добавлю: \(np.artist.isEmpty ? "" : np.artist + " — ")\(np.title)", size: 12,
                      color: theme.pixel ? 0x3F3F3F : theme.panelDim, onPanel: true).lineLimit(1)
            }
            HStack {
                Spacer()
                TButton("Отмена") { m.modal = nil }
                TButton("Создать", icon: "plus", prominent: true) { create() }
            }
        }
    }

    private func create() {
        let id = m.createPlaylist(name, addCurrent: addCurrent)
        m.modal = nil
        if !addCurrent { m.show(.playlist(id)) }
    }
}

// MARK: - Подключение площадок

struct AddAccountSheet: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        TPanel(title: "Подключить музыку", width: 800, onClose: { m.modal = nil }) {
            TText("Выбери площадку и войди в аккаунт. Можно подключать сколько угодно аккаунтов на каждой: у каждого своя отдельная сессия.",
                  size: 12, color: theme.pixel ? 0x3F3F3F : theme.panelDim, onPanel: true)
                .fixedSize(horizontal: false, vertical: true)
            AddAccountBody()
        }
    }
}

struct AddAccountBody: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Platform.allCases) { p in PlatformTile(p: p) }
            }
            if !m.accounts.isEmpty {
                SectionLabel(text: "Уже подключено").padding(.top, 4)
                Scrolling {
                    VStack(spacing: 6) {
                        ForEach(m.accounts) { a in ConnectedRow(a: a) }
                    }
                }
                .frame(maxHeight: min(CGFloat(m.accounts.count) * 52, 230))
            }
            TText("Музыка играет через официальный плеер площадки прямо в программе, а текст и обложка появляются сами. Вход через Google может не открыться во встроенном окне — тогда входи по почте, телефону или паролю.",
                  size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PlatformTile: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let p: Platform
    @State private var hover = false

    var body: some View {
        let count = m.accounts.filter { $0.platform == p }.count
        Button { m.addAccount(p) } label: {
            HStack(spacing: 14) {
                PlatformBadge(platform: p, size: 48)
                    .shadow(color: Color(hex: p.color, alpha: theme.pixel ? 0 : 0.5), radius: hover ? 12 : 6)
                VStack(alignment: .leading, spacing: 4) {
                    TText(p.title, size: 16, title: true, onPanel: true)
                    TText(p.blurb, size: 11, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
                    TText(count == 0 ? "Не подключено" : "Подключено: \(count)", size: 10,
                          color: count == 0 ? (theme.pixel ? 0x555555 : theme.panelDim) : (theme.pixel ? 0x2E5616 : 0x3DDC84), onPanel: true)
                }
                Spacer(minLength: 0)
                Image(systemName: count == 0 ? "arrow.right.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(hex: p.color))
            }
            .padding(14)
            .background {
                if theme.pixel {
                    BevelBox(fill: hover ? 0xB9C3F7 : 0xB5B5B5, light: 0xE0E0E0, dark: 0x6F6F6F, border: nil)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(hex: p.color, alpha: hover ? 0.2 : 0.1))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color(hex: p.color, alpha: hover ? 0.9 : 0.4), lineWidth: 1.5))
                }
            }
            .scaleEffect(hover ? 1.015 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .tip(count == 0 ? "Войти в \(p.title)" : "Добавить ещё аккаунт \(p.title)", offset: -34)
    }
}

struct ConnectedRow: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let a: Account

    var body: some View {
        let s = m.session(a.id)
        HStack(spacing: 10) {
            PlatformBadge(platform: a.platform, size: 22)
            TText(a.name, size: 13, onPanel: true).lineLimit(1)
            if s?.loggedIn == true {
                TText("✓ вход выполнен", size: 10, color: theme.pixel ? 0x2E5616 : 0x3DDC84, onPanel: true)
            } else if s == nil {
                TText("выгружен", size: 10, color: theme.pixel ? 0x555555 : theme.panelDim, onPanel: true)
            }
            if m.activeWebID == a.id && m.isPlaying {
                Image(systemName: "waveform").foregroundStyle(Color(hex: a.platform.color)).symbolEffect(.variableColor.iterative)
            }
            Spacer()
            TButton("Открыть", icon: "play.rectangle") { m.openAccount(a.id) }
            TButton("Имя", icon: "pencil") { AccountDialogs.rename(a) }
            TButton("Удалить", icon: "trash") { AccountDialogs.remove(a) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background {
            if theme.pixel { BevelBox(fill: 0xB5B5B5, light: 0x8B8B8B, dark: 0xE0E0E0, border: nil) } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: theme.panelText, alpha: 0.05))
            }
        }
    }
}

// MARK: - Окно плеера площадки

struct AccountBrowser: View {
    @EnvironmentObject var m: PlayerModel
    @Environment(\.theme) private var theme
    let session: WebSession
    let open: Bool

    var body: some View {
        let a = m.account(session.accountID)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PlatformBadge(platform: session.platform, size: 24)
                TText("\(session.platform.title) · \(a?.name ?? "")", size: 14, title: true, onPanel: true).lineLimit(1)
                if session.loggedIn == true {
                    TText("✓ вход выполнен", size: 10, color: theme.pixel ? 0x2E5616 : 0x3DDC84, onPanel: true)
                }
                Spacer()
                TIconButton("chevron.left", size: 30, tip: "Назад") { session.webView.goBack() }
                TIconButton("chevron.right", size: 30, tip: "Вперёд") { session.webView.goForward() }
                TIconButton("arrow.clockwise", size: 30, tip: "Обновить") { session.webView.reload() }
                TIconButton("house.fill", size: 30, tip: "Главная музыки") { session.goHome() }
                if session.needsLogin {
                    TButton("Войти", icon: "person.crop.circle") { session.goLogin() }
                }
                TButton("К тексту", icon: "quote.bubble.fill", prominent: true) { m.closeBrowser() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            if session.needsLogin {
                LoginHint(platform: session.platform)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            WebBrowserView(webView: session.webView, visible: open, awake: session.hasJob)
                .clipShape(RoundedRectangle(cornerRadius: theme.pixel ? 0 : 12, style: .continuous))
                .padding([.horizontal, .bottom], 8)
        }
        .background(PanelBackground())
        .padding(.horizontal, Layout.side)
        .padding(.top, Layout.top)
        .padding(.bottom, 12)
        .opacity(open ? 1 : 0)
        .allowsHitTesting(open)
        .scaleEffect(open ? 1 : 0.98)
    }
}

struct LoginHint: View {
    @Environment(\.theme) private var theme
    let platform: Platform

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.key.fill").font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(hex: platform.color))
            TText("Войди в аккаунт \(platform.title) на странице ниже. Как только вход получится, я сам открою музыку и подпишу аккаунт.",
                  size: 12, onPanel: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background {
            if theme.pixel { BevelBox(fill: 0xE0E0A0, light: 0xFFFFD0, dark: 0x8B8B50, border: nil) } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: platform.color, alpha: 0.14))
            }
        }
    }
}
