// Draws the Biosphere app icon (purple orb with a leaf) at every size iconutil needs.
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let inset = s * 0.09
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.23, cornerHeight: tile.width * 0.23, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(calibratedRed: 0.20, green: 0.07, blue: 0.42, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.47, green: 0.22, blue: 0.86, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.minY), end: CGPoint(x: tile.maxX, y: tile.maxY), options: [])
    // the "biosphere" orb
    let r = tile.width * 0.33
    let c = CGPoint(x: tile.midX, y: tile.midY)
    let orb = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(calibratedRed: 0.93, green: 0.86, blue: 1.0, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.70, green: 0.48, blue: 1.0, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.45, green: 0.22, blue: 0.85, alpha: 1).cgColor] as CFArray, locations: [0, 0.5, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)); ctx.clip()
    ctx.drawRadialGradient(orb, startCenter: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.4), startRadius: 0, endCenter: c, endRadius: r * 1.05, options: [])
    ctx.restoreGState()
    // orbit ring
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor); ctx.setLineWidth(s * 0.018)
    ctx.saveGState(); ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: -0.45)
    ctx.strokeEllipse(in: CGRect(x: -r * 1.38, y: -r * 0.42, width: r * 2.76, height: r * 0.84))
    ctx.restoreGState()
    // leaf
    if let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: r * 1.05, weight: .bold)) {
        let tinted = NSImage(size: leaf.size, flipped: false) { rect in
            leaf.draw(in: rect); NSColor(calibratedRed: 0.24, green: 0.10, blue: 0.50, alpha: 1).set(); rect.fill(using: .sourceAtop); return true
        }
        let w = leaf.size.width, h = leaf.size.height
        tinted.draw(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
    }
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
