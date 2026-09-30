import SwiftUI

/// Общие «живые» значения анализа звука для интерфейса.
final class Visuals {
    static let shared = Visuals()
    var bass: Double = 0
    var loudness: Double = 0
}

struct SceneInput {
    var progress: Double?
    var playing: Bool
    var spectrum: [Float]
    var binHz: Double
    var level: Double
    var particles: Bool
    var palette: [UInt32]
}

struct Features {
    var t: Double
    var dt: Double
    var active: Bool
    var bass: Double
    var level: Double
    var beat: Bool
    var progress: Double?
    var spectrum: [Float]
    var binHz: Double
    var particles: Bool
    var palette: [UInt32]

    /// Полосы спектра по логарифмической шкале, 0…1.
    func bands(_ n: Int, from f0: Double = 35, to f1: Double = 15000) -> [Double] {
        var out = [Double](repeating: 0, count: n)
        let count = spectrum.count
        guard active, count > 0 else { return out }
        for i in 0..<n {
            let a = f0 * pow(f1 / f0, Double(i) / Double(n)), b = f0 * pow(f1 / f0, Double(i + 1) / Double(n))
            let b1 = Int(a / binHz), b2 = max(b1 + 1, Int(ceil(b / binHz)))
            var v: Float = 0
            if b1 < count { for k in b1..<min(b2, count) { v = max(v, spectrum[k]) } }
            out[i] = min(1, Double(v) * (0.9 + 0.3 * Double(i) / Double(n)))
        }
        return out
    }
}

/// Плавная «псевдо-музыка» для фона, когда звук недоступен для анализа (аккаунты, превью).
enum Ambient {
    static func spectrum(t: Double, binHz: Double, n: Int = AudioEngine.fftSize / 2) -> [Float] {
        let beat = exp(-(t * 2).truncatingRemainder(dividingBy: 1) * 5)
        let hat = exp(-(t * 4 + 0.5).truncatingRemainder(dividingBy: 1) * 8)
        var out = [Float](repeating: 0, count: n)
        for i in 1..<n {
            let f = Double(i) * binHz
            let lf = log2(max(f, 20))
            var v = max(0, 0.72 - (lf - 5) * 0.055) + 0.12 * sin(t * 1.7 + lf * 1.3) + 0.08 * sin(t * 3.1 + lf * 2.7)
            if f < 150 { v += 0.35 * beat }
            if f > 3000 && f < 12000 { v += 0.15 * hat }
            out[i] = Float(min(1, max(0, v)))
        }
        return out
    }
}

protocol BackgroundRenderer: AnyObject {
    func draw(_ ctx: inout GraphicsContext, size: CGSize, f: Features)
}

/// Считает общие признаки (басы, громкость, удары) и рисует выбранный фон.
final class SceneEngine {
    private var lastTime = 0.0
    private var bass = 0.0
    private var level = 0.0
    private var bassAvg = 0.0
    private var lastBeat = 0.0
    private var renderers: [BackgroundID: BackgroundRenderer] = [:]

    private func renderer(_ id: BackgroundID) -> BackgroundRenderer {
        if let r = renderers[id] { return r }
        let r: BackgroundRenderer
        switch id {
        case .minecraft: r = MinecraftRenderer()
        case .hearts: r = HeartsRenderer()
        case .cuteRock: r = CuteRockRenderer()
        case .space: r = SpaceRenderer()
        case .synthwave: r = SynthwaveRenderer()
        case .aurora: r = AuroraRenderer()
        case .ocean: r = OceanRenderer()
        }
        renderers[id] = r
        return r
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Double, input: SceneInput, id: BackgroundID, shared: Bool) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.1, max(0, now - lastTime))
        lastTime = now
        let spec = input.spectrum, n = spec.count
        let active = input.playing && n > 0
        var bassNow = 0.0
        if active {
            let b0 = max(1, Int(35 / input.binHz)), b1 = min(n - 1, max(b0 + 1, Int(150 / input.binHz)))
            for b in b0...b1 { bassNow += Double(spec[b]) }
            bassNow /= Double(b1 - b0 + 1)
        }
        bass += (bassNow - bass) * min(1, dt * 18)
        level += ((active ? input.level : 0) - level) * min(1, dt * 12)
        bassAvg += (bassNow - bassAvg) * min(1, dt * 1.5)
        var beat = false
        if active && bassNow > bassAvg * 1.2 && bassNow > 0.45 && now - lastBeat > 0.2 {
            beat = true
            lastBeat = now
        }
        if shared {
            Visuals.shared.bass = bass
            Visuals.shared.loudness = level
        }
        let f = Features(t: now, dt: dt, active: active, bass: bass, level: level, beat: beat, progress: input.progress,
                         spectrum: spec, binHz: input.binHz, particles: input.particles, palette: input.palette)
        renderer(id).draw(&ctx, size: size, f: f)
    }
}

/// Живой фон. Частота кадров ограничена настройкой, а когда окна не видно или фон закрыт плеером
/// площадки, он стоит на месте и не тратит процессор.
struct SceneView: View {
    @EnvironmentObject var m: PlayerModel
    let background: BackgroundID
    var preview = false
    var paused = false
    @State private var engine = SceneEngine()

