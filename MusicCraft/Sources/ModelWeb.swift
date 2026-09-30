import SwiftUI
import WebKit

// MARK: - Аккаунты и сессии площадок

extension PlayerModel {
    func addAccount(_ p: Platform) {
        let n = accounts.filter { $0.platform == p }.count + 1
        let a = Account(id: UUID(), platform: p, name: "\(p.short) \(n)", autoNamed: true)
        accounts.append(a)
        modal = nil
        openAccount(a.id, login: true)
    }

    /// Сессия создаётся при первом обращении и дальше живёт скрытой, пока не выгрузим её за ненадобностью.
    @discardableResult
    func ensureSession(_ id: UUID, login: Bool = false) -> WebSession? {
        if let s = sessions[id] { return s }
        guard let a = account(id) else { return nil }
        let s = WebSession(account: a, model: self, startAtLogin: login)
        setSession(s, for: id)
        return s
    }

    func openAccount(_ id: UUID, login: Bool = false) {
        guard let s = ensureSession(id, login: login) else { return }
        s.touch()
        modal = nil
        page = .account(id)
    }

    func closeBrowser() {
        if let id = openAccountID { session(id)?.touch() }
        if case .account = page { page = .stage }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    func renameAccount(_ id: UUID, _ name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        accounts[i].name = n.isEmpty ? accounts[i].platform.short : n
        accounts[i].autoNamed = false
        if activeWebID == id { refreshNowPlaying() }
    }

    func reloadAccount(_ id: UUID) {
        if let s = sessions[id] { s.webView.reload() } else { ensureSession(id) }
    }

    func removeAccount(_ id: UUID) {
        unloadSession(id)
        if activeWebID == id {
            activeWebID = nil
            isPlaying = audio.isPlaying
            refreshNowPlaying()
        }
        if case .account(let open) = page, open == id { page = .stage }
        accounts.removeAll { $0.id == id }
        if lastWebAccount == id { lastWebAccount = nil }
        // Удаляем cookies и вход этого аккаунта (после того как веб-вид освободит хранилище)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            WKWebsiteDataStore.remove(forIdentifier: id) { _ in }
        }
    }

    func unloadSession(_ id: UUID) {
        if let s = sessions[id] { s.shutdown() }
        setSession(nil, for: id)
    }

    /// Аккаунты, которые давно не играли и не открыты, выгружаем: освобождаем память и процессор.
    /// Вход сохраняется, при нажатии аккаунт загрузится снова.
    func unloadIdleSessions() {
        guard unloadAfter > 0 else { return }
        let limit = Double(unloadAfter) * 60
        for (id, s) in sessions {
            guard id != activeWebID, id != openAccountID, !s.state.playing,
                  webExpect?.session != id, Date().timeIntervalSince(s.lastActivity) > limit else { continue }
            unloadSession(id)
        }
    }

    func pauseAllWeb(except keep: UUID? = nil) {
        for (id, s) in sessions where id != keep {
            s.cancelAutoplay()
            s.pause()
        }
    }

    func isLoaded(_ id: UUID) -> Bool { sessions[id] != nil }

    // MARK: События от страниц площадок

    func webStateChanged(_ s: WebSession, trackChanged: Bool, playingChanged: Bool) {
        let id = s.accountID
        // Трек из нашего плейлиста: ждём, пока заиграет, и переходим к следующему, когда закончится
        if var e = webExpect, e.session == id {
            let same = Self.sameSong(s.state.title, s.state.artist, e.title, e.artist)
            if !e.confirmed {
                if same && s.state.playing {
                    e.confirmed = true
                    webExpect = e
                    queueFailures = 0
                    refreshNowPlaying()
                }
            } else if !same || s.state.ended {
                webExpect = nil
                if queue != nil {
                    s.pause()
                    advanceQueue(1, auto: true)
                    return
                }
            }
        }

        if s.state.playing && activeWebID != id {
            let expected = webExpect?.session == id || s.hasJob || Date().timeIntervalSince(s.lastCommand) < 5
            if !expected && openAccountID != id {
                // Скрытая площадка заиграла сама (восстановила прошлый трек, автоплей) — не даём ей перебить музыку
                s.forcePause()
                return
            }
            // Включили музыку прямо на сайте — это становится источником, очередь плейлиста заканчивается
            if webExpect?.session != id { queue = nil; webExpect = nil }
            if audio.isPlaying { audio.pause() }
            pauseAllWeb(except: id)
            activeWebID = id
            lastWebAccount = id
            refreshNowPlaying()
        } else if activeWebID == id && trackChanged {
            refreshNowPlaying()
        }
        if activeWebID == id {
            if isPlaying != s.state.playing { isPlaying = s.state.playing }
            if s.state.playing && playingChanged { s.setVolume(volume) }
        }
    }

    func webArtworkChanged(_ s: WebSession) {
        if activeWebID == s.accountID { refreshNowPlaying() }
    }

    func webLoggedIn(_ s: WebSession) {
        announce("Вход в \(s.platform.title) выполнен ✓")
    }

    func webDetectedName(_ s: WebSession, _ name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == s.accountID }), accounts[i].autoNamed else { return }
        accounts[i].name = name
        accounts[i].autoNamed = false
        if activeWebID == s.accountID { refreshNowPlaying() }
    }

    func webAutoplayFailed(_ s: WebSession) {
        guard let e = webExpect, e.session == s.accountID, !e.confirmed else { return }
        if queue != nil {
            // В плейлисте музыка не должна вставать: этот трек пропускаем
            announce("Не получилось включить «\(e.title)» — включаю следующий")
            webExpect = nil
            skipSoon()
        } else {
            announce("Площадка не дала включить «\(e.title)» сама — нажми ▶ на странице")
            page = .account(s.accountID)
        }
    }
}
