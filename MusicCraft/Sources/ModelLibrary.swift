import SwiftUI

// MARK: - Любимые, плейлисты и очередь

extension PlayerModel {
    var favorites: Playlist { playlists.first(where: \.isFavorites) ?? Playlist(id: Playlist.favoritesID, name: "Любимые") }
    var userPlaylists: [Playlist] { playlists.filter { !$0.isFavorites } }

    func playlist(_ id: UUID) -> Playlist? { playlists.first { $0.id == id } }

    private func mutate(_ id: UUID, _ f: (inout Playlist) -> Void) {
        if let i = playlists.firstIndex(where: { $0.id == id }) { f(&playlists[i]) }
    }

    func isFavorite(_ np: NowPlaying?) -> Bool {
        guard let np else { return false }
        return favorites.items.contains { $0.key == np.key }
    }

    func contains(_ playlistID: UUID, _ np: NowPlaying?) -> Bool {
        guard let np, let p = playlist(playlistID) else { return false }
        return p.items.contains { $0.key == np.key }
    }

    /// Текущий трек в виде записи для плейлиста. Для треков площадок узнаём ссылку на страницу трека.
    func currentSaved(_ done: @escaping (SavedTrack?) -> Void) {
        guard let np = nowPlaying else { done(nil); return }
        switch np.origin {
        case .local(let id):
            guard let t = track(id) else { done(nil); return }
            done(SavedTrack(source: .file(path: t.url.standardizedFileURL.path), title: t.title, artist: t.artist,
                            duration: t.duration))
        case .web(let aid):
            guard let a = account(aid) else { done(nil); return }
            let s = session(aid)
            // Снимок в момент нажатия: обложка и альбом именно этого трека
            let snapTitle = s?.state.title ?? "", snapArtist = s?.state.artist ?? ""
            let snapArt = (np.loading ? webExpect?.artURL : s?.artURL) ?? artMap[np.key]
            let snapAlbum = s?.state.album ?? ""
            let make: (String?) -> SavedTrack = { link in
                SavedTrack(source: .web(platform: a.platform, account: aid, link: link), title: np.title, artist: np.artist,
                           album: snapAlbum, duration: np.duration, artURL: snapArt)
            }
            if np.loading, let q = queue?.current, q.key == np.key { done(q); return }
            guard let s else { done(make(nil)); return }
            s.fetchLink { link in
                // Пока ждали ссылку, трек мог смениться — тогда ссылка уже от другого трека, её не берём
                let still = Self.sameSong(s.state.title, s.state.artist, snapTitle, snapArtist)
                done(make(still ? link : nil))
            }
        }
    }

    func toggleFavorite() {
        guard let np = nowPlaying else { announce("Сначала включи песню"); return }
        if isFavorite(np) {
            mutate(Playlist.favoritesID) { $0.items.removeAll { $0.key == np.key } }
            announce("Убрано из любимых")
        } else {
            currentSaved { t in
                guard let t else { return }
                if !self.playlists.contains(where: \.isFavorites) {
                    self.playlists.insert(Playlist(id: Playlist.favoritesID, name: "Любимые"), at: 0)
                }
                self.mutate(Playlist.favoritesID) { p in
                    if !p.items.contains(where: { $0.key == t.key }) { p.items.insert(t, at: 0) }
                }
                self.announce("♥ Добавлено в любимые")
            }
        }
    }

    func addCurrent(to playlistID: UUID) {
        guard let np = nowPlaying, let p = playlist(playlistID) else { return }
        if p.items.contains(where: { $0.key == np.key }) {
            announce("Уже есть в «\(p.name)»")
            return
        }
        currentSaved { t in
            guard let t else { return }
            self.mutate(playlistID) { $0.items.append(t) }
            self.announce("Добавлено в «\(p.name)»")
        }
    }