    var body: some View {
        let stop = paused || m.animationsPaused || (!preview && !m.visual.liveBackground)
        // Фон мягкий: рисуем его в пониженном разрешении и растягиваем — нагрузка в 2–4 раза меньше.
        // На паузе (ничего не играет) — не чаще 30 кадров.
        let q = preview ? 1 : CGFloat(max(0.5, min(1, m.visual.quality)))
        let idle = !preview && m.visual.idleSlow && !m.isPlaying
        let interval = preview ? 1.0 / 15 : (idle ? max(m.frameInterval ?? 0, 1.0 / 30) : m.frameInterval)
        GeometryReader { g in
            TimelineView(.animation(minimumInterval: interval, paused: stop)) { tl in
                Canvas(rendersAsynchronously: false) { ctx, size in
                    let now = tl.date.timeIntervalSinceReferenceDate
                    let input = preview ? PlayerModel.previewInput(now: now) : m.sceneInput(now: now)
                    ctx.scaleBy(x: q, y: q)
                    engine.draw(&ctx, size: CGSize(width: size.width / q, height: size.height / q), now: now, input: input,
                                id: background, shared: !preview)
                }
                .frame(width: (g.size.width * q).rounded(), height: (g.size.height * q).rounded())
                .scaleEffect(1 / q, anchor: .topLeading)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
            .clipped()
        }
    }
}

// MARK: - Фигурки

enum Shapes {
    static func heart(_ c: CGPoint, _ s: CGFloat) -> Path {
        var p = Path()
        let top = CGPoint(x: c.x, y: c.y - s * 0.2)
        let bottom = CGPoint(x: c.x, y: c.y + s * 0.5)
        p.move(to: bottom)
        p.addCurve(to: top, control1: CGPoint(x: c.x - s * 0.95, y: c.y - s * 0.02),
                   control2: CGPoint(x: c.x - s * 0.45, y: c.y - s * 0.72))
        p.addCurve(to: bottom, control1: CGPoint(x: c.x + s * 0.45, y: c.y - s * 0.72),
                   control2: CGPoint(x: c.x + s * 0.95, y: c.y - s * 0.02))
        p.closeSubpath()
        return p
    }

    static func sparkle(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
        return p
    }

    static func bow(_ c: CGPoint, _ s: CGFloat) -> Path {
        var p = Path()
        for k in [-1.0, 1.0] as [CGFloat] {
            p.move(to: c)
            p.addCurve(to: CGPoint(x: c.x + k * s * 0.5, y: c.y - s * 0.32),
                       control1: CGPoint(x: c.x + k * s * 0.15, y: c.y - s * 0.35),
                       control2: CGPoint(x: c.x + k * s * 0.35, y: c.y - s * 0.45))
            p.addCurve(to: CGPoint(x: c.x + k * s * 0.5, y: c.y + s * 0.32),
                       control1: CGPoint(x: c.x + k * s * 0.62, y: c.y - s * 0.15),
                       control2: CGPoint(x: c.x + k * s * 0.62, y: c.y + s * 0.15))
            p.addCurve(to: c, control1: CGPoint(x: c.x + k * s * 0.35, y: c.y + s * 0.45),
                       control2: CGPoint(x: c.x + k * s * 0.15, y: c.y + s * 0.35))
            p.closeSubpath()
        }
        return p
    }

    static func bolt(_ o: CGPoint, _ s: CGFloat) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(0.1, 0), (0.55, 0), (0.33, 0.42), (0.62, 0.42), (0.05, 1.15), (0.22, 0.6), (-0.05, 0.6)]
        var p = Path()
        p.move(to: CGPoint(x: o.x + pts[0].0 * s, y: o.y + pts[0].1 * s))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: o.x + q.0 * s, y: o.y + q.1 * s)) }
        p.closeSubpath()
        return p
    }
}

