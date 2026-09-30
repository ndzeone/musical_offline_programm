import AppKit

/// Обновления: кнопка в настройках и проверка сама — через 8 секунд после запуска и раз в 6 часов.
extension PlayerModel {
    private static let every: TimeInterval = 6 * 3600

    var lastUpdateCheck: Date? { Self.d.object(forKey: "lastUpdateCheck") as? Date }

    func startUpdateChecks() {
        NewFeatures.markLaunch()
        guard !LibraryStore.readOnly else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.autoUpdates else { return }
            self.checkUpdates(manual: false)
        }
        let t = Timer(timeInterval: 15 * 60, repeats: true) { _ in
            MainActor.assumeIsolated {
                let m = PlayerModel.shared
                guard m.autoUpdates, Date().timeIntervalSince(m.lastUpdateCheck ?? .distantPast) > Self.every - 60 else { return }
                m.checkUpdates(manual: false)
            }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        updateTimer = t
    }

    func checkUpdates(manual: Bool) {
        guard !updateState.busy else { return }
        updateState = .checking
        Task {
            do {
                let r = try await Updates.fetchLatest()
                Self.d.set(Date(), forKey: "lastUpdateCheck")
                if Updates.compare(r.version, Updates.current) > 0 {
                    updateState = .available(r)
                    if manual { announce("Доступна версия \(r.version)") }
                    else if Self.d.string(forKey: "skipVersion") != r.version, modal == nil { modal = .update }
                } else {
                    updateState = .latest(Date())
                    if manual { announce("У тебя последняя версия \(Updates.current)") }
                }
            } catch {
                updateState = .failed(error.localizedDescription)
                if manual { announce(error.localizedDescription) }
            }
        }
    }

    /// Скачать .dmg, поставить новую программу на место этой и перезапуститься.
    /// Если в папку программы нельзя писать — открываем образ, чтобы перетащить вручную.
    func installUpdate() {
        guard case .available(let r) = updateState else { return }
        guard let dmgURL = r.dmg else { NSWorkspace.shared.open(r.page); return }
        let app = Bundle.main.bundleURL
        let writable = FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
        updateState = .downloading
        Task {
            do {
                let work = try Updates.workDir()
                let dmg = try await Updates.download(dmgURL, into: work)
                guard writable else {
                    NSWorkspace.shared.open(dmg)
                    updateState = .available(r)
                    announce("Перетащи новую программу в «Программы» с заменой")
                    return
                }
                updateState = .installing
                saveSession()
                LibraryStore.flushNow()
                try Updates.install(dmg: dmg, replacing: app, work: work, waitPID: getpid(), relaunch: true)
                try? await Task.sleep(nanoseconds: 300_000_000)
                NSApp.terminate(nil)
            } catch {
                updateState = .failed(error.localizedDescription)
                announce("Не получилось обновиться: \(error.localizedDescription)")
            }
        }
    }

    func skipUpdate() {
        if case .available(let r) = updateState { Self.d.set(r.version, forKey: "skipVersion") }
        modal = nil
        announce("Напомню о следующей версии. Обновиться можно в Настройках")
    }

    var settingsDot: Bool {
        if case .available = updateState { return true }
        return NewFeatures.any
    }
}