    @discardableResult
    func createPlaylist(_ name: String, addCurrent add: Bool = false) -> UUID {
        let n = name.trimmingCharacters(in: .whitespaces)
        let p = Playlist(name: n.isEmpty ? "Плейлист \(userPlaylists.count + 1)" : n)
        playlists.append(p)
        if add { addCurrent(to: p.id) }
        return p.id
    }

    func renamePlaylist(_ id: UUID, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        mutate(id) { $0.name = n }
    }

    func deletePlaylist(_ id: UUID) {
        guard id != Playlist.favoritesID else { return }
        playlists.removeAll { $0.id == id }
        if page == .playlist(id) { page = .stage }
        if queue?.playlistID == id { queue = nil }
    }

    func removeItem(_ itemID: UUID, from playlistID: UUID) {
        mutate(playlistID) { $0.items.removeAll { $0.id == itemID } }
    }

    func moveItem(_ itemID: UUID, in playlistID: UUID, by delta: Int) {
        mutate(playlistID) { p in
            guard let i = p.items.firstIndex(where: { $0.id == itemID }) else { return }
            let j = min(max(0, i + delta), p.items.count - 1)
            guard i != j else { return }
            let x = p.items.remove(at: i)
            p.items.insert(x, at: j)
        }
    }

    func moveItems(in playlistID: UUID, from: IndexSet, to: Int) {
        mutate(playlistID) { $0.items.move(fromOffsets: from, toOffset: to) }
    }

    /// Найти обложки заново для всего плейлиста (кнопка «Обновить обложки»).
    func refreshArt(_ playlistID: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        for j in playlists[i].items.indices where playlists[i].items[j].fileURL == nil {
            let key = playlists[i].items[j].key
            playlists[i].items[j].artURL = nil
            artMap[key] = nil
        }
        resolveMissingArt(playlistID)
        announce("Ищу обложки заново…")
    }

    /// Один раз после обновления до 2.3: сверяем сохранённые обложки треков площадок с самим треком
    /// (в старых версиях могла запомниться картинка соседнего трека) и ставим правильную.
    func verifyArtOnce() {
        let flag = "artVerified-2.3"
        guard !UserDefaults.standard.bool(forKey: flag), !LibraryStore.readOnly else { return }
        var seen = Set<String>()
        let todo = playlists.flatMap(\.items).filter { $0.fileURL == nil && seen.insert($0.key).inserted }
        guard !todo.isEmpty else { UserDefaults.standard.set(true, forKey: flag); return }
        Task {
            var fixed = 0
            for t in todo {
                var link: String?
                if case .web(_, _, let l) = t.source { link = l }
                guard let url = await ArtResolver.resolve(title: t.title, artist: t.artist, link: link) else { continue }
                artMap[t.key] = url
                for i in playlists.indices {
                    for j in playlists[i].items.indices where playlists[i].items[j].key == t.key && playlists[i].items[j].artURL != url {
                        playlists[i].items[j].artURL = url
                        fixed += 1
                    }
                }
            }
            UserDefaults.standard.set(true, forKey: flag)
            if fixed > 0 { announce("Обложки в плейлистах проверены и обновлены") }
        }
    }

    /// Картинка по сохранённому адресу больше не открывается — ищем обложку заново.
    func artworkBroken(_ url: String) {
        var touched = Set<UUID>()
        for i in playlists.indices {
            for j in playlists[i].items.indices where playlists[i].items[j].artURL == url {
                artMap[playlists[i].items[j].key] = nil
                playlists[i].items[j].artURL = nil
                touched.insert(playlists[i].id)
            }
        }
        for (k, v) in artMap where v == url { artMap[k] = nil }
        for id in touched { resolveMissingArt(id) }
    }