private func gradientFill(_ ctx: inout GraphicsContext, _ size: CGSize, _ colors: [UInt32], _ stops: [CGFloat]? = nil) {
    let g: Gradient
    if let stops {
        g = Gradient(stops: zip(colors, stops).map { Gradient.Stop(color: Color(hex: $0.0), location: $0.1) })
    } else {
        g = Gradient(colors: colors.map { Color(hex: $0) })
    }
    ctx.fill(Path(CGRect(origin: .zero, size: size)),
             with: .linearGradient(g, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
}

// MARK: - Майнкрафт: рельеф из блоков, смена дня и ночи по ходу песни

private struct Particle {
    var x: CGFloat
    var y: CGFloat
    var age: Double
    var life: Double
    var color: Int
    var size: CGFloat
    var phase: Double
}

private struct Cloud {
    var x: Double
    var y: Double
    var speed: Double
    var cells: [(Int, Int)]
    var w: Int
}

private struct Sky {
    var top: UInt32
    var bottom: UInt32
    var night: Double
    var warm: Double

    static let keys: [(Double, Sky)] = [
        (0.00, Sky(top: 0x2E3C7A, bottom: 0xF2995A, night: 0.35, warm: 1)),
        (0.10, Sky(top: 0x4A78C8, bottom: 0x92B4E6, night: 0, warm: 0.2)),
        (0.25, Sky(top: 0x4A78C8, bottom: 0x8FB0E0, night: 0, warm: 0)),
        (0.66, Sky(top: 0x4A78C8, bottom: 0x8FB0E0, night: 0, warm: 0)),
        (0.78, Sky(top: 0x46407F, bottom: 0xEE7A4A, night: 0.25, warm: 1)),
        (0.88, Sky(top: 0x151A3F, bottom: 0x39386A, night: 0.8, warm: 0.2)),
        (1.00, Sky(top: 0x0A0E26, bottom: 0x232E62, night: 1, warm: 0)),
    ]

    static func at(_ p: Double) -> Sky {
        let p = min(1, max(0, p))
        for i in 1..<keys.count where p <= keys[i].0 {
            let (p0, a) = keys[i - 1], (p1, b) = keys[i]
            let t = (p - p0) / max(0.0001, p1 - p0)
            return Sky(top: lerpColor(a.top, b.top, t), bottom: lerpColor(a.bottom, b.bottom, t),
                       night: a.night + (b.night - a.night) * t, warm: a.warm + (b.warm - a.warm) * t)
        }
        return keys.last!.1
    }
}

final class MinecraftRenderer: BackgroundRenderer {
    private var heights: [Double] = []
    private var peaks: [Double] = []
    private var hold: [Double] = []
    private var particles: [Particle] = []
    private var clouds: [Cloud] = []
    private var stars: [CGPoint] = []
    private var noteColor = 0
    private var rng = RNG(99)
    private let terrain = TerrainRenderer()

    init() {
        var r = RNG(5)
        clouds = (0..<8).map { _ in
            let w = 4 + Int(r.next() * 7), h = 2 + (r.next() > 0.5 ? 1 : 0)
            var cells: [(Int, Int)] = []
            for y in 0..<h {
                for x in 0..<w {
                    let corner = (x == 0 || x == w - 1) && (y == 0 || y == h - 1)
                    if y == h / 2 || (!corner && r.next() > 0.3) { cells.append((x, y)) }
                }
            }
            return Cloud(x: r.next(), y: 0.08 + r.next() * 0.2, speed: 5 + r.next() * 9, cells: cells, w: w)
        }
        stars = (0..<80).map { _ in CGPoint(x: r.next(), y: r.next() * 0.6) }
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, f: Features) {
        let W = size.width, H = size.height, dt = f.dt
        let cell = max(12, min(30, (W / 52).rounded()))
        let cols = Int(ceil(W / cell))
        let rows = max(6, Int(H * 0.34 / cell))
        if heights.count != cols {
            heights = Array(repeating: 4, count: cols)
            peaks = heights
            hold = Array(repeating: 0, count: cols)
        }

        if f.beat && f.particles {
            noteColor = (noteColor + 1 + Int(rng.next() * 4)) % Art.notes.count
            for _ in 0..<(1 + Int(rng.next() * 3)) {
                let c = Int(rng.next() * Double(cols))
                particles.append(Particle(x: CGFloat(c) * cell + cell * 0.2, y: H - CGFloat(heights[c]) * cell - cell,
                                          age: 0, life: 1.4 + rng.next() * 0.8, color: noteColor,
                                          size: cell * 0.9, phase: rng.next() * 6))
            }
        }

        let base = 4.0
        let bands = f.bands(cols)
        for c in 0..<cols {
            let v = pow(bands[c], 1.4)
            let target = base + v * Double(rows - Int(base) - 1)
            heights[c] = target > heights[c] ? target : max(target, heights[c] - dt * 14)
            let h = heights[c].rounded()
            if h >= peaks[c] { peaks[c] = h; hold[c] = 0.5 }
            else if hold[c] > 0 { hold[c] -= dt }
            else { peaks[c] = max(h, peaks[c] - dt * 4) }
        }

        let p = f.progress ?? (f.t / 240).truncatingRemainder(dividingBy: 1)
        let sky = Sky.at(p)
        gradientFill(&ctx, CGSize(width: W, height: H * 0.85), [sky.top, sky.bottom])
        ctx.fill(Path(CGRect(x: 0, y: H * 0.85 - 1, width: W, height: H * 0.15 + 1)), with: .color(Color(hex: sky.bottom)))

        if sky.night > 0.02 {
            for s in stars {
                let a = sky.night * (0.45 + 0.4 * sin(f.t * 1.7 + Double(s.x) * 60))
                ctx.fill(Path(CGRect(x: s.x * W, y: s.y * H, width: 2, height: 2)), with: .color(.white.opacity(a)))
            }
        }

        let sz = cell * 3
        if p < 0.86 {
            let q = p / 0.86
            let x = -sz + (W + sz) * q, y = H * 0.55 - sin(q * .pi) * H * 0.45
            ctx.fill(Path(CGRect(x: x - sz * 0.35, y: y - sz * 0.35, width: sz * 1.7, height: sz * 1.7)),
                     with: .color(Color(hex: 0xFFF3A0, alpha: 0.18)))
            ctx.fill(Path(CGRect(x: x, y: y, width: sz, height: sz)), with: .color(Color(hex: 0xFFE95C)))
            ctx.fill(Path(CGRect(x: x + sz * 0.2, y: y + sz * 0.2, width: sz * 0.6, height: sz * 0.6)),
                     with: .color(Color(hex: 0xFFFFD8)))
        }
        if p > 0.72 {
            let q = (p - 0.72) / 0.28
            let x = -sz + (W * 0.72 + sz) * q, y = H * 0.55 - sin(q * .pi / 2) * H * 0.42
            ctx.fill(Path(CGRect(x: x, y: y, width: sz, height: sz)), with: .color(Color(hex: 0xE6E6D6)))
            ctx.fill(Path(CGRect(x: x + sz * 0.2, y: y + sz * 0.25, width: sz * 0.25, height: sz * 0.25)),
                     with: .color(Color(hex: 0xBFBFAE)))
            ctx.fill(Path(CGRect(x: x + sz * 0.6, y: y + sz * 0.55, width: sz * 0.2, height: sz * 0.2)),
                     with: .color(Color(hex: 0xBFBFAE)))
        }

        let cloudCell = cell * 0.85
        var cloudColor = lerpColor(0xFFFFFF, 0x4A5070, sky.night)
        cloudColor = lerpColor(cloudColor, 0xFFC8A8, sky.warm * 0.5)
        for i in clouds.indices {
            let cw = Double(clouds[i].w) * cloudCell
            clouds[i].x += clouds[i].speed * dt / (W + cw)
            if clouds[i].x > 1 { clouds[i].x -= 1 }
            let x0 = clouds[i].x * (W + cw) - cw, y0 = clouds[i].y * H
            var path = Path()
            for (cx, cy) in clouds[i].cells {
                path.addRect(CGRect(x: x0 + Double(cx) * cloudCell, y: y0 + Double(cy) * cloudCell * 0.6,
                                    width: cloudCell, height: cloudCell * 0.6))
            }
            ctx.fill(path, with: .color(Color(hex: cloudColor, alpha: 0.85)))
        }

        terrain.resize(cols: cols, rows: rows)
        if let img = terrain.render(heights: heights.map { Int($0.rounded()) },
                                    peaks: peaks.map { Int($0.rounded()) }, showPeaks: f.active) {
            let rect = CGRect(x: 0, y: H - CGFloat(rows) * cell, width: CGFloat(cols) * cell, height: CGFloat(rows) * cell)
            let shade = sky.night * 0.55, warm = sky.warm * 0.12
            ctx.drawLayer { l in
                l.draw(Image(decorative: img, scale: 1).interpolation(.none), in: rect)
                if shade > 0.01 || warm > 0.01 {
                    l.blendMode = .sourceAtop
                    if shade > 0.01 { l.fill(Path(rect), with: .color(Color(hex: 0x05081A, alpha: shade))) }
                    if warm > 0.01 { l.fill(Path(rect), with: .color(Color(hex: 0xFF8040, alpha: warm))) }
                }
            }
        }

        particles.removeAll { $0.age >= $0.life }
        for i in particles.indices {
            particles[i].age += dt
            particles[i].y -= CGFloat(55 * dt)
            let pt = particles[i]
            var c2 = ctx
            c2.opacity = max(0, 1 - pt.age / pt.life)
            let x = pt.x + CGFloat(sin(pt.age * 3 + pt.phase) * 6)
            c2.draw(Image(decorative: Art.notes[pt.color], scale: 1).interpolation(.none),
                    in: CGRect(x: x, y: pt.y, width: pt.size * 0.75, height: pt.size))
        }
    }
}

// MARK: - Сердечки и бантики

final class HeartsRenderer: BackgroundRenderer {
    private struct Floaty {
        var x: Double, y: Double, size: Double, speed: Double, phase: Double
        var kind: Int, color: UInt32, rot: Double
    }
    private var items: [Floaty] = []
    private var rng = RNG(77)

    private func make(randomY: Bool) -> Floaty {
        let r = rng.next()
        let kind = r < 0.55 ? 0 : (r < 0.78 ? 1 : 2)
        return Floaty(x: rng.next(), y: randomY ? rng.next() * 1.1 : 1.08, size: 14 + rng.next() * 26,
                      speed: 0.03 + rng.next() * 0.05, phase: rng.next() * 6.28, kind: kind,
                      color: rng.pick([0xFF6FA5, 0xFF8FB8, 0xE8374F, 0xFFA3C6, 0xD98BFF]), rot: (rng.next() - 0.5) * 0.6)
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, f: Features) {
        let W = size.width, H = size.height
        if items.isEmpty { items = (0..<28).map { _ in make(randomY: true) } }
        gradientFill(&ctx, size, [0xFFC7DD, 0xFFE3EE, 0xFFF4F8], [0, 0.55, 1])

        let sp: CGFloat = 54
        let off = CGFloat((f.t * 10).truncatingRemainder(dividingBy: Double(sp)))
        var dots = Path()
        var row = 0
        var y = -sp + off
        while y < H + sp {
            var x = -sp + off * 0.5 + (row % 2 == 0 ? 0 : sp / 2)
            while x < W + sp {
                dots.addEllipse(in: CGRect(x: x - 5, y: y - 5, width: 10, height: 10))
                x += sp
            }
            y += sp
            row += 1
        }
        ctx.fill(dots, with: .color(.white.opacity(0.6)))

        let glowR = min(W, H) * (0.45 + f.bass * 0.12)
        ctx.fill(Path(ellipseIn: CGRect(x: W / 2 - glowR, y: H / 2 - glowR, width: glowR * 2, height: glowR * 2)),
                 with: .radialGradient(Gradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)]),
                                       center: CGPoint(x: W / 2, y: H / 2), startRadius: 0, endRadius: glowR))

        if f.beat && f.particles {
            for _ in 0..<4 {
                var n = make(randomY: false)
                n.kind = 0
                n.size = 10 + rng.next() * 8
                n.speed = 0.22 + rng.next() * 0.2
                items.append(n)
            }
            if items.count > 64 { items.removeFirst(items.count - 64) }
        }

        for i in items.indices {
            items[i].y -= items[i].speed * f.dt * (1 + f.level)
            if items[i].y < -0.1 { items[i] = make(randomY: false) }
            let it = items[i]
            let s = CGFloat(it.size * (1 + f.bass * 0.35))
            var c = ctx
            c.translateBy(x: it.x * W + sin(f.t * 0.8 + it.phase) * 26, y: it.y * H)
            c.rotate(by: .radians(sin(f.t + it.phase) * 0.35 + it.rot))
            switch it.kind {
            case 0:
                c.fill(Shapes.heart(.zero, s), with: .color(Color(hex: it.color, alpha: 0.88)))
                c.fill(Shapes.heart(CGPoint(x: -s * 0.2, y: -s * 0.12), s * 0.22), with: .color(.white.opacity(0.4)))
            case 1:
                let b = Shapes.bow(.zero, s * 1.5)
                c.fill(b, with: .color(Color(hex: 0xE8374F)))
                c.stroke(b, with: .color(Color(hex: 0xB21D3A)), lineWidth: 2)
                c.fill(Path(ellipseIn: CGRect(x: -s * 0.17, y: -s * 0.19, width: s * 0.34, height: s * 0.38)),
                       with: .color(Color(hex: 0xC92440)))
            default:
                let tw = 0.5 + 0.5 * sin(f.t * 3 + it.phase)
                c.fill(Shapes.sparkle(.zero, s * CGFloat(0.35 + 0.35 * tw)), with: .color(.white.opacity(0.95)))
            }
        }
    }
}

