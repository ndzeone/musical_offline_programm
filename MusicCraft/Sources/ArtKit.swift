import AppKit
import CoreGraphics

/// Рисование обложек, пластинок, иконки приложения и выбор цветов из обложки.
enum ArtKit {
    static let defaultPalette: [UInt32] = [0x7B2FF7, 0xF72F8C, 0xFFB347, 0x2FC6F7]

    static let gradients: [(UInt32, UInt32)] = [
        (0x7B2FF7, 0xF72F8C), (0xFF5F6D, 0xFFC371), (0x11998E, 0x38EF7D), (0x396AFC, 0x2948FF),
        (0xFC466B, 0x3F5EFB), (0xF7971E, 0xFFD200), (0x8E2DE2, 0x4A00E0), (0xEE0979, 0xFF6A00),
        (0x00C6FF, 0x0072FF), (0xDA22FF, 0x9733EE), (0xFF758C, 0xFF7EB3), (0x43CEA2, 0x185A9D),
    ]

    static func cg(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: a)
    }

    static func hash(_ s: String) -> Int {
        var h: UInt64 = 1_469_598_103_934_665_603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1_099_511_628_211 }
        return Int(h % 1_000_003)
    }

    private static func context(_ size: Int) -> CGContext {
        CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Две ноты с перемычкой (♫). Координаты CoreGraphics, ось Y вверх.
    static func notePath(in r: CGRect) -> CGPath {
        let p = CGMutablePath()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        for (cx, cy) in [(0.28, 0.22), (0.74, 0.31)] as [(CGFloat, CGFloat)] {
            let t = CGAffineTransform(translationX: r.minX + cx * r.width, y: r.minY + cy * r.height).rotated(by: 0.38)
            p.addEllipse(in: CGRect(x: -0.145 * r.width, y: -0.1 * r.height, width: 0.29 * r.width, height: 0.2 * r.height),
                         transform: t)
        }
        p.addRect(CGRect(x: r.minX + 0.365 * r.width, y: r.minY + 0.25 * r.height, width: 0.06 * r.width, height: 0.58 * r.height))
        p.addRect(CGRect(x: r.minX + 0.825 * r.width, y: r.minY + 0.34 * r.height, width: 0.06 * r.width, height: 0.58 * r.height))
        p.move(to: pt(0.365, 0.83))
        p.addLine(to: pt(0.885, 0.92))
        p.addLine(to: pt(0.885, 0.77))
        p.addLine(to: pt(0.365, 0.68))
        p.closeSubpath()
        return p
    }

    static func sparklePath(center o: CGPoint, radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: o.x, y: o.y + r))
        p.addQuadCurve(to: CGPoint(x: o.x + r, y: o.y), control: o)
        p.addQuadCurve(to: CGPoint(x: o.x, y: o.y - r), control: o)
        p.addQuadCurve(to: CGPoint(x: o.x - r, y: o.y), control: o)
        p.addQuadCurve(to: CGPoint(x: o.x, y: o.y + r), control: o)
        return p
    }

    static func drawVinyl(_ c: CGContext, center o: CGPoint, radius R: CGFloat, label: (UInt32, UInt32)) {
        c.saveGState()
        c.setFillColor(cg(0x121216))
        c.fillEllipse(in: CGRect(x: o.x - R, y: o.y - R, width: 2 * R, height: 2 * R))
        c.setLineWidth(max(1, R * 0.006))
        var rr = R * 0.95
        while rr > R * 0.4 {
            c.setStrokeColor(cg(0xFFFFFF, 0.055))
            c.strokeEllipse(in: CGRect(x: o.x - rr, y: o.y - rr, width: 2 * rr, height: 2 * rr))
            rr -= R * 0.034
        }
        c.setStrokeColor(cg(0xFFFFFF, 0.13))
        c.setLineWidth(R * 0.06)
        c.setLineCap(.round)
        for a in [0.12, 1.12] as [CGFloat] {
            c.addArc(center: o, radius: R * 0.7, startAngle: .pi * a, endAngle: .pi * (a + 0.2), clockwise: false)
            c.strokePath()
        }
        let lr = R * 0.34
        c.saveGState()
        c.addEllipse(in: CGRect(x: o.x - lr, y: o.y - lr, width: 2 * lr, height: 2 * lr))
        c.clip()
        let g = CGGradient(colorsSpace: nil, colors: [cg(label.0), cg(label.1)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: o.x - lr, y: o.y + lr), end: CGPoint(x: o.x + lr, y: o.y - lr), options: [])
        c.restoreGState()
        let hr = R * 0.045
        c.setFillColor(cg(0x121216))
        c.fillEllipse(in: CGRect(x: o.x - hr, y: o.y - hr, width: 2 * hr, height: 2 * hr))
        c.restoreGState()
    }

    // MARK: - Пластинка рядом с обложкой: рисуем один раз, потом только поворачиваем

    private static var vinylCache: [String: CGImage] = [:]

    static func vinylImage(size s: Int, label: (UInt32, UInt32)) -> CGImage {
        let key = "\(s)-\(label.0)-\(label.1)"
        if let c = vinylCache[key] { return c }
        let c = context(s)
        let S = CGFloat(s)
        drawVinyl(c, center: CGPoint(x: S / 2, y: S / 2), radius: S / 2 - 1, label: label)
        // Блик на этикетке, чтобы вращение было заметно
        c.setFillColor(cg(0xFFFFFF, 0.55))
        c.fill(CGRect(x: S / 2 + S * 0.04, y: S / 2 - S * 0.01, width: S * 0.09, height: S * 0.02))
        let img = c.makeImage()!
        if vinylCache.count > 24 { vinylCache.removeAll() }
        vinylCache[key] = img
        return img
    }

    // MARK: - Заглушка, когда настоящей обложки нет: спокойный градиент и нота

    private static var placeholderCache: [String: NSImage] = [:]

    static func placeholder(seed: String, size s: Int = 400) -> NSImage {
        let key = "\(seed)-\(s)"
        if let c = placeholderCache[key] { return c }
        let h = hash(seed)
        let (a, b) = gradients[h % gradients.count]
        let S = CGFloat(s)
        let c = context(s)
        let dark: (UInt32) -> CGColor = { col in
            let r = CGFloat((col >> 16) & 255) / 255, g = CGFloat((col >> 8) & 255) / 255, bl = CGFloat(col & 255) / 255
            return CGColor(srgbRed: r * 0.42 + 0.06, green: g * 0.42 + 0.06, blue: bl * 0.42 + 0.08, alpha: 1)
        }
        let g = CGGradient(colorsSpace: nil, colors: [dark(a), dark(b)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
        c.addPath(notePath(in: CGRect(x: S * 0.31, y: S * 0.3, width: S * 0.38, height: S * 0.4)))
        c.setFillColor(cg(0xFFFFFF, 0.32))
        c.fillPath()
        let img = NSImage(cgImage: c.makeImage()!, size: NSSize(width: s, height: s))
        if placeholderCache.count > 300 { placeholderCache.removeAll() }
        placeholderCache[key] = img
        return img
    }

    // MARK: - Обложка для трека без картинки

    private static var coverCache: [String: NSImage] = [:]

    static func cover(seed: String, size s: Int = 600) -> NSImage {
        if let c = coverCache[seed] { return c }
        let h = hash(seed)
        let (a, b) = gradients[h % gradients.count]
        let S = CGFloat(s)
        let c = context(s)
        let g = CGGradient(colorsSpace: nil, colors: [cg(a), cg(b)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
        c.setFillColor(cg(0xFFFFFF, 0.09))
        c.fillEllipse(in: CGRect(x: -S * 0.25, y: S * 0.5, width: S * 0.75, height: S * 0.75))
        c.setFillColor(cg(0x000000, 0.1))
        c.fillEllipse(in: CGRect(x: S * 0.45, y: -S * 0.35, width: S * 0.95, height: S * 0.95))
        drawVinyl(c, center: CGPoint(x: S * 0.7, y: S * 0.3), radius: S * 0.37, label: (b, a))
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.035, color: cg(0x000000, 0.35))
        c.addPath(notePath(in: CGRect(x: S * 0.09, y: S * 0.44, width: S * 0.46, height: S * 0.46)))
        c.setFillColor(cg(0xFFFFFF, 0.96))
        c.fillPath()
        c.restoreGState()
        c.setFillColor(cg(0xFFFFFF, 0.9))
        c.addPath(sparklePath(center: CGPoint(x: S * 0.83, y: S * 0.83), radius: S * 0.05)); c.fillPath()
        c.setFillColor(cg(0xFFFFFF, 0.7))
        c.addPath(sparklePath(center: CGPoint(x: S * 0.67, y: S * 0.91), radius: S * 0.026)); c.fillPath()
        let img = NSImage(cgImage: c.makeImage()!, size: NSSize(width: s, height: s))
        coverCache[seed] = img
        return img
    }

    // MARK: - Иконка приложения

    static func appIcon(size s: Int = 1024) -> CGImage {
        let S = CGFloat(s)
        let c = context(s)
        let rect = CGRect(x: S * 0.0977, y: S * 0.0977, width: S * 0.8047, height: S * 0.8047)
        let path = CGPath(roundedRect: rect, cornerWidth: S * 0.18, cornerHeight: S * 0.18, transform: nil)

        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03, color: cg(0x000000, 0.45))
        c.addPath(path); c.setFillColor(cg(0x2A1050)); c.fillPath()
        c.restoreGState()

        c.saveGState()
        c.addPath(path); c.clip()
        let bg = CGGradient(colorsSpace: nil, colors: [cg(0x5B2BF0), cg(0xE0318F), cg(0xFFA64D)] as CFArray,
                            locations: [0, 0.55, 1])!
        c.drawLinearGradient(bg, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        let glow = CGGradient(colorsSpace: nil, colors: [cg(0xFFFFFF, 0.35), cg(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        c.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.3, y: S * 0.8), startRadius: 0,
                             endCenter: CGPoint(x: S * 0.3, y: S * 0.8), endRadius: S * 0.45, options: [])
        drawVinyl(c, center: CGPoint(x: S * 0.45, y: S * 0.45), radius: S * 0.27, label: (0xFFD36B, 0xFF4F9A))
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03, color: cg(0x3A0A40, 0.5))
        c.addPath(notePath(in: CGRect(x: S * 0.43, y: S * 0.39, width: S * 0.41, height: S * 0.41)))
        c.setFillColor(cg(0xFFFFFF)); c.fillPath()
        c.restoreGState()
        for (x, y, r, a) in [(0.78, 0.8, 0.045, 0.95), (0.23, 0.79, 0.028, 0.85), (0.85, 0.3, 0.022, 0.8)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            c.setFillColor(cg(0xFFFFFF, a))
            c.addPath(sparklePath(center: CGPoint(x: S * x, y: S * y), radius: S * r)); c.fillPath()
        }
        let gloss = CGGradient(colorsSpace: nil, colors: [cg(0xFFFFFF, 0.16), cg(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(gloss, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.midY), options: [])
        c.restoreGState()

        c.addPath(path)
        c.setStrokeColor(cg(0xFFFFFF, 0.2))
        c.setLineWidth(S * 0.005)
        c.strokePath()
        return c.makeImage()!
    }

    // MARK: - Цвета обложки для фона «Цвета обложки»

    static func palette(_ img: NSImage) -> [UInt32] {
        guard let src = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return defaultPalette }
        let n = 8
        let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.interpolationQuality = .medium
        c.draw(src, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let data = c.data else { return defaultPalette }
        let px = data.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var cols: [(UInt32, Double)] = []
        for i in 0..<(n * n) {
            let r = Double(px[i * 4]) / 255, g = Double(px[i * 4 + 1]) / 255, b = Double(px[i * 4 + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b)
            let sat = mx > 0 ? (mx - mn) / mx : 0
            let hex = UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
            cols.append((hex, sat * 0.75 + mx * 0.25))
        }
        cols.sort { $0.1 > $1.1 }
        var out: [UInt32] = []
        func dist(_ a: UInt32, _ b: UInt32) -> Int {
            abs(Int((a >> 16) & 255) - Int((b >> 16) & 255)) + abs(Int((a >> 8) & 255) - Int((b >> 8) & 255))
                + abs(Int(a & 255) - Int(b & 255))
        }
        for (c, _) in cols where out.allSatisfy({ dist($0, c) > 90 }) {
            out.append(c)
            if out.count == 4 { break }
        }
        for c in defaultPalette where out.count < 4 { out.append(c) }
        return out.map { brighten($0) }
    }

    private static func brighten(_ c: UInt32) -> UInt32 {
        let r = Double((c >> 16) & 255), g = Double((c >> 8) & 255), b = Double(c & 255)
        let mx = max(r, g, b, 1)
        let k = mx < 150 ? 150 / mx : 1
        return UInt32(min(255, r * k)) << 16 | UInt32(min(255, g * k)) << 8 | UInt32(min(255, b * k))
    }
}
