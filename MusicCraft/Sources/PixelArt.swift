import CoreGraphics
import Foundation

// Пиксель-арт: всё рисуется кодом, никаких картинок из интернета.
// Цвета хранятся как 0xAARRGGBB (формат BGRA в памяти).

struct RNG {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> Double {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return Double(s % 1_000_000) / 1_000_000
    }
    mutating func pick<T>(_ a: [T]) -> T { a[Int(next() * Double(a.count)) % a.count] }
}

@inline(__always) func opaque(_ rgb: UInt32) -> UInt32 { 0xFF00_0000 | rgb }

func lerpColor(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    let t = min(1, max(0, t))
    func ch(_ s: UInt32) -> UInt32 {
        let x = Double((a >> s) & 255), y = Double((b >> s) & 255)
        return UInt32((x + (y - x) * t).rounded()) << s
    }
    return ch(16) | ch(8) | ch(0)
}

enum Pix {
    static let space = CGColorSpaceCreateDeviceRGB()
    static let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

    static func make(_ w: Int, _ h: Int, seed: UInt64 = 1, _ f: (Int, Int, inout RNG) -> UInt32) -> [UInt32] {
        var r = RNG(seed)
        var a = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { a[y * w + x] = f(x, y, &r) } }
        return a
    }

    static func image(_ px: [UInt32], _ w: Int, _ h: Int) -> CGImage {
        let data = px.withUnsafeBufferPointer { Data(buffer: $0) }
        let prov = CGDataProvider(data: data as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: space, bitmapInfo: info, provider: prov, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func pattern(_ rows: [String], _ pal: [Character: UInt32]) -> CGImage {
        let h = rows.count, w = rows.map(\.count).max() ?? 1
        var a = [UInt32](repeating: 0, count: w * h)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() { if let c = pal[ch] { a[y * w + x] = c } }
        }
        return image(a, w, h)
    }
}

// MARK: - Блоки

enum Blocks {
    static let dirtC: [UInt32] = [0x866043, 0x79553A, 0x966C4A, 0x6C4A31, 0x8B6446, 0x593D29]
    static let grassC: [UInt32] = [0x5D9A30, 0x6AAE3A, 0x7DC24A, 0x4F8A28, 0x5B8C32]
    static let stoneC: [UInt32] = [0x7F7F7F, 0x8F8F8F, 0x747474, 0x686868, 0x9A9A9A]
    static let bedrockC: [UInt32] = [0x565656, 0x3A3A3A, 0x7A7A7A, 0x2B2B2B, 0x4A4A4A]
    static let woodC: [UInt32] = [0x6B4A2B, 0x5E3F24, 0x7A5634]

    static let dirt = Pix.make(16, 16, seed: 7) { _, _, r in opaque(r.pick(dirtC)) }
    static let grass = Pix.make(16, 16, seed: 11) { x, y, r in
        let d = opaque(r.pick(dirtC)), g = opaque(r.pick(grassC))
        let edge = 3 + ((x * 7 + 3) % 3 == 0 ? 1 : 0) + ((x * 5) % 4 == 0 ? 1 : 0)
        return y < edge ? g : d
    }
    static let stone = Pix.make(16, 16, seed: 3) { _, _, r in opaque(r.pick(stoneC)) }
    static let bedrock = Pix.make(16, 16, seed: 13) { _, _, r in opaque(r.pick(bedrockC)) }