// MARK: - Кьют-рок: розовый неон, звёзды, молнии, эквалайзер

final class CuteRockRenderer: BackgroundRenderer {
    private struct Star { var x: Double, y: Double, size: Double, phase: Double, color: UInt32 }
    private struct Heart { var x: Double, y: Double, size: Double, vx: Double, vy: Double, phase: Double, color: UInt32 }
    private struct Bolt { var x: Double, y: Double, age: Double, scale: Double, color: UInt32 }
    private var stars: [Star] = []
    private var hearts: [Heart] = []
    private var bolts: [Bolt] = []
    private var glitter: [CGPoint] = []
    private var bars: [Double] = []
    private var rng = RNG(31)

    func draw(_ ctx: inout GraphicsContext, size: CGSize, f: Features) {
        let W = size.width, H = size.height
        if stars.isEmpty {
            stars = (0..<16).map { _ in
                Star(x: rng.next(), y: rng.next() * 0.75, size: 8 + rng.next() * 20, phase: rng.next() * 6.28,
                     color: rng.pick([0xFF6BCB, 0xD9A1FF, 0xFFE66B, 0xFFFFFF]))
            }
            hearts = (0..<9).map { _ in
                Heart(x: rng.next(), y: rng.next(), size: 22 + rng.next() * 34, vx: (rng.next() - 0.5) * 0.02,
                      vy: -0.01 - rng.next() * 0.02, phase: rng.next() * 6.28, color: rng.pick([0xFF4FB8, 0xB36BFF, 0xFF8AD8]))
            }
            glitter = (0..<150).map { _ in CGPoint(x: rng.next(), y: rng.next()) }
        }
        gradientFill(&ctx, size, [0x12051C, 0x2A0B3D, 0x51104F], [0, 0.55, 1])

        let gr = min(W, H) * (0.55 + f.bass * 0.2)
        ctx.fill(Path(ellipseIn: CGRect(x: W * 0.5 - gr, y: H * 0.45 - gr, width: gr * 2, height: gr * 2)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xFF2DAA, alpha: 0.28 + f.bass * 0.2), .clear]),
                                       center: CGPoint(x: W * 0.5, y: H * 0.45), startRadius: 0, endRadius: gr))

        for (i, g) in glitter.enumerated() {
            let a = 0.15 + 0.55 * max(0, sin(f.t * (1.5 + Double(i % 7) * 0.3) + Double(i)))
            ctx.fill(Path(ellipseIn: CGRect(x: g.x * W, y: g.y * H, width: 2.2, height: 2.2)),
                     with: .color(Color(hex: i % 3 == 0 ? 0xFFB3E6 : 0xFFFFFF, alpha: a)))
        }

        for s in stars {
            let tw = 0.55 + 0.45 * sin(f.t * 2.2 + s.phase)
            let r = CGFloat(s.size * tw * (1 + f.bass * 0.4))
            var c = ctx
            c.translateBy(x: s.x * W, y: s.y * H)
            c.rotate(by: .radians(f.t * 0.3 + s.phase))
            c.fill(Shapes.sparkle(.zero, r * 1.8), with: .color(Color(hex: s.color, alpha: 0.18)))
            c.fill(Shapes.sparkle(.zero, r), with: .color(Color(hex: s.color, alpha: 0.95)))
        }

        for i in hearts.indices {
            hearts[i].x += hearts[i].vx * f.dt
            hearts[i].y += hearts[i].vy * f.dt * (1 + f.level * 2)
            if hearts[i].y < -0.1 { hearts[i].y = 1.1; hearts[i].x = rng.next() }
            if hearts[i].x < -0.1 { hearts[i].x = 1.1 } else if hearts[i].x > 1.1 { hearts[i].x = -0.1 }
            let h = hearts[i]
            let s = CGFloat(h.size * (1 + f.bass * 0.25))
            var c = ctx
            c.translateBy(x: h.x * W, y: h.y * H)
            c.rotate(by: .radians(sin(f.t * 0.9 + h.phase) * 0.3))
            let p = Shapes.heart(.zero, s)
            c.fill(p, with: .color(Color(hex: h.color, alpha: 0.9)))
            c.stroke(p, with: .color(Color(hex: 0x14041F)), lineWidth: 3.5)
            c.fill(Shapes.heart(CGPoint(x: -s * 0.2, y: -s * 0.12), s * 0.2), with: .color(.white.opacity(0.55)))
        }

        if f.beat && f.particles {
            bolts.append(Bolt(x: 0.08 + rng.next() * 0.84, y: 0.04 + rng.next() * 0.3, age: 0,
                              scale: 50 + rng.next() * 60, color: rng.pick([0xFFE66B, 0xFF6BCB, 0xC7A2FF])))
        }
        bolts.removeAll { $0.age > 0.4 }
        for i in bolts.indices {
            bolts[i].age += f.dt
            let b = bolts[i]
            let a = max(0, 1 - b.age / 0.4)
            let path = Shapes.bolt(CGPoint(x: b.x * W, y: b.y * H), CGFloat(b.scale))
            ctx.stroke(path, with: .color(Color(hex: b.color, alpha: a * 0.35)), lineWidth: 10)
            ctx.fill(path, with: .color(Color(hex: b.color, alpha: a)))
        }

        let n = 40
        let bands = f.bands(n)
        if bars.count != n { bars = Array(repeating: 0, count: n) }
        let bw = W / CGFloat(n)
        for i in 0..<n {
            bars[i] = bands[i] > bars[i] ? bands[i] : max(bands[i], bars[i] - f.dt * 1.6)
            let h = max(4, CGFloat(bars[i]) * H * 0.26)
            let r = CGRect(x: CGFloat(i) * bw + bw * 0.18, y: H - h, width: bw * 0.64, height: h + 8)
            ctx.fill(Path(roundedRect: r, cornerRadius: bw * 0.3),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0xFF6BCB), Color(hex: 0x8A3DFF, alpha: 0.6)]),
                                           startPoint: CGPoint(x: 0, y: H - h), endPoint: CGPoint(x: 0, y: H)))
        }
    }
}

