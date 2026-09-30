import SwiftUI
import UniformTypeIdentifiers

// MARK: - Текст песни: файл рядом → сохранённый → теги → lrclib / NetEase (с повторами при сбоях связи)

extension PlayerModel {
    func cacheURL(_ np: NowPlaying) -> URL {
        switch np.origin {
        case .local(let id): return LyricsCache.url(for: track(id)?.url ?? URL(fileURLWithPath: np.key))
        case .web: return LyricsCache.url(forKey: np.key)
        }
    }

    func ensureLyrics(_ np: NowPlaying) {
        if let e = lyricsDB[np.key], let l = e.lyrics {
            status = "Текст: \(e.source)" + (l.synced ? "" : " (без тайминга, примерно)")
            return
        }
        guard !lyricsLoading.contains(np.key) else { return }
        lyricsLoading.insert(np.key)
        Task {
            await loadLyrics(np)
            lyricsLoading.remove(np.key)
        }
    }

    func setLyrics(_ key: String, _ l: Lyrics, _ source: String, duration: Double) {
        var e = lyricsDB[key] ?? SongLyrics()
        if let o = lyricOffsets[key] { e.offset = o }
        e.plain = l.synced ? nil : l
        e.lyrics = l.synced ? l : l.estimated(duration: duration)
        e.source = source
        lyricsDB[key] = e
        if key == nowPlaying?.key {
            status = "Текст: \(source)" + (l.synced ? "" : " (без тайминга, примерно)")
            lyricsOffline = false
        }
    }

    private func loadLyrics(_ start: NowPlaying) async {
        var np = start
        if case .local(let id) = np.origin {
            await loadMeta(id)
            if let t = track(id) { np.title = t.title; np.artist = t.artist; np.duration = t.duration }
        }
        if case .local(let id) = np.origin, let t = track(id) {
            let sibling = t.url.deletingPathExtension().appendingPathExtension("lrc")
            if let s = readText(sibling), let l = LyricsParser.parse(s) {
                setLyrics(np.key, l, "файл \(sibling.lastPathComponent)", duration: np.duration); return
            }
        }
        if let s = readText(cacheURL(np)), let l = LyricsParser.parse(s) {
            setLyrics(np.key, l, "сохранённый текст", duration: np.duration); return
        }
        if case .local(let id) = np.origin {
            if track(id)?.metaLoaded == false { await loadMeta(id) }
            if let e = track(id)?.embeddedLyrics, let l = LyricsParser.parse(e) {
                setLyrics(np.key, l, "из тегов файла", duration: np.duration)
                if l.synced { return }
            }
        }
        guard autoLyrics else {
            if nowPlaying?.key == np.key { status = "Автопоиск текста выключен в настройках. Нажми «Найти текст»." }
            return
        }
        await searchOnline(np, query: nil)
    }

    func searchManual() {
        guard let np = nowPlaying else { status = "Сначала включи песню."; return }
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        Task { await searchOnline(np, query: q) }
    }

    /// Кнопка «Повторить», когда не было связи.
    func retryLyrics() {
        guard let np = nowPlaying else { return }
        Task { await searchOnline(np, query: nil) }
    }

    func nextResult() {
        guard let np = nowPlaying, var e = lyricsDB[np.key], e.results.count > 1 else {
            status = "Других вариантов нет."
            return
        }
        e.resultIndex = (e.resultIndex + 1) % e.results.count
        lyricsDB[np.key] = e
        applyResult(np, manual: true)
    }

    func setOffset(_ v: Double) {
        guard let key = nowPlaying?.key else { return }
        var e = lyricsDB[key] ?? SongLyrics()
        e.offset = v
        lyricsDB[key] = e
        lyricOffsets[key] = abs(v) < 0.05 ? nil : v
    }