    private static let oreSpots: Set<Int> = [3 * 16 + 3, 3 * 16 + 4, 4 * 16 + 3, 4 * 16 + 4, 4 * 16 + 10, 4 * 16 + 11,
                                              5 * 16 + 11, 5 * 16 + 12, 10 * 16 + 5, 10 * 16 + 6, 11 * 16 + 6,
                                              11 * 16 + 7, 11 * 16 + 11, 11 * 16 + 12, 12 * 16 + 12]
    static func ore(_ c1: UInt32, _ c2: UInt32, seed: UInt64) -> [UInt32] {
        Pix.make(16, 16, seed: seed) { x, y, r in
            let s = opaque(r.pick(stoneC))
            return oreSpots.contains(y * 16 + x) ? opaque((x + y) % 3 == 0 ? c2 : c1) : s
        }
    }
    // уголь, золото, редстоун, алмаз, изумруд
    static let ores = [ore(0x2A2A2A, 0x4A4A4A, seed: 21), ore(0xFCEE4B, 0xFFFFB5, seed: 22),
                       ore(0xE01010, 0xFF6060, seed: 23), ore(0x4AEDD9, 0xC8FFF4, seed: 24),
                       ore(0x17DD62, 0x7EFFA8, seed: 25)]

    static let noteMask: [[Bool]] = Art.noteRows.map { $0.map { $0 == "X" } }
    static let noteBlock = Pix.make(16, 16, seed: 31) { x, y, r in
        if x == 0 || y == 0 || x == 15 || y == 15 { return opaque(0x3F2A16) }
        if x == 1 || y == 1 || x == 14 || y == 14 { return opaque(0x8A6440) }
        let nx = x - 5, ny = y - 4
        if ny >= 0, ny < noteMask.count, nx >= 0, nx < noteMask[ny].count, noteMask[ny][nx] { return opaque(0x2A1A0C) }
        return opaque(r.pick(woodC))
    }
    static let jukebox = Pix.make(16, 16, seed: 41) { x, y, r in
        if x == 0 || y == 0 || x == 15 || y == 15 { return opaque(0x3F2A16) }
        if x == 1 || y == 1 || x == 14 || y == 14 { return opaque(0x8A6440) }
        if (3...12).contains(x) && (3...12).contains(y) {
            if x == 3 || y == 3 { return opaque(0x2E1E10) }
            if x == 12 || y == 12 { return opaque(0x9A7048) }
            return opaque(r.pick([0x4E3520, 0x563A22, 0x49311D]))
        }
        return opaque(r.pick(woodC))
    }
}

// MARK: - Иконки и предметы

enum Art {
    static let noteRows = [
        "...XX.",
        "...XXX",
        "...X.X",
        "...X..",
        ".XXX..",
        "XXXX..",
        "XXXX..",
        ".XX...",
    ]

    // Цвета частиц нот, как у нотного блока
    static let noteColors: [UInt32] = [0x77D700, 0x95C000, 0xB2A500, 0xCC8600, 0xE26500, 0xF34100, 0xFC1E00, 0xFE000F,
                                       0xF70033, 0xE8005A, 0xCF0083, 0xAE00A9, 0x8600CC, 0x5B00E7, 0x2D00F9, 0x020AFE,
                                       0x0037F6, 0x0068E0, 0x009ABC, 0x00C68D, 0x00E958, 0x00FC21, 0x1FFC00, 0x59E800]
    static let notes: [CGImage] = noteColors.map { Pix.pattern(noteRows, ["X": opaque($0)]) }

    private static let W: [Character: UInt32] = ["X": opaque(0xFFFFFF), "s": opaque(0xA8A8A8)]
    static let play = Pix.pattern([
        "XX.......", "XXXX.....", "XXXXXX...", "XXXXXXXX.", "XXXXXXXXX",
        "XXXXXXXX.", "XXXXXX...", "XXXX.....", "XX.......",
    ], W)
    static let pause = Pix.pattern(Array(repeating: "XXX...XXX", count: 9), W)
    static let stop = Pix.pattern([
        ".........", ".XXXXXXX.", ".XXXXXXX.", ".XXXXXXX.", ".XXXXXXX.",
        ".XXXXXXX.", ".XXXXXXX.", ".XXXXXXX.", ".........",
    ], W)
    private static let nextRows = ["X...X...X", "XX..XX..X", "XXX.XXX.X", "XXXXXXXXX", "XXX.XXX.X", "XX..XX..X", "X...X...X"]
    static let next = Pix.pattern(nextRows, W)
    static let prev = Pix.pattern(nextRows.map { String($0.reversed()) }, W)
    static let repeatAll = Pix.pattern([
        "......X..", ".XXXXXXX.", "X.....X..", "X........", "X.......X",
        "........X", "..X.....X", ".XXXXXXX.", "..X......",
    ], W)
    static let repeatOne = Pix.pattern([
        "......X..", ".XXXXXXX.", "X...X.X..", "X..XX....", "X...X...X",
        "....X...X", "..X.X...X", ".XXXXXXX.", "..X......",
    ], W)
    static let shuffle = Pix.pattern([
        "......X..", "XX..XXXX.", "..XX..X..", "...X.....", "..XX..X..", "XX..XXXX.", "......X..",
    ], W)

