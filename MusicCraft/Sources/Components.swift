import SwiftUI
import CoreText

// MARK: - Шрифты и цвета

enum Fonts {
    static func register() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    static func mc(_ size: CGFloat) -> Font { .custom("PressStart2P-Regular", fixedSize: size) }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: alpha)
    }
}

/// Тень текста как в Minecraft: тот же цвет, в 4 раза темнее.
func mcShadow(_ hex: UInt32) -> UInt32 {
    (((hex >> 16) & 255) / 4) << 16 | (((hex >> 8) & 255) / 4) << 8 | (hex & 255) / 4
}

func hueHex(_ h: Double) -> UInt32 {
    let c = NSColor(hue: h.truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 1, alpha: 1)
        .usingColorSpace(.sRGB)!
    return UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255)
}

func fmtTime(_ s: Double) -> String {
    guard s.isFinite, s > 0 else { return "0:00" }
    let i = Int(s)
    return String(format: "%d:%02d", i / 60, i % 60)
}

// MARK: - Пиксельные компоненты (тема «Майнкрафт»)

struct MCText: View {
    let text: String
    var size: CGFloat = 8
    var color: UInt32 = 0xFFFFFF
    var shadow = true
    var align: TextAlignment = .leading

    init(_ text: String, size: CGFloat = 8, color: UInt32 = 0xFFFFFF, shadow: Bool = true, align: TextAlignment = .leading) {
        self.text = text.precomposedStringWithCanonicalMapping
        self.size = size; self.color = color; self.shadow = shadow; self.align = align
    }

    var body: some View {
        base.foregroundStyle(Color(hex: color))
            .background(alignment: .topLeading) {
                if shadow {
                    base.foregroundStyle(Color(hex: mcShadow(color)))
                        .offset(x: max(1, size / 8), y: max(1, size / 8))
                }
            }
    }

    private var base: some View {
        Text(text).font(.mc(size)).multilineTextAlignment(align).lineSpacing(size * 0.45)
    }
}

/// Цифры с чёрной обводкой (как уровень опыта).
struct OutlinedText: View {
    let text: String
    var size: CGFloat = 8
    var color: UInt32 = 0x80FF20

    var body: some View {
        let o = max(1, size / 8)
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Text(text).font(.mc(size)).foregroundStyle(.black)
                    .offset(x: [o, -o, 0, 0][i], y: [0, 0, o, -o][i])
            }
            Text(text).font(.mc(size)).foregroundStyle(Color(hex: color))
        }
    }
}

struct BevelBox: View {
    var fill: UInt32
    var light: UInt32
    var dark: UInt32
    var border: UInt32? = 0x000000
    var w: CGFloat = 2
    var alpha: Double = 1