    private func searchOnline(_ np: NowPlaying, query: String?, attempt: Int = 0) async {
        let isCur = { self.nowPlaying?.key == np.key }
        if isCur() { status = "Ищу текст…"; lyricsOffline = false }
        do {
            let list = try await LyricsSearch.find(artist: np.artist, title: np.title, duration: np.duration, query: query)
            guard !list.isEmpty else {
                if isCur() {
                    status = lyricsDB[np.key]?.lyrics == nil
                        ? "Текст не найден ни в одной базе. Можно поискать вручную или вставить свой текст."
                        : "Синхронный текст не найден, показываю текст из файла."
                }
                return
            }
            if query == nil, lyricsDB[np.key]?.lyrics != nil, list[0].syncedLyrics == nil {
                if isCur() { status = "Текст: из тегов файла (без тайминга)" }
                return
            }
            var e = lyricsDB[np.key] ?? SongLyrics()
            e.results = list
            e.resultIndex = 0
            lyricsDB[np.key] = e
            applyResult(np, manual: query != nil)
        } catch {
            guard isCur() else { return }
            lyricsOffline = true
            // Сбой связи: пробуем ещё раз сами, пока играет эта же песня
            let delays = [4.0, 12.0, 30.0]
            if attempt < delays.count {
                status = "Нет связи с сервером текстов. Повторю через \(Int(delays[attempt])) с…"
                try? await Task.sleep(nanoseconds: UInt64(delays[attempt] * 1e9))
                if isCur() && lyricsDB[np.key]?.lyrics == nil {
                    await searchOnline(np, query: query, attempt: attempt + 1)
                }
            } else {
                status = "Нет связи с сервером текстов. Проверь интернет и нажми «Повторить»."
            }
        }
    }

    private func applyResult(_ np: NowPlaying, manual: Bool) {
        guard let e = lyricsDB[np.key], e.results.indices.contains(e.resultIndex) else { return }
        let r = e.results[e.resultIndex]
        guard let text = r.syncedLyrics ?? r.plainLyrics, let l = LyricsParser.parse(text) else { return }
        if l.synced || manual { try? text.write(to: cacheURL(np), atomically: true, encoding: .utf8) }
        setLyrics(np.key, l, "\(r.artistName ?? "?") - \(r.trackName ?? "?") (\(r.provider), вариант \(e.resultIndex + 1) из \(e.results.count))",
                  duration: np.duration)
    }

    /// Свой текст: вставленный из буфера обмена. С таймингом [мм:сс] — синхронный, без — строки пойдут примерно.
    @discardableResult
    func pasteLyrics(_ text: String) -> Bool {
        guard let np = nowPlaying, let l = LyricsParser.parse(text) else { return false }
        try? text.write(to: cacheURL(np), atomically: true, encoding: .utf8)
        setLyrics(np.key, l, "вставлен вручную", duration: np.duration)
        announce(l.synced ? "Текст сохранён" : "Текст сохранён, строки пойдут примерно по времени")
        return true
    }

    /// Поиск текста в браузере — когда его нет ни в одной базе.
    func searchLyricsInBrowser() {
        guard let np = nowPlaying else { return }
        let q = [np.artist, np.title, "текст песни"].filter { !$0.isEmpty }.joined(separator: " ")
        var c = URLComponents(string: "https://yandex.ru/search/")!
        c.queryItems = [URLQueryItem(name: "text", value: q)]
        if let u = c.url { NSWorkspace.shared.open(u) }
    }

    func chooseLRC() {
        guard let np = nowPlaying else { status = "Сначала включи песню."; return }
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText, .plainText]
        if case .local(let id) = np.origin, let t = track(id) { p.directoryURL = t.url.deletingLastPathComponent() }
        p.prompt = "Загрузить текст"
        guard p.runModal() == .OK, let u = p.url else { return }
        guard let text = readText(u), let l = LyricsParser.parse(text) else { status = "В этом файле нет текста."; return }
        try? text.write(to: cacheURL(np), atomically: true, encoding: .utf8)
        setLyrics(np.key, l, "файл \(u.lastPathComponent)", duration: np.duration)
    }

    func lyricFrame(time: Double) -> LyricFrame? {
        guard let e = lyricsEntry, let ly = e.lyrics, !ly.lines.isEmpty else { return nil }
        let L = ly.lines, tm = time + e.offset
        var idx = -1, lo = 0, hi = L.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if L[mid].time <= tm { idx = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        var sung = 0
        if idx >= 0 && ly.synced {
            let text = L[idx].text.isEmpty ? "..." : L[idx].text
            let start = L[idx].time, end = idx + 1 < L.count ? L[idx + 1].time : start + 5
            let dur = min(max(end - start, 0.3), 10)
            let p = min(1, max(0, (tm - start) / (dur * 0.85)))
            sung = Int((p * Double(text.count)).rounded())
        }
        return LyricFrame(index: idx, lines: L, sung: sung, synced: ly.synced)
    }
}