    static let chest = Pix.image(Pix.make(16, 16) { x, y, _ in
        guard (1...14).contains(x), (2...14).contains(y) else { return 0 }
        if x == 1 || x == 14 || y == 2 || y == 14 || y == 7 { return opaque(0x2B1A0A) }
        if (7...8).contains(x) && (6...9).contains(y) { return opaque(y == 9 ? 0x6A6A6A : 0xD8D8D8) }
        let wood: UInt32 = y < 7 ? 0xA8702F : 0x94602A
        return opaque((x + y * 3) % 7 == 0 ? 0x7A4C1E : wood)
    }, 16, 16)

    static let book = Pix.image(Pix.make(16, 16) { x, y, _ in
        guard (3...13).contains(x), (1...14).contains(y) else { return 0 }
        if x == 3 || y == 1 || y == 14 || x == 13 { return opaque(0x3B1E0E) }
        if x == 12 { return opaque(0xF2EAD2) }
        if x == 4 { return opaque(0x5A2E14) }
        if y == 5 && (6...10).contains(x) { return opaque(0xE8C35A) }
        if y == 10 && (6...10).contains(x) { return opaque(0xE8C35A) }
        return opaque(0x8B3A1A)
    }, 16, 16)

    static let gear = Pix.image(Pix.make(16, 16) { x, y, _ in
        let dx = Double(x) - 7.5, dy = Double(y) - 7.5
        let d = (dx * dx + dy * dy).squareRoot(), a = atan2(dy, dx)
        if d < 2.2 { return 0 }
        if d < 3.0 { return opaque(0x3A3A3A) }
        if d < 5.2 { return opaque(d < 4.2 ? 0xC4C4C4 : 0x9A9A9A) }
        if d < 7.4 && cos(a * 8) > 0.25 { return opaque(0x7A7A7A) }
        return 0
    }, 16, 16)

    // Сердца = громкость
    private static let heartRows = [
        ".ooo.ooo.", "orwrorrro", "owrrrrrro", "orrrrrrro",
        ".orrrrro.", "..orrro..", "...oro...", "....o....",
    ]
    static let heartFull = Pix.pattern(heartRows, ["o": opaque(0x140000), "r": opaque(0xE3201B), "w": opaque(0xFFB6B6)])
    static let heartEmpty = Pix.pattern(heartRows, ["o": opaque(0x140000), "r": opaque(0x3D1010), "w": opaque(0x3D1010)])
    static let heartHalf = Pix.pattern(heartRows.map { row in
        String(row.enumerated().map { i, c in i > 4 && (c == "r" || c == "w") ? "e" : c })
    }, ["o": opaque(0x140000), "r": opaque(0xE3201B), "w": opaque(0xFFB6B6), "e": opaque(0x3D1010)])