// MARK: - Космос: звёзды летят навстречу, туманности, планета

final class SpaceRenderer: BackgroundRenderer {
    private struct S3 { var x: Double, y: Double, z: Double }
    private var stars: [S3] = []
    private var rng = RNG(123)
    private var shoot: (x: Double, y: Double, age: Double)?
    private var nextShoot = 3.0

    private func spawn(far: Bool) -> S3 {
        S3(x: rng.next() * 2 - 1, y: rng.next() * 2 - 1, z: far ? 1 : 0.05 + rng.next() * 0.95)
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, f: Features) {
        let W = size.width, H = size.height
        if stars.isEmpty { stars = (0..<380).map { _ in spawn(far: false) } }
        gradientFill(&ctx, size, [0x02030A, 0x080C24, 0x0E1233], [0, 0.6, 1])

        let neb: [(UInt32, Double, Double, Double)] = [(0x5B2AB8, 0.3, 0.35, 0.3), (0x1F4FB0, 0.72, 0.3, 0.26), (0xB02E8A, 0.55, 0.72, 0.22)]
        for (i, (c, x, y, a)) in neb.enumerated() {
            let cx = W * (x + 0.06 * sin(f.t * 0.05 + Double(i) * 2)), cy = H * (y + 0.05 * cos(f.t * 0.04 + Double(i)))
            let r = max(W, H) * (0.42 + f.bass * 0.05)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [Color(hex: c, alpha: a), .clear]),
                                           center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
        }