    /// У треков без обложки находим настоящую (по ссылке на трек или по названию) и запоминаем её в плейлисте.
    func resolveMissingArt(_ playlistID: UUID) {
        guard let p = playlist(playlistID) else { return }
        let todo = p.items.filter { ($0.artURL ?? "").isEmpty && !artResolving.contains($0.key) }
        guard !todo.isEmpty else { return }
        for t in todo { artResolving.insert(t.key) }
        Task {
            for t in todo {
                var url = artMap[t.key]
                if url == nil, let f = t.fileURL, await ArtworkLoader.shared.fetch(f.absoluteString) != nil {
                    artResolving.remove(t.key)
                    continue                                   // у файла есть своя картинка в тегах
                }
                if url == nil {
                    var link: String?
                    if case .web(_, _, let l) = t.source { link = l }
                    url = await ArtResolver.resolve(title: t.title, artist: t.artist, link: link)
                }
                artResolving.remove(t.key)
                guard let url else { continue }
                artMap[t.key] = url
                for i in playlists.indices {
                    for j in playlists[i].items.indices where playlists[i].items[j].key == t.key && (playlists[i].items[j].artURL ?? "").isEmpty {
                        playlists[i].items[j].artURL = url
                    }
                }
            }
        }
    }

    // MARK: Очередь

    func playPlaylist(_ id: UUID, at index: Int? = nil, shuffled: Bool? = nil) {
        guard let p = playlist(id), !p.items.isEmpty else { announce("Плейлист пустой"); return }
        var order = Array(p.items.indices)
        var pos = index ?? 0
        if shuffled ?? shuffle {
            order.shuffle()
            if let i = index, let k = order.firstIndex(of: i) { order.swapAt(0, k) }
            pos = 0
        }
        queue = PlayQueue(playlistID: id, items: p.items, order: order, pos: min(pos, order.count - 1))
        startQueueItem()
    }

    func isQueued(_ itemID: UUID) -> Bool { queue?.current?.id == itemID }

    func startQueueItem() {
        guard let t = queue?.current else { return }
        playSaved(t)
    }

    func advanceQueue(_ delta: Int, auto: Bool) {
        guard var q = queue, !q.order.isEmpty else { return }
        if auto && repeatMode == .one { startQueueItem(); return }
        var p = q.pos + delta
        if p >= q.order.count {
            if auto && repeatMode == .none {
                queue = nil
                isPlaying = false
                announce("Плейлист закончился")
                return
            }
            p = 0
        }
        if p < 0 { p = q.order.count - 1 }
        q.pos = p
        queue = q
        startQueueItem()
    }

    /// Включить трек из плейлиста: файл — нашим плеером, трек площадки — в её плеере нужного аккаунта.
    func playSaved(_ t: SavedTrack) {
        switch t.source {
        case .file(let path):
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path), let id = ensureTrack(url) else {
                announce("Файл не найден: \(url.lastPathComponent)")
                if queue != nil { skipSoon() }
                return
            }
            play(id: id, fromQueue: queue != nil)
        case .web(let platform, let accID, let link):
            let acc = accID.flatMap { account($0) } ?? accounts.first { $0.platform == platform }
            guard let acc, let s = ensureSession(acc.id) else {
                if queue != nil {
                    announce("Пропускаю «\(t.title)»: не подключён \(platform.title)")
                    skipSoon()
                } else {
                    announce("Чтобы включить «\(t.title)», подключи \(platform.title)")
                    modal = .addAccount
                }
                return
            }
            if audio.isPlaying { audio.pause() }
            pauseAllWeb(except: acc.id)
            activeWebID = acc.id
            lastWebAccount = acc.id
            webExpect = WebExpect(title: t.title, artist: t.artist, duration: t.duration, artURL: t.artURL,
                                  session: acc.id, started: Date(), confirmed: false)
            s.openTrack(link: link, title: t.title, artist: t.artist)
            isPlaying = true
            refreshNowPlaying()
        }
    }

    /// Пропустить недоступный трек очереди. Если подряд не играет ни один — останавливаемся, а не крутимся по кругу.
    func skipSoon() {
        queueFailures += 1
        if let q = queue, queueFailures >= q.order.count {
            queue = nil
            queueFailures = 0
            isPlaying = false
            announce("Ни один трек этого плейлиста сейчас не включается")
            return
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if queue != nil { advanceQueue(1, auto: true) }
        }
    }
}
