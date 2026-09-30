import SwiftUI

/// Вся музыка на Mac: поиск Spotlight по всему компьютеру (и подключённым дискам) + проверка,
/// что файлы из «Моих файлов» ещё на месте.
struct ScanResult: Equatable {
    var found: Int
    var fresh: Int
    var missing: Int
}

extension PlayerModel {
    /// Аудиофайлы, которые Spotlight знает на этом Mac (системные звуки, лупы и короткие записи — не считаем)
    func spotlightAudio() async -> [URL] {
        await withCheckedContinuation { (cont: CheckedContinuation<[URL], Never>) in
            let q = NSMetadataQuery()
            q.predicate = NSPredicate(format: "kMDItemContentTypeTree == 'public.audio'")
            q.searchScopes = [NSMetadataQueryLocalComputerScope]
            var token: NSObjectProtocol?
            var done = false
            let finish: () -> Void = {
                guard !done else { return }
                done = true
                q.disableUpdates()
                var out: [URL] = []
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                for i in 0..<q.resultCount {
                    guard let it = q.result(at: i) as? NSMetadataItem,
                          let path = it.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
                    if Self.skipPath(path, home: home) { continue }
                    let ext = (path as NSString).pathExtension.lowercased()
                    guard Self.audioExt.contains(ext) else { continue }
                    if let d = it.value(forAttribute: "kMDItemDurationSeconds") as? Double, d > 0, d < 30 { continue }
                    out.append(URL(fileURLWithPath: path))
                }
                q.stop()
                if let token { NotificationCenter.default.removeObserver(token) }
                cont.resume(returning: out)
            }
            token = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { _ in
                MainActor.assumeIsolated { finish() }
            }
            if !q.start() { finish() }
            // на всякий случай не ждём дольше минуты
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { MainActor.assumeIsolated { finish() } }
        }
    }

    nonisolated static func skipPath(_ p: String, home: String) -> Bool {
        let lower = p.lowercased()
        if p.hasPrefix("/System/") || p.hasPrefix("/Library/") || p.hasPrefix("/Applications/") || p.hasPrefix("/private/")
            || p.hasPrefix("/usr/") || p.hasPrefix("/opt/") || p.hasPrefix(home + "/Library/") { return true }
        if lower.contains(".app/") || lower.contains("/contents/resources/") || lower.contains("/.trash/")
            || lower.contains("apple loops") || lower.contains("/garageband/") || lower.contains("/node_modules/") { return true }
        return false
    }

    /// Кнопка «Найти всю музыку»: добавляет новые файлы в «Мои файлы» и убирает исчезнувшие.
    func scanWholeMac() {
        guard !scanning else { return }
        scanning = true
        announce("Ищу музыку на всём Mac…")
        Task {
            let before = tracks.count
            // исчезнувшие файлы
            let gone = tracks.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
            for t in gone where t.id != currentID { remove(id: t.id) }
            let found = await spotlightAudio()
            let have = Set(tracks.map { $0.url.standardizedFileURL.path })
            let fresh = found.filter { !have.contains($0.standardizedFileURL.path) }
            // добавляем порциями, чтобы теги читались спокойно и окно не подвисало
            var i = 0
            while i < fresh.count {
                add(urls: Array(fresh[i..<min(i + 60, fresh.count)]), playFirst: false, quiet: true)
                i += 60
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            scanning = false
            scanResult = ScanResult(found: tracks.count, fresh: max(0, tracks.count - before + gone.count), missing: gone.count)
            announce("Готово: песен \(tracks.count), новых \(fresh.count), исчезнувших убрано \(gone.count)")
        }
    }
}