        let speed = 0.05 + f.level * 0.45 + (f.beat ? 0.25 : 0)
        let cx = W / 2, cy = H / 2, k = max(W, H) * 0.42
        for i in stars.indices {
            let old = stars[i]
            stars[i].z -= speed * f.dt
            if stars[i].z <= 0.03 { stars[i] = spawn(far: true); continue }
            let s = stars[i]
            let sx = cx + s.x / s.z * k, sy = cy + s.y / s.z * k
            if sx < -20 || sx > W + 20 || sy < -20 || sy > H + 20 { stars[i] = spawn(far: true); continue }
            let a = min(1, (1 - s.z) * 1.4)
            let r = max(0.7, (1 - s.z) * 3)
            if speed > 0.2 {
                let ox = cx + old.x / old.z * k, oy = cy + old.y / old.z * k
                var line = Path()
                line.move(to: CGPoint(x: ox, y: oy))
                line.addLine(to: CGPoint(x: sx, y: sy))
                ctx.stroke(line, with: .color(.white.opacity(a * 0.5)), lineWidth: r * 0.8)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: sx - r / 2, y: sy - r / 2, width: r, height: r)), with: .color(.white.opacity(a)))
        }

        let pr = min(W, H) * 0.14 * (1 + f.bass * 0.04)
        let pc = CGPoint(x: W * 0.84, y: H * 0.76)
        let ring = CGRect(x: pc.x - pr * 1.9, y: pc.y - pr * 0.45, width: pr * 3.8, height: pr * 0.9)
        ctx.stroke(Path(ellipseIn: ring), with: .color(Color(hex: 0xFFD1A6, alpha: 0.35)), lineWidth: pr * 0.12)
        ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: 2 * pr, height: 2 * pr)),
                 with: .linearGradient(Gradient(colors: [Color(hex: 0xFFB36B), Color(hex: 0xC2417E), Color(hex: 0x4A1E6B)]),
                                       startPoint: CGPoint(x: pc.x - pr, y: pc.y - pr), endPoint: CGPoint(x: pc.x + pr, y: pc.y + pr)))
        var front = ctx
        front.clip(to: Path(CGRect(x: ring.minX - 10, y: pc.y, width: ring.width + 20, height: ring.height)))
        front.stroke(Path(ellipseIn: ring), with: .color(Color(hex: 0xFFD1A6, alpha: 0.7)), lineWidth: pr * 0.12)

        nextShoot -= f.dt
        if shoot == nil && nextShoot <= 0 {
            shoot = (x: rng.next() * 0.6, y: rng.next() * 0.35, age: 0)
            nextShoot = 4 + rng.next() * 6
        }
        if let s = shoot {
            let t = s.age / 0.9
            let x0 = (s.x + t * 0.35) * W, y0 = (s.y + t * 0.18) * H
            var line = Path()
            line.move(to: CGPoint(x: x0 - 120, y: y0 - 60))
            line.addLine(to: CGPoint(x: x0, y: y0))
            ctx.stroke(line, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.9 * (1 - t))]),
                                                   startPoint: CGPoint(x: x0 - 120, y: y0 - 60), endPoint: CGPoint(x: x0, y: y0)),
                       lineWidth: 2.2)
            shoot?.age += f.dt
            if s.age > 0.9 { shoot = nil }
        }
    }
}