    var body: some View {
        ZStack {
            Color(hex: fill, alpha: alpha)
            Color(hex: light).frame(height: w).frame(maxHeight: .infinity, alignment: .top)
            Color(hex: light).frame(width: w).frame(maxWidth: .infinity, alignment: .leading)
            Color(hex: dark).frame(height: w).frame(maxHeight: .infinity, alignment: .bottom)
            Color(hex: dark).frame(width: w).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(border == nil ? 0 : w)
        .background(border.map { Color(hex: $0) } ?? Color.clear)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct MCButton: View {
    let title: String
    var width: CGFloat?
    var height: CGFloat = 40
    var size: CGFloat = 10
    var selected = false
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, width: CGFloat? = nil, height: CGFloat = 40, size: CGFloat = 10, selected: Bool = false,
         action: @escaping () -> Void) {
        self.title = title; self.width = width; self.height = height; self.size = size
        self.selected = selected; self.action = action
    }

    var body: some View {
        Button(action: action) {
            MCText(title, size: size, color: hover ? 0xFFFFA0 : 0xE0E0E0, align: .center)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(width: width, height: height)
                .background(
                    hover ? BevelBox(fill: 0x7B86C2, light: 0xB9C3F7, dark: 0x545D91)
                        : selected ? BevelBox(fill: 0x4F8A28, light: 0x8FD35A, dark: 0x2E5616)
                        : BevelBox(fill: 0x6F6F6F, light: 0xA8A8A8, dark: 0x4A4A4A)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
    }
}

/// Слайдер как в настройках Minecraft: надпись по центру, ползунок-кнопка.
struct MCSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let label: (Double) -> String
    @State private var hover = false

    var body: some View {
        GeometryReader { g in
            let span = range.upperBound - range.lowerBound
            let p = (value - range.lowerBound) / span
            ZStack(alignment: .leading) {
                BevelBox(fill: 0x3C3C3C, light: 0x222222, dark: 0x555555)
                (hover ? BevelBox(fill: 0x8F99D1, light: 0xC7D0FF, dark: 0x545D91)
                       : BevelBox(fill: 0x8B8B8B, light: 0xC6C6C6, dark: 0x555555))
                    .frame(width: 16)
                    .offset(x: p * (g.size.width - 16))
                MCText(label(value), size: 9, color: hover ? 0xFFFFA0 : 0xFFFFFF, align: .center)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let raw = range.lowerBound + Double((v.location.x - 8) / max(1, g.size.width - 16)) * span
                let stepped = (raw / step).rounded() * step
                let nv = min(range.upperBound, max(range.lowerBound, stepped))
                if abs(nv - value) > step / 10 { value = nv }
            })
        }
        .frame(height: 40)
        .onHover { hover = $0 }
    }
}

struct PixelImage: View {
    let image: CGImage
    var width: CGFloat
    var height: CGFloat?

    init(_ image: CGImage, width: CGFloat, height: CGFloat? = nil) {
        self.image = image; self.width = width; self.height = height
    }

    var body: some View {
        Image(decorative: image, scale: 1).interpolation(.none).resizable()
            .frame(width: width, height: height ?? width * CGFloat(image.height) / CGFloat(image.width))
    }
}

/// Подсказка с фиолетовой рамкой, как у предметов в Minecraft.
struct TooltipBox: View {
    @Environment(\.theme) private var theme
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        if theme.pixel {
            MCText(text, size: 8)
                .fixedSize()
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(Color(hex: 0x100010, alpha: 0.95))
                .overlay(Rectangle().strokeBorder(
                    LinearGradient(colors: [Color(hex: 0x5000FF, alpha: 0.7), Color(hex: 0x28007F, alpha: 0.7)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 2).padding(2))
                .overlay(Rectangle().strokeBorder(Color(hex: 0x100010), lineWidth: 2))
        } else {
            Text(text)
                .font(theme.body(11))
                .foregroundStyle(Color(hex: theme.panelText))
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color(hex: theme.panel, alpha: 0.95)))
                .overlay(Capsule().strokeBorder(Color(hex: theme.border, alpha: 0.6), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
    }
}

private struct TooltipModifier: ViewModifier {
    let text: String
    let offset: CGFloat
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .onHover { hover = $0 }
            .overlay(alignment: .top) {
                if hover && !text.isEmpty {
                    TooltipBox(text).offset(y: offset).allowsHitTesting(false)
                }
            }
            .zIndex(hover ? 10 : 0)
    }
}

extension View {
    func tip(_ text: String, offset: CGFloat = -40) -> some View {
        modifier(TooltipModifier(text: text, offset: offset))
    }
}

// MARK: - Компоненты, которые подстраиваются под тему

struct TText: View {
    @Environment(\.theme) private var theme
    let text: String
    var size: CGFloat = 13
    var title = false
    var color: UInt32?
    var alpha: Double = 1
    var align: TextAlignment = .leading
    var onPanel = false

    init(_ text: String, size: CGFloat = 13, title: Bool = false, color: UInt32? = nil, alpha: Double = 1,
         onPanel: Bool = false, align: TextAlignment = .leading) {
        self.text = text; self.size = size; self.title = title; self.color = color
        self.alpha = alpha; self.align = align; self.onPanel = onPanel
    }

    var body: some View {
        let c = color ?? (onPanel ? theme.panelText : theme.text)
        if theme.pixel {
            MCText(text, size: (size * 0.62).rounded(), color: c, shadow: !onPanel, align: align).opacity(alpha)
        } else {
            Text(text.precomposedStringWithCanonicalMapping)
                .font(title ? theme.title(size) : theme.body(size))
                .foregroundStyle(Color(hex: c, alpha: alpha))
                .multilineTextAlignment(align)
                .shadow(color: theme.textShadow && !onPanel ? .black.opacity(0.35) : .clear, radius: 3, y: 1)
        }
    }
}

struct TButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var icon: String?
    var prominent = false
    var width: CGFloat?
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, icon: String? = nil, prominent: Bool = false, width: CGFloat? = nil, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.prominent = prominent; self.width = width; self.action = action
    }

    var body: some View {
        if theme.pixel {
            MCButton(title, width: width, height: 40, size: 9, selected: prominent, action: action)
        } else {
            let r = min(theme.radius * 0.7, 19)
            Button(action: action) {
                HStack(spacing: 7) {
                    if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                    Text(title).font(theme.body(13)).lineLimit(1)
                }
                .foregroundStyle(Color(hex: prominent ? theme.onAccent : theme.panelText))
                .padding(.horizontal, 16)
                .frame(width: width, height: 38)
                .background {
                    if prominent {
                        LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        Color(hex: theme.panelText, alpha: hover ? 0.16 : 0.09)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(Color(hex: theme.border, alpha: prominent ? 0 : 0.45), lineWidth: 1.2))
                .contentShape(RoundedRectangle(cornerRadius: r, style: .continuous))
                .brightness(prominent && hover ? 0.06 : 0)
                .scaleEffect(hover ? 1.02 : 1)
            }
            .buttonStyle(PressStyle())
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
        }
    }
}

/// Круглая кнопка со значком. В пиксельной теме показывает пиксельную иконку, если она есть.
struct TIconButton: View {
    @Environment(\.theme) private var theme
    let symbol: String
    var pixel: CGImage?
    var size: CGFloat = 36
    var prominent = false
    var active = false
    var tipText = ""
    let action: () -> Void
    @State private var hover = false

    init(_ symbol: String, pixel: CGImage? = nil, size: CGFloat = 36, prominent: Bool = false, active: Bool = false,
         tip: String = "", action: @escaping () -> Void) {
        self.symbol = symbol; self.pixel = pixel; self.size = size; self.prominent = prominent
        self.active = active; self.tipText = tip; self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if theme.pixel {
                    (hover ? BevelBox(fill: 0x7B86C2, light: 0xB9C3F7, dark: 0x545D91)
                           : active ? BevelBox(fill: 0x4F8A28, light: 0x8FD35A, dark: 0x2E5616)
                           : BevelBox(fill: 0x6F6F6F, light: 0xA8A8A8, dark: 0x4A4A4A))
                    if let pixel {
                        PixelImage(pixel, width: pixel.width == 16 ? size * 0.6 : size * 0.5)
                    } else {
                        Image(systemName: symbol).font(.system(size: size * 0.4, weight: .heavy)).foregroundStyle(.white)
                    }
                } else {
                    Circle().fill(prominent
                                  ? AnyShapeStyle(LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(Color(hex: theme.panelText, alpha: hover ? 0.16 : (active ? 0.14 : 0.0))))
                    Image(systemName: symbol)
                        .font(.system(size: size * (prominent ? 0.42 : 0.4), weight: .bold))
                        .foregroundStyle(Color(hex: prominent ? theme.onAccent : (active ? theme.accent : theme.panelText)))
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .scaleEffect(hover && !theme.pixel ? 1.08 : 1)
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .tip(tipText, offset: -size - 6)
    }
}

struct TSlider: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let label: (Double) -> String

    var body: some View {
        if theme.pixel {
            MCSlider(value: $value, range: range, step: step, label: label)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Text(label(value)).font(theme.body(12)).foregroundStyle(Color(hex: theme.panelText))
                SmoothTrack(value: $value, range: range, step: step)
            }
        }
    }
}

/// Тонкая дорожка-слайдер для гладких тем.
struct SmoothTrack: View {
    @Environment(\.theme) private var theme
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    var height: CGFloat = 6
    var thumb: CGFloat = 16
    @State private var hover = false

    var body: some View {
        GeometryReader { g in
            let span = range.upperBound - range.lowerBound
            let p = min(1, max(0, (value - range.lowerBound) / span))
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: theme.panelText, alpha: 0.18)).frame(height: height)
                Capsule().fill(LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * p), height: height)
                Circle().fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .scaleEffect(hover ? 1.15 : 1)
                    .offset(x: p * (g.size.width - thumb))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                var nv = range.lowerBound + Double(min(1, max(0, v.location.x / max(1, g.size.width)))) * span
                if step > 0 { nv = (nv / step).rounded() * step }
                value = min(range.upperBound, max(range.lowerBound, nv))
            })
        }
        .frame(height: max(thumb, height) + 4)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.1), value: hover)
    }
}

