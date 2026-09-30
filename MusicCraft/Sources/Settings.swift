import SwiftUI

/// Режим производительности: набор настроек «сколько красоты — столько нагрузки».
enum PerfMode: String, CaseIterable, Identifiable {
    case eco, balanced, beauty
    var id: String { rawValue }

    var title: String {
        switch self {
        case .eco: return "Экономия"
        case .balanced: return "Баланс"
        case .beauty: return "Красота"
        }
    }

    var subtitle: String {
        switch self {
        case .eco: return "Для слабых компьютеров и работы от батареи: 30 кадров, без размытия и свечения"
        case .balanced: return "60 кадров, живой фон и пластинка, без тяжёлых эффектов"
        case .beauty: return "Все эффекты: стекло, свечение, размытие строк, пульс под басы"
        }
    }

    var symbol: String {
        switch self {
        case .eco: return "leaf.fill"
        case .balanced: return "dial.medium.fill"
        case .beauty: return "sparkles"
        }
    }

    var preset: VisualPrefs {
        switch self {
        case .eco:
            return VisualPrefs(fps: 30, liveBackground: true, glass: false, glow: false, blurLines: false,
                               bassPulse: false, vinylSpin: false, particles: false)
        case .balanced:
            return VisualPrefs(fps: 60, liveBackground: true, glass: false, glow: true, blurLines: false,
                               bassPulse: false, vinylSpin: true, particles: true)
        case .beauty:
            return VisualPrefs(fps: 0, liveBackground: true, glass: true, glow: true, blurLines: true,
                               bassPulse: true, vinylSpin: true, particles: true)
        }
    }
}

/// Настройки, от которых зависит нагрузка и красота.
struct VisualPrefs: Equatable {
    var fps: Int                // 30, 60 или 0 = как у экрана
    var liveBackground: Bool    // фон двигается
    var glass: Bool             // стеклянные панели (размытие того, что под ними)
    var glow: Bool              // свечение текста и обложки
    var blurLines: Bool         // соседние строки текста слегка размыты
    var bassPulse: Bool         // текст и обложка «дышат» под басы
    var vinylSpin: Bool         // пластинка крутится
    var particles: Bool         // ноты, сердечки и молнии на ударах
}

/// Как расположены текст и обложка на главном экране.
enum StageLayout: String, CaseIterable, Identifiable {
    case side, center, lyrics
    var id: String { rawValue }

    var title: String {
        switch self {
        case .side: return "Рядом"
        case .center: return "По центру"
        case .lyrics: return "Только текст"
        }
    }

    var subtitle: String {
        switch self {
        case .side: return "Текст слева, обложка справа"
        case .center: return "Обложка сверху, текст под ней"
        case .lyrics: return "Крупный текст на весь экран"
        }
    }

    var symbol: String {
        switch self {
        case .side: return "rectangle.split.2x1.fill"
        case .center: return "rectangle.split.1x2.fill"
        case .lyrics: return "text.alignleft"
        }
    }
}

/// Размер обложки на главном экране.
enum CoverSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { ["small": "Маленькая", "medium": "Средняя", "large": "Большая"][rawValue]! }
    var factor: CGFloat { ["small": 0.8, "medium": 1.0, "large": 1.18][rawValue]! }
}

/// Как подсвечивается текущая строка текста.
enum KaraokeMode: String, CaseIterable, Identifiable {
    case letters, line
    var id: String { rawValue }
    var title: String { self == .letters ? "По буквам" : "Строка целиком" }
}

/// Разделы приложения в боковом меню.
enum Page: Hashable {
    case stage
    case library
    case playlist(UUID)
    case settings
    case account(UUID)
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, look, performance, sound, keys
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Основные"
        case .look: return "Оформление"
        case .performance: return "Производительность"
        case .sound: return "Звук"
        case .keys: return "Клавиши"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "switch.2"
        case .look: return "paintpalette.fill"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .sound: return "slider.horizontal.3"
        case .keys: return "keyboard"
        }
    }
}

/// Видно ли окно: когда оно свёрнуто, закрыто другими окнами или приложение скрыто, анимации стоят.
@MainActor
enum WindowWatcher {
    static func install() {
        let nc = NotificationCenter.default
        let update: @Sendable (Notification) -> Void = { _ in MainActor.assumeIsolated { refresh() } }
        nc.addObserver(forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main, using: update)
        nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main, using: update)
        nc.addObserver(forName: NSWindow.didMiniaturizeNotification, object: nil, queue: .main, using: update)
        nc.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: nil, queue: .main, using: update)
        nc.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main, using: update)
        nc.addObserver(forName: NSApplication.didUnhideNotification, object: nil, queue: .main, using: update)
        refresh()
    }

    static func refresh() {
        let visible = !NSApp.isHidden && NSApp.occlusionState.contains(.visible) && NSApp.windows.contains {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) && !($0 is NSPanel)
        }
        let m = PlayerModel.shared
        if m.windowVisible != visible { m.windowVisible = visible }
    }
}
