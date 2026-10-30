// Generates MacHelm's brand assets: app icon (.iconset), README banner, DMG background.
// Usage: swift scripts/make_assets.swift <output-dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/assets")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}

func bitmap(_ w: Int, _ h: Int, pointSize: NSSize? = nil) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    if let p = pointSize { rep.size = p }
    return rep
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

/// Draws the MacHelm icon into a square of side `size` whose origin is (0,0).
func drawIcon(_ ctx: CGContext, size: CGFloat) {
    let inset = size * 0.098
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = body.width * 0.2237
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let c = CGPoint(x: size / 2, y: size / 2)
    let u = body.width // unit

    // drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.014), blur: size * 0.035, color: rgb(0x000000, 0.45))
    ctx.addPath(path); ctx.setFillColor(rgb(0x0B0E2A)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()

    // base gradient
    ctx.drawLinearGradient(gradient([(0, rgb(0x0C1038)), (0.55, rgb(0x2B1B7A)), (1, rgb(0x7A2BC4))]),
                           start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // cyan glow behind the wheel
    ctx.drawRadialGradient(gradient([(0, rgb(0x42E8FF, 0.38)), (1, rgb(0x42E8FF, 0))]),
                           startCenter: c, startRadius: 0, endCenter: c, endRadius: u * 0.52, options: [])
    // faint orbit rings
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.07)); ctx.setLineWidth(u * 0.006)
    for r in [0.46, 0.56, 0.68] {
        ctx.strokeEllipse(in: CGRect(x: c.x - u * r, y: c.y - u * r, width: u * r * 2, height: u * r * 2))
    }

    // wheel
    let ringR = u * 0.255
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: u * 0.05, color: rgb(0x4DE8FF, 0.9))
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(0xF2FAFF))
    ctx.setLineWidth(u * 0.05)
    ctx.strokeEllipse(in: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2))
    ctx.setLineWidth(u * 0.034)
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + .pi / 8
        ctx.move(to: CGPoint(x: c.x + cos(a) * u * 0.07, y: c.y + sin(a) * u * 0.07))
        ctx.addLine(to: CGPoint(x: c.x + cos(a) * u * 0.335, y: c.y + sin(a) * u * 0.335))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // handles = the machines
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + .pi / 8
        let p = CGPoint(x: c.x + cos(a) * u * 0.355, y: c.y + sin(a) * u * 0.355)
        let r = u * 0.046
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: u * 0.03, color: rgb(0x4DE8FF, 0.95))
        ctx.setFillColor(i % 2 == 0 ? rgb(0x7DF9FF) : rgb(0xFFFFFF))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }

    // hub
    let hubR = u * 0.088
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: u * 0.05, color: rgb(0x4DE8FF, 1))
    ctx.addEllipse(in: CGRect(x: c.x - hubR, y: c.y - hubR, width: hubR * 2, height: hubR * 2)); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF)), (1, rgb(0x5CE6FF))]),
                           start: CGPoint(x: c.x - hubR, y: c.y + hubR), end: CGPoint(x: c.x + hubR, y: c.y - hubR), options: [])
    ctx.restoreGState()
    ctx.setFillColor(rgb(0x2B1B7A))
    let dot = u * 0.03
    ctx.fillEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))

    // top gloss
    ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.20)), (1, rgb(0xFFFFFF, 0))]),
                           start: CGPoint(x: c.x, y: body.maxY), end: CGPoint(x: c.x, y: body.midY), options: [])
    ctx.restoreGState()

    // edge
    ctx.addPath(path); ctx.setStrokeColor(rgb(0xFFFFFF, 0.14)); ctx.setLineWidth(max(1, size * 0.003)); ctx.strokePath()
}

func withContext(_ rep: NSBitmapImageRep, _ body: (CGContext) -> Void) {
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    body(g.cgContext)
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: kern,
    ]
    NSAttributedString(string: s, attributes: attrs).draw(at: p)
}