struct TField: View {
    @Environment(\.theme) private var theme
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let pix = theme.pixel
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color(hex: pix ? 0x666666 : theme.panelDim)))
            .textFieldStyle(.plain)
            .font(pix ? .mc(9) : theme.body(13))
            .foregroundStyle(Color(hex: pix ? 0xE0E0E0 : theme.panelText))
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, pix ? 10 : 14)
            .frame(height: pix ? 40 : 38)
            .background {
                if pix { Color.black } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: theme.panelText, alpha: 0.08))
                }
            }
            .overlay {
                if pix {
                    Rectangle().strokeBorder(Color(hex: focused ? 0xFFFFFF : 0xA0A0A0), lineWidth: 2)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(hex: theme.border, alpha: focused ? 0.9 : 0.35), lineWidth: 1.5)
                }
            }
    }
}

/// Фон панели: серое окно Minecraft или карточка темы.
/// Стекло (размытие того, что под панелью) — только в режиме красоты: оно пересчитывается каждый кадр фона.
struct PanelBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.visual) private var visual
    var radius: CGFloat?
    var shadow = true

    var body: some View {
        if theme.pixel {
            BevelBox(fill: 0xC6C6C6, light: 0xFFFFFF, dark: 0x555555, w: 3)
        } else {
            let r = radius ?? theme.radius
            let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
            shape
                .fill(Color(hex: theme.panel, alpha: visual.glass ? theme.panelAlpha : min(0.96, theme.panelAlpha + 0.14)))
                .background {
                    if visual.glass { shape.fill(.ultraThinMaterial) }
                }
                .overlay(shape.strokeBorder(Color(hex: theme.border, alpha: 0.4), lineWidth: 1.2))
                .shadow(color: .black.opacity(shadow && visual.glow ? 0.28 : 0), radius: 22, y: 10)
        }
    }
}

