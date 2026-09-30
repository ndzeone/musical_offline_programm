import SwiftUI

enum ThemeID: String, CaseIterable, Codable, Identifiable {
    case minecraft, dora, kitty, neon, minimal
    var id: String { rawValue }
}

enum BackgroundID: String, CaseIterable, Codable, Identifiable {
    case minecraft, hearts, cuteRock, space, synthwave, aurora, ocean
    var id: String { rawValue }

    var title: String {
        switch self {
        case .minecraft: return "Майнкрафт"
        case .hearts: return "Сердечки и бантики"
        case .cuteRock: return "Кьют-рок"
        case .space: return "Космос"
        case .synthwave: return "Синтвейв"
        case .aurora: return "Цвета обложки"
        case .ocean: return "Ночной океан"
        }
    }
}

/// Тема меняет всё: шрифты, цвета, форму кнопок, панели, фон по умолчанию.
struct Theme {
    let id: ThemeID
    let name: String
    let tagline: String
    let pixel: Bool                 // пиксельные компоненты (Майнкрафт)
    let background: BackgroundID    // живой фон по умолчанию
    let titleFontName: String?
    let bodyFontName: String?
    let text: UInt32                // основной текст на фоне
    let dim: UInt32                 // второстепенный текст
    let unsungAlpha: Double         // непропетые буквы текущей строки
    let sung: UInt32                // пропетые буквы
    let glow: UInt32?               // свечение текущей строки
    let accent: UInt32
    let accent2: UInt32
    let onAccent: UInt32
    let panel: UInt32
    let panelAlpha: Double
    let panelText: UInt32
    let panelDim: UInt32
    let border: UInt32
    let radius: CGFloat
    let textShadow: Bool
    let lyricSize: CGFloat
    let preview: [UInt32]           // цвета карточки в выборе темы

    func title(_ size: CGFloat) -> Font {
        if pixel { return .mc((size * 0.62).rounded()) }
        if let n = titleFontName { return .custom(n, fixedSize: size) }
        return .system(size: size, weight: .bold)
    }

    func body(_ size: CGFloat) -> Font {
        if pixel { return .mc((size * 0.62).rounded()) }
        if let n = bodyFontName { return .custom(n, fixedSize: size) }
        return .system(size: size, weight: .semibold)
    }

    static func get(_ id: ThemeID) -> Theme { all.first { $0.id == id } ?? all[0] }

    static let all: [Theme] = [
        Theme(id: .minecraft, name: "Майнкрафт", tagline: "Пиксели, блоки и хотбар", pixel: true,
              background: .minecraft, titleFontName: "PressStart2P-Regular", bodyFontName: "PressStart2P-Regular",
              text: 0xFFFFFF, dim: 0xB4B4B4, unsungAlpha: 1, sung: 0xFFFF55, glow: nil,
              accent: 0x80FF20, accent2: 0xFFFF55, onAccent: 0xFFFFFF,
              panel: 0xC6C6C6, panelAlpha: 1, panelText: 0x3F3F3F, panelDim: 0x5A5A5A, border: 0x000000,
              radius: 0, textShadow: true, lyricSize: 30, preview: [0x5D9A30, 0x866043, 0x7F7F7F, 0x4A78C8]),
        Theme(id: .dora, name: "Дора", tagline: "Кьют-рок: розовый неон и звёзды", pixel: false,
              background: .cuteRock, titleFontName: "Unbounded-ExtraBold", bodyFontName: "Nunito-ExtraBold",
              text: 0xFFFFFF, dim: 0xE7CCFF, unsungAlpha: 1, sung: 0xFF6BCB, glow: 0xFF2DAA,
              accent: 0xFF4FB8, accent2: 0xB36BFF, onAccent: 0xFFFFFF,
              panel: 0x1B0A2A, panelAlpha: 0.8, panelText: 0xFFFFFF, panelDim: 0xD9B8F2, border: 0xFF7BCB,
              radius: 22, textShadow: true, lyricSize: 34, preview: [0x2A0B3D, 0xFF4FB8, 0xB36BFF, 0xFFE66B]),
        Theme(id: .kitty, name: "Китти", tagline: "Розовая, с бантиками и сердечками", pixel: false,
              background: .hearts, titleFontName: "Comfortaa-Bold", bodyFontName: "Comfortaa-Bold",
              text: 0x6B2440, dim: 0xA8627F, unsungAlpha: 1, sung: 0xE8174F, glow: 0xFFFFFF,
              accent: 0xFF5C93, accent2: 0xE8374F, onAccent: 0xFFFFFF,
              panel: 0xFFFFFF, panelAlpha: 0.88, panelText: 0x6B2440, panelDim: 0xA8627F, border: 0xFFB3CF,
              radius: 26, textShadow: false, lyricSize: 34, preview: [0xFFD6E7, 0xFF5C93, 0xE8374F, 0xFFFFFF]),
        Theme(id: .neon, name: "Неон", tagline: "Ретро-80-е и синтвейв", pixel: false,
              background: .synthwave, titleFontName: "RussoOne-Regular", bodyFontName: "RussoOne-Regular",
              text: 0xFFFFFF, dim: 0xA9B8FF, unsungAlpha: 1, sung: 0x00F0FF, glow: 0x00D5FF,
              accent: 0xFF2BD6, accent2: 0x00C8FF, onAccent: 0xFFFFFF,
              panel: 0x0B0620, panelAlpha: 0.78, panelText: 0xFFFFFF, panelDim: 0xA9B8FF, border: 0x00E5FF,
              radius: 14, textShadow: true, lyricSize: 36, preview: [0x0B0322, 0xFF2BD6, 0x00F0FF, 0xFFE259]),
        Theme(id: .minimal, name: "Минимал", tagline: "Спокойная, цвета берёт из обложки", pixel: false,
              background: .aurora, titleFontName: nil, bodyFontName: nil,
              text: 0xFFFFFF, dim: 0xFFFFFF, unsungAlpha: 0.42, sung: 0xFFFFFF, glow: nil,
              accent: 0xFFFFFF, accent2: 0xD9D9E3, onAccent: 0x111118,
              panel: 0x121218, panelAlpha: 0.62, panelText: 0xFFFFFF, panelDim: 0xA0A0AE, border: 0xFFFFFF,
              radius: 18, textShadow: true, lyricSize: 36, preview: [0x1B1B24, 0x7B2FF7, 0xF72F8C, 0xFFB347]),
    ]
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.all[0]
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