// 1. iconset
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = bitmap(px, px)
        withContext(rep) { drawIcon($0, size: CGFloat(px)) }
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let big = bitmap(1024, 1024)
withContext(big) { drawIcon($0, size: 1024) }
save(big, "logo.png")

// 2. README banner / social preview (1280x640)
let banner = bitmap(1280, 640)
withContext(banner) { ctx in
    ctx.drawLinearGradient(gradient([(0, rgb(0x070918)), (0.6, rgb(0x15103A)), (1, rgb(0x2A1257))]),
                           start: CGPoint(x: 0, y: 640), end: CGPoint(x: 1280, y: 0), options: [])
    ctx.drawRadialGradient(gradient([(0, rgb(0x42E8FF, 0.22)), (1, rgb(0x42E8FF, 0))]),
                           startCenter: CGPoint(x: 330, y: 320), startRadius: 0, endCenter: CGPoint(x: 330, y: 320), endRadius: 460, options: [])
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.04)); ctx.setLineWidth(1)
    for x in stride(from: 0, to: 1280, by: 40) { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: 640)); ctx.strokePath() }
    for y in stride(from: 0, to: 640, by: 40) { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: 1280, y: y)); ctx.strokePath() }
    ctx.saveGState(); ctx.translateBy(x: 70, y: 50); drawIcon(ctx, size: 540); ctx.restoreGState()
    text("MacHelm", at: CGPoint(x: 600, y: 330), size: 128, weight: .heavy, color: .white, kern: -3)
    text("Command every Mac you own.", at: CGPoint(x: 606, y: 270), size: 42, weight: .medium, color: NSColor(cgColor: rgb(0x9FB4FF))!)
    text("REMOTE CONTROL  ·  SESSIONS  ·  FILES  ·  FLEET AUTOMATION", at: CGPoint(x: 608, y: 205), size: 17, weight: .semibold,
         color: NSColor(cgColor: rgb(0x7DF9FF))!, kern: 1.6)
    text("Native macOS app  ·  Open source  ·  No agents to install", at: CGPoint(x: 608, y: 160), size: 22, weight: .regular,
         color: NSColor(white: 1, alpha: 0.5))
}
save(banner, "banner.png")

// 3. DMG background (660x400 points @2x)
let dmg = bitmap(1320, 800, pointSize: NSSize(width: 660, height: 400))
withContext(dmg) { ctx in
    ctx.scaleBy(x: 2, y: 2)
    ctx.drawLinearGradient(gradient([(0, rgb(0x0A0D26)), (1, rgb(0x241153))]),
                           start: CGPoint(x: 0, y: 400), end: CGPoint(x: 660, y: 0), options: [])
    ctx.drawRadialGradient(gradient([(0, rgb(0x42E8FF, 0.16)), (1, rgb(0x42E8FF, 0))]),
                           startCenter: CGPoint(x: 330, y: 190), startRadius: 0, endCenter: CGPoint(x: 330, y: 190), endRadius: 300, options: [])
    // arrow between the two icon slots (icons sit at x=170 and x=490, y=185 from top)
    ctx.setStrokeColor(rgb(0x7DF9FF, 0.85)); ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setLineDash(phase: 0, lengths: [2, 12])
    ctx.move(to: CGPoint(x: 262, y: 215)); ctx.addLine(to: CGPoint(x: 388, y: 215)); ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.move(to: CGPoint(x: 376, y: 229)); ctx.addLine(to: CGPoint(x: 394, y: 215)); ctx.addLine(to: CGPoint(x: 376, y: 201)); ctx.strokePath()
    text("Drag MacHelm to Applications", at: CGPoint(x: 330 - 122, y: 330), size: 21, weight: .semibold, color: .white)
    text("then open it from Launchpad", at: CGPoint(x: 330 - 90, y: 306), size: 14, weight: .regular, color: NSColor(white: 1, alpha: 0.55))
}
save(dmg, "dmg-background.png")
print("assets written to \(out.path)")