// MARK: - Настройки внешнего вида в окружении (чтобы любой элемент знал, сколько «красоты» можно)

private struct VisualKey: EnvironmentKey {
    static let defaultValue = PerfMode.balanced.preset
}

extension EnvironmentValues {
    var visual: VisualPrefs {
        get { self[VisualKey.self] }
        set { self[VisualKey.self] = newValue }
    }
}

// MARK: - Заголовок раздела

struct SectionLabel: View {
    @Environment(\.theme) private var theme
    let text: String
    var onPanel = true

    var body: some View {
        if theme.pixel {
            MCText(text.uppercased(), size: 7, color: 0xFFFF55)
        } else {
            Text(text.uppercased())
                .font(theme.body(10.5))
                .tracking(1.2)
                .foregroundStyle(Color(hex: onPanel ? theme.panelDim : theme.dim, alpha: 0.9))
        }
    }
}

// MARK: - Переключатель «вкл/выкл» в стиле темы

struct TToggle: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        if theme.pixel {
            MCButton("\(title): \(isOn ? "ВКЛ" : "ВЫКЛ")", height: 36, size: 8, selected: isOn) { isOn.toggle() }
        } else {
            Button { isOn.toggle() } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(theme.body(13)).foregroundStyle(Color(hex: theme.panelText))
                        if let subtitle {
                            Text(subtitle).font(theme.body(11)).foregroundStyle(Color(hex: theme.panelDim))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ZStack(alignment: isOn ? .trailing : .leading) {
                        Capsule().fill(isOn ? AnyShapeStyle(LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                                                           startPoint: .leading, endPoint: .trailing))
                                            : AnyShapeStyle(Color(hex: theme.panelText, alpha: 0.18)))
                        Circle().fill(Color.white).padding(3).shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    }
                    .frame(width: 42, height: 24)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: theme.panelText, alpha: 0.05)))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }
}

// MARK: - Выбор одного варианта из нескольких