// MARK: - Синтвейв: ретро-солнце, горы-эквалайзер, неоновая сетка

final class SynthwaveRenderer: BackgroundRenderer {
    private var stars: [CGPoint] = []
    private var ridge: [Double] = []

    func draw(_ ctx: inout GraphicsContext, size: CGSize, f: Features) {
        let W = size.width, H = size.height
        if stars.isEmpty {
            var r = RNG(8)
            stars = (0..<90).map { _ in CGPoint(x: r.next(), y: r.next() * 0.55) }
        }
        let hy = H * 0.64
        gradientFill(&ctx, CGSize(width: W, height: hy), [0x07021A, 0x220843, 0x7A1470, 0xFF2BD6], [0, 0.55, 0.85, 1])
        for (i, s) in stars.enumerated() {
            let a = 0.3 + 0.5 * max(0, sin(f.t * 1.3 + Double(i)))
            ctx.fill(Path(CGRect(x: s.x * W, y: s.y * H, width: 1.8, height: 1.8)), with: .color(.white.opacity(a)))
        }

        let R = min(W, H) * 0.22 * (1 + f.bass * 0.05)
        let sc = CGPoint(x: W / 2, y: hy - R * 0.38)
        ctx.fill(Path(ellipseIn: CGRect(x: sc.x - R * 1.8, y: sc.y - R * 1.8, width: R * 3.6, height: R * 3.6)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xFF4E9A, alpha: 0.35), .clear]),
                                       center: sc, startRadius: R * 0.8, endRadius: R * 1.8))
        ctx.drawLayer { l in
            l.fill(Path(ellipseIn: CGRect(x: sc.x - R, y: sc.y - R, width: 2 * R, height: 2 * R)),
                   with: .linearGradient(Gradient(colors: [Color(hex: 0xFFE259), Color(hex: 0xFF8A3D), Color(hex: 0xFF2BD6)]),
                                         startPoint: CGPoint(x: 0, y: sc.y - R), endPoint: CGPoint(x: 0, y: sc.y + R)))
            l.blendMode = .destinationOut
            let shift = (f.t * 12).truncatingRemainder(dividingBy: Double(R) * 0.16)
            var y = sc.y + R * 0.05 + shift
            var k: CGFloat = 1
            while y < sc.y + R {
                l.fill(Path(CGRect(x: sc.x - R, y: y, width: 2 * R, height: CGFloat(2) + k * 1.6)), with: .color(.black))
                y += R * 0.16
                k += 1
            }
        }

        let n = 48
        let bands = f.bands(n)
        if ridge.count != n + 1 { ridge = Array(repeating: 0, count: n + 1) }
        var mountain = Path()
        mountain.move(to: CGPoint(x: 0, y: hy))
        for i in 0...n {
            let mirrored = i <= n / 2 ? n / 2 - i : i - n / 2
            let b = bands[min(n - 1, mirrored * 2)]
            let base = 0.2 + 0.25 * abs(sin(Double(i) * 1.7))
            let target = base + b * 0.9
            ridge[i] = target > ridge[i] ? target : max(target, ridge[i] - f.dt * 1.2)
            let x = W * CGFloat(i) / CGFloat(n)
            mountain.addLine(to: CGPoint(x: x, y: hy - CGFloat(ridge[i]) * H * 0.12))
        }
        mountain.addLine(to: CGPoint(x: W, y: hy))
        mountain.closeSubpath()
        ctx.fill(mountain, with: .color(Color(hex: 0x1A0633)))
        ctx.stroke(mountain, with: .color(Color(hex: 0x00E5FF, alpha: 0.25)), lineWidth: 6)
        ctx.stroke(mountain, with: .color(Color(hex: 0x00E5FF, alpha: 0.9)), lineWidth: 1.6)

        ctx.fill(Path(CGRect(x: 0, y: hy, width: W, height: H - hy)),
                 with: .linearGradient(Gradient(colors: [Color(hex: 0x16032E), Color(hex: 0x0A0016)]),
                                       startPoint: CGPoint(x: 0, y: hy), endPoint: CGPoint(x: 0, y: H)))
        var grid = Path()
        for i in -22...22 {
            grid.move(to: CGPoint(x: W / 2 + CGFloat(i) * W * 0.018, y: hy))
            grid.addLine(to: CGPoint(x: W / 2 + CGFloat(i) * W * 0.16, y: H))
        }
        let speed = 0.3 + f.level * 1.4
        let phase = (f.t * speed).truncatingRemainder(dividingBy: 1)
        let rows = 16
        for k in 0..<rows {
            let u = (Double(k) + phase) / Double(rows)
            let y = hy + (H - hy) * CGFloat(pow(u, 2.4))
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: W, y: y))
        }
        ctx.stroke(grid, with: .color(Color(hex: 0xFF2BD6, alpha: 0.22)), lineWidth: 5)
        ctx.stroke(grid, with: .color(Color(hex: 0xFF4FE0, alpha: 0.85)), lineWidth: 1.3)
        ctx.fill(Path(CGRect(x: 0, y: hy - 1, width: W, height: 3)), with: .color(Color(hex: 0xFFB3F0, alpha: 0.9)))
    }
}