    // Еда = басы
    private static let meatRows = [
        "..ooo....", ".oMmmo...", "oMmmmmo..", "ommmmmo..", "ommmmmo..",
        ".ommmwo..", "..ooowwo.", "......wwo", ".......o.",
    ]
    static let meatFull = Pix.pattern(meatRows, ["o": opaque(0x2A1400), "m": opaque(0xB5651D), "M": opaque(0xE0A060), "w": opaque(0xF0F0E0)])
    static let meatEmpty = Pix.pattern(meatRows, ["o": opaque(0x2A1400), "m": opaque(0x3A2A1A), "M": opaque(0x3A2A1A), "w": opaque(0x4A4A40)])
    static let meatHalf = Pix.pattern(meatRows.map { row in
        String(row.enumerated().map { i, c in i < 4 && (c == "m" || c == "M") ? "e" : c })
    }, ["o": opaque(0x2A1400), "m": opaque(0xB5651D), "M": opaque(0xE0A060), "w": opaque(0xF0F0E0), "e": opaque(0x3A2A1A)])

    // Пластинки
    static let discColors: [UInt32] = [0xF9D71C, 0x4CAF50, 0xE53935, 0x1E88E5, 0x8E24AA, 0xFF7043, 0x26C6DA, 0xEC407A]
    static let discs: [CGImage] = discColors.map { color in
        Pix.image(Pix.make(16, 16) { x, y, _ in
            let d = hypot(Double(x) - 7.5, Double(y) - 7.5)
            if d > 7.4 { return 0 }
            if d > 6.5 { return opaque(0x0B0B0B) }
            if d < 1.1 { return opaque(0x050505) }
            if d < 2.7 { return opaque(color) }
            if d > 4.3 && d < 5.2 && x < 8 && y < 8 { return opaque(0x4A4A4A) }
            return opaque((x * 3 + y) % 5 == 0 ? 0x353535 : 0x222222)
        }, 16, 16)
    }
}

// MARK: - Рендер рельефа (эквалайзер из блоков)

final class TerrainRenderer {
    private(set) var cols = 0
    private(set) var rows = 0
    private var buf: UnsafeMutablePointer<UInt32>?
    private var ctx: CGContext?

    func resize(cols: Int, rows: Int) {
        guard cols != self.cols || rows != self.rows else { return }
        buf?.deallocate()
        self.cols = cols; self.rows = rows
        let n = cols * 16 * rows * 16
        let b = UnsafeMutablePointer<UInt32>.allocate(capacity: n)
        b.initialize(repeating: 0, count: n)
        buf = b
        ctx = CGContext(data: b, width: cols * 16, height: rows * 16, bitsPerComponent: 8,
                        bytesPerRow: cols * 16 * 4, space: Pix.space, bitmapInfo: Pix.info.rawValue)
    }

    deinit { buf?.deallocate() }

    func render(heights: [Int], peaks: [Int], showPeaks: Bool) -> CGImage? {
        guard let buf, let ctx, heights.count >= cols, peaks.count >= cols else { return nil }
        let w = cols * 16
        buf.update(repeating: 0, count: w * rows * 16)
        for c in 0..<cols {
            let h = min(rows, max(1, heights[c]))
            for r in 0..<h { blit(texture(c, r, h), c, r, w, buf) }
            if showPeaks, peaks[c] > h, peaks[c] < rows { blit(Blocks.noteBlock, c, peaks[c], w, buf) }
        }
        return ctx.makeImage()
    }

    private func texture(_ c: Int, _ r: Int, _ h: Int) -> [UInt32] {
        if r == h - 1 { return Blocks.grass }
        if r == 0 { return Blocks.bedrock }
        if r <= 1 + h / 3 {
            let hash = (c &* 73_856_093) ^ (r &* 19_349_663)
            let v = abs(hash) % 1000
            if v % 7 == 0 { return Blocks.ores[(v / 7) % Blocks.ores.count] }
            return Blocks.stone
        }
        return Blocks.dirt
    }

    private func blit(_ t: [UInt32], _ c: Int, _ r: Int, _ w: Int, _ buf: UnsafeMutablePointer<UInt32>) {
        let x0 = c * 16, y0 = (rows - 1 - r) * 16
        t.withUnsafeBufferPointer { src in
            for y in 0..<16 { (buf + (y0 + y) * w + x0).update(from: src.baseAddress! + y * 16, count: 16) }
        }
    }
}