struct TSegmented<T: Hashable>: View {
    @Environment(\.theme) private var theme
    let options: [(T, String)]
    @Binding var value: T

    var body: some View {
        HStack(spacing: theme.pixel ? 4 : 3) {
            ForEach(options, id: \.0) { o in
                if theme.pixel {
                    MCButton(o.1, height: 34, size: 8, selected: value == o.0) { value = o.0 }
                } else {
                    Button { value = o.0 } label: {
                        Text(o.1).font(theme.body(12))
                            .foregroundStyle(Color(hex: value == o.0 ? theme.onAccent : theme.panelText))
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background {
                                if value == o.0 {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(LinearGradient(colors: [Color(hex: theme.accent), Color(hex: theme.accent2)],
                                                             startPoint: .leading, endPoint: .trailing))
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .padding(theme.pixel ? 0 : 3)
        .background {
            if !theme.pixel {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: theme.panelText, alpha: 0.07))
            }
        }
        .animation(.easeOut(duration: 0.15), value: value)
    }
}

// MARK: - Круглые кнопки действий (сердечко, «+», текст) — одного вида

/// Фон круглой кнопки: одинаковый у всех кнопок действий.
struct RoundBackground: View {
    @Environment(\.theme) private var theme
    let hover: Bool
    var active = false

    var body: some View {
        if theme.pixel {
            hover ? BevelBox(fill: 0x7B86C2, light: 0xB9C3F7, dark: 0x545D91)
                : active ? BevelBox(fill: 0x4F8A28, light: 0x8FD35A, dark: 0x2E5616)
                : BevelBox(fill: 0x6F6F6F, light: 0xA8A8A8, dark: 0x4A4A4A)
        } else {
            Circle().fill(Color(hex: theme.panelText, alpha: hover ? 0.2 : (active ? 0.16 : 0.1)))
        }
    }
}

struct RoundAction: View {
    @Environment(\.theme) private var theme
    let symbol: String
    var size: CGFloat = 36
    var active = false
    var tip = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Color(hex: theme.pixel ? 0xFFFFFF : (active ? theme.accent : theme.panelText)))
                .frame(width: size, height: size)
                .background(RoundBackground(hover: hover, active: active))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .tip(tip, offset: -size - 6)
    }
}

/// Сердечко «в любимые».
struct HeartButton: View {
    @Environment(\.theme) private var theme
    let on: Bool
    var size: CGFloat = 32
    var filledBackground = false
    let action: () -> Void
    @State private var bump = false
    @State private var hover = false

    var body: some View {
        Button {
            action()
            bump = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { bump = false }
        } label: {
            ZStack {
                if filledBackground { RoundBackground(hover: hover) }
                if theme.pixel {
                    PixelImage(on ? Art.heartFull : Art.heartEmpty, width: size * 0.5)
                } else {
                    Image(systemName: on ? "heart.fill" : "heart")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(Color(hex: on ? (theme.id == .minimal ? 0xFF4D6D : theme.accent) : theme.panelText))
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(bump ? 1.25 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: bump)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .tip(on ? "Убрать из любимых" : "В любимые", offset: -size - 6)
    }
}

// MARK: - Окно-панель с заголовком и крестиком

struct TPanel<Content: View>: View {
    @Environment(\.theme) private var theme
    var title: String?
    var width: CGFloat
    var height: CGFloat?
    var onClose: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack {
                    TText(title, size: theme.pixel ? 16 : 22, title: true, onPanel: true).lineLimit(1)
                    Spacer()
                    if let onClose {
                        Button(action: onClose) {
                            if theme.pixel {
                                MCText("X", size: 10, color: 0x3F3F3F, shadow: false)
                            } else {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color(hex: theme.panelText))
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Color(hex: theme.panelText, alpha: 0.1)))
                            }
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            content()
        }
        .padding(theme.pixel ? 18 : 24)
        .frame(width: width, height: height, alignment: .top)
        .background(PanelBackground())
    }
}

// MARK: - Прокрутка (в проверочных снимках содержимое рисуется без неё)

enum Debug {
    nonisolated(unsafe) static var snapshot = false
}

struct Scrolling<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if Debug.snapshot {
            content().frame(maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollView(showsIndicators: false) { content() }
        }
    }
}