// MARK: - Цвета обложки: мягкие переливы, как в Apple Music

final class AuroraRenderer: BackgroundRenderer {
    func draw(_ ctx: inout GraphicsContext, size: CGSize, f: Features) {
        let W = size.width, H = size.height
        let pal = f.palette.isEmpty ? ArtKit.defaultPalette : f.palette
        gradientFill(&ctx, size, [lerpColor(pal[0], 0x000000, 0.82), lerpColor(pal[min(1, pal.count - 1)], 0x000000, 0.88)])
        ctx.blendMode = .screen
        for i in 0..<6 {
            let c = pal[i % pal.count]
            let di = Double(i)
            let cx = W * (0.5 + 0.38 * sin(f.t * 0.06 * (di + 1) + di * 1.7))
            let cy = H * (0.5 + 0.36 * cos(f.t * 0.045 * (di + 1) + di * 2.3))
            let r = max(W, H) * (0.34 + 0.08 * sin(f.t * 0.1 + di)) * (1 + f.bass * 0.14)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [Color(hex: c, alpha: 0.55), Color(hex: c, alpha: 0)]),
                                           center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
        }
        ctx.blendMode = .normal
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.18)))
    }
}

// MARK: - Ночной океан: луна и волны, которые качаются под музыку

final class OceanRenderer: BackgroundRenderer {
    private var stars: [CGPoint] = []

    func draw(_ ctx: inout GraphicsContext, size: CGSize, f: Features) {
        let W = size.width, H = size.height
        if stars.isEmpty {
            var r = RNG(44)
            stars = (0..<90).map { _ in CGPoint(x: r.next(), y: r.next() * 0.5) }
        }
        gradientFill(&ctx, size, [0x060B22, 0x13265A, 0x2B4F8C], [0, 0.5, 1])
        for (i, s) in stars.enumerated() {
            let a = 0.25 + 0.5 * max(0, sin(f.t * 1.1 + Double(i) * 1.3))
            ctx.fill(Path(ellipseIn: CGRect(x: s.x * W, y: s.y * H, width: 2, height: 2)), with: .color(.white.opacity(a)))
        }
        let mr = min(W, H) * 0.065
        let mc = CGPoint(x: W * 0.78, y: H * 0.2)
        ctx.fill(Path(ellipseIn: CGRect(x: mc.x - mr * 4, y: mc.y - mr * 4, width: mr * 8, height: mr * 8)),
                 with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF6D8, alpha: 0.25), .clear]),
                                       center: mc, startRadius: mr, endRadius: mr * 4))
        ctx.fill(Path(ellipseIn: CGRect(x: mc.x - mr, y: mc.y - mr, width: 2 * mr, height: 2 * mr)), with: .color(Color(hex: 0xF7F2DC)))

        let bands = f.bands(5, from: 40, to: 6000)
        let colors: [UInt32] = [0x1E4A86, 0x17407A, 0x10336A, 0x0B2858, 0x071C44]
        for k in 0..<5 {
            let base = H * (0.56 + CGFloat(k) * 0.09)
            let amp = CGFloat(6 + Double(k) * 5) * CGFloat(1 + bands[k] * 2.2 + f.bass * 0.6)
            let freq = 0.006 - Double(k) * 0.0006
            let speed = 0.6 + Double(k) * 0.25
            var p = Path()
            p.move(to: CGPoint(x: 0, y: H))
            var x: CGFloat = 0
            while x <= W + 8 {
                let y = base + CGFloat(sin(Double(x) * freq + f.t * speed + Double(k))) * amp
                    + CGFloat(sin(Double(x) * freq * 2.3 - f.t * speed * 1.3)) * amp * 0.35
                p.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            p.addLine(to: CGPoint(x: W, y: H))
            p.closeSubpath()
            ctx.fill(p, with: .color(Color(hex: colors[k], alpha: 0.95)))
            if k < 2 {
                for j in 0..<14 {
                    let gx = mc.x + CGFloat(sin(Double(j) * 12.9 + f.t * 0.7)) * mr * 2.5
                    let gy = base + CGFloat(j) * 6 - 10
                    let a = 0.2 + 0.5 * max(0, sin(f.t * 3 + Double(j) * 1.7))
                    ctx.fill(Path(CGRect(x: gx - 10, y: gy, width: 20, height: 1.6)), with: .color(Color(hex: 0xFFF6D8, alpha: a)))
                }
            }
        }
    }
}
