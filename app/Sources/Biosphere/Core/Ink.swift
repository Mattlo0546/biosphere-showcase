import AppKit
import PDFKit

/// Finds her handwriting by comparing the PDF she sent back with the PDF the app made. Whatever is
/// darker now is her ink, so the reader only ever sees her answers (with the printed page faint behind
/// them for context), and essay lines get exact rectangles without asking a model where they are.
///
/// If the two PDFs can't be lined up (different page count or size, or a re-scan that changed every
/// pixel), `original` is nil and the sheets fall back to the plain returned page.
struct InkPage {
    let number: Int               // 1-based page number in the PDF
    let width: Int
    let height: Int
    let completed: [UInt8]        // grayscale, row 0 at the top
    let original: [UInt8]?
    let mask: [UInt8]             // 1 where she wrote (darkened by more than `Ink.detect`); empty without an original
    let inkFraction: Double

    init(number: Int, width: Int, height: Int, completed: [UInt8], original: [UInt8]?) {
        self.number = number; self.width = width; self.height = height; self.completed = completed
        guard let original, original.count == completed.count else {
            self.original = nil; mask = []; inkFraction = 0; return
        }
        self.original = original
        var mask = [UInt8](repeating: 0, count: completed.count)
        var n = 0
        original.withUnsafeBufferPointer { o in
            completed.withUnsafeBufferPointer { c in
                mask.withUnsafeMutableBufferPointer { m in
                    for i in 0..<c.count where Int(o[i]) - Int(c[i]) > Ink.detect { m[i] = 1; n += 1 }
                }
            }
        }
        self.mask = mask
        inkFraction = Double(n) / Double(max(1, completed.count))
    }

    var canSeparateInk: Bool { original != nil }

    func isInk(_ i: Int) -> Bool { canSeparateInk && mask[i] != 0 }

    /// Rows of the page (top-left pixel space) that hold any of her ink, within `columns`.
    func inkRows(_ rows: Range<Int>, columns: Range<Int>? = nil) -> [Int] {
        guard canSeparateInk else { return [] }
        let cols = columns ?? 0..<width
        return mask.withUnsafeBufferPointer { m in
            rows.filter { y in
                var n = 0
                for x in cols where m[y * width + x] != 0 { n += 1; if n >= Ink.minRowInk { return true } }
                return false
            }
        }
    }

    func hasInk(rows: Range<Int>, columns: Range<Int>? = nil) -> Bool { !inkRows(rows, columns: columns).isEmpty }
}

/// One handwritten line on a page, in pixels and as a page anchor (fractions from the top-left).
struct InkLine: Hashable {
    var page: Int
    var top: Int
    var bottom: Int
    var left: Int
    var right: Int
    var pageWidth: Int
    var pageHeight: Int

    var anchor: EssayAnchor {
        let pad = 3
        let x0 = max(0, left - pad), x1 = min(pageWidth, right + pad), y0 = max(0, top - pad), y1 = min(pageHeight, bottom + pad)
        return EssayAnchor(page: page, x: Double(x0) / Double(pageWidth), y: Double(y0) / Double(pageHeight),
                           width: Double(x1 - x0) / Double(pageWidth), height: Double(y1 - y0) / Double(pageHeight))
    }
}

enum Ink {
    /// Render width: ~2 px per point on A4, enough for handwriting and cheap for the reader.
    static let renderWidth = 1200
    /// Darkening (0–255) that counts as ink when finding answers and lines.
    static let detect = 60
    /// Softer threshold for drawing, so pen strokes keep their anti-aliased edges.
    static let draw = 18
    static let minRowInk = 2
    /// A page where more than this fraction changed isn't the page we sent (scanned, re-rendered…).
    static let maxInkFraction = 0.15

    // MARK: rendering

    static func render(_ page: PDFPage, width: Int = renderWidth) -> (pixels: [UInt8], width: Int, height: Int) {
        let box = page.bounds(for: .cropBox)
        let scale = CGFloat(width) / box.width
        let height = max(1, Int((box.height * scale).rounded()))
        var pixels = [UInt8](repeating: 255, count: width * height)
        pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            page.draw(with: .cropBox, to: ctx)   // includes markup annotations (Files / Notes on iPad)
        }
        return (pixels, width, height)
    }

    /// Her pages, each paired with the page we sent when the two line up. `only` limits work to some pages (1-based).
    static func pages(original: URL?, completed: URL, only: Set<Int>? = nil) throws -> [InkPage] {
        guard let done = PDFDocument(url: completed) else { throw ClaudeCLI.CLIError.failed("Couldn't open the completed PDF.") }
        let sent = original.flatMap { PDFDocument(url: $0) }
        let comparable = sent.map { s in
            s.pageCount == done.pageCount && (0..<done.pageCount).allSatisfy { i in
                guard let a = s.page(at: i)?.bounds(for: .cropBox), let b = done.page(at: i)?.bounds(for: .cropBox) else { return false }
                return abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
            }
        } ?? false
        var out: [InkPage] = []
        for i in 0..<done.pageCount where only?.contains(i + 1) ?? true {
            guard let page = done.page(at: i) else { continue }
            let c = render(page)
            let o = comparable ? sent?.page(at: i).map { render($0).pixels } : nil
            out.append(InkPage(number: i + 1, width: c.width, height: c.height, completed: c.pixels, original: o))
        }
        // One page that changed wholesale means the PDF was re-scanned: don't trust any diff.
        if out.contains(where: { $0.inkFraction > maxInkFraction }) {
            out = out.map { InkPage(number: $0.number, width: $0.width, height: $0.height, completed: $0.completed, original: nil) }
        }
        return out
    }

    // MARK: lines

    /// Handwritten lines on a page: rows of ink grouped across small gaps, tall blobs (touching lines)
    /// split at their thinnest row, specks dropped.
    static func lines(on page: InkPage, rows: Range<Int>? = nil) -> [InkLine] {
        guard page.canSeparateInk else { return [] }
        let range = rows ?? 0..<page.height
        var counts = [Int](repeating: 0, count: page.height)
        page.mask.withUnsafeBufferPointer { m in
            for y in range {
                var n = 0
                let base = y * page.width
                for x in 0..<page.width where m[base + x] != 0 { n += 1 }
                counts[y] = n
            }
        }
        var bands: [(Int, Int)] = []
        var start: Int?, last = -100
        for y in range where counts[y] >= minRowInk {
            if let s = start, y - last > 8 { bands.append((s, last + 1)); start = y } else if start == nil { start = y }
            last = y
        }
        if let s = start { bands.append((s, last + 1)) }
        bands = bands.filter { b in (b.0..<b.1).reduce(0) { $0 + counts[$1] } >= 25 }   // specks and dust

        let heights = bands.map { $0.1 - $0.0 }.filter { $0 >= 10 }.sorted()
        let typical = heights.isEmpty ? 40 : heights[heights.count / 2]
        func split(_ b: (Int, Int)) -> [(Int, Int)] {
            let h = b.1 - b.0
            guard h > max(Int(Double(typical) * 1.8), 70) else { return [b] }
            let lo = b.0 + h * 3 / 10, hi = b.1 - h * 3 / 10
            guard lo < hi, let cut = (lo..<hi).min(by: { counts[$0] < counts[$1] }) else { return [b] }
            return split((b.0, cut)) + split((cut, b.1))
        }
        return bands.flatMap(split).compactMap { b in
            var left = page.width, right = 0
            page.mask.withUnsafeBufferPointer { m in
                for y in b.0..<b.1 {
                    let base = y * page.width
                    for x in 0..<page.width where m[base + x] != 0 { left = min(left, x); right = max(right, x + 1) }
                }
            }
            guard right > left else { return nil }
            return InkLine(page: page.number, top: b.0, bottom: b.1, left: left, right: right,
                           pageWidth: page.width, pageHeight: page.height)
        }
    }

    // MARK: reading sheets

    /// Her ink at full strength over a faint copy of the printed page, cropped to `rows` × `columns`.
    /// Optional `tags` add a left gutter with line ids beside each handwritten line.
    static func sheet(_ page: InkPage, rows: Range<Int>, columns: Range<Int>? = nil,
                      tags: [(line: InkLine, id: String)] = []) -> Data? {
        let cols = columns ?? 0..<page.width
        let gutter = tags.isEmpty ? 0 : 76
        let w = cols.count + gutter, h = rows.count
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: w * h)
        let original = page.original ?? page.completed
        let separate = page.canSeparateInk
        pixels.withUnsafeMutableBufferPointer { out in
            original.withUnsafeBufferPointer { o in
                page.completed.withUnsafeBufferPointer { c in
                    for (yy, y) in rows.enumerated() {
                        let src = y * page.width, dst = yy * w + gutter
                        for (xx, x) in cols.enumerated() {
                            let i = src + x
                            // Ink at full strength (soft threshold keeps stroke edges); print at ~22% so it's only context.
                            out[dst + xx] = !separate || Int(o[i]) - Int(c[i]) > draw ? c[i] : 255 - UInt8((Int(255 - o[i]) * 22) / 100)
                        }
                    }
                }
            }
        }
        guard let image = pixels.withUnsafeMutableBytes({ buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            if !tags.isEmpty {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                ctx.setStrokeColor(gray: 0.75, alpha: 1); ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: gutter - 4, y: 0)); ctx.addLine(to: CGPoint(x: gutter - 4, y: h)); ctx.strokePath()
                for tag in tags {
                    let mid = (tag.line.top + tag.line.bottom) / 2 - rows.lowerBound
                    guard (0..<h).contains(mid) else { continue }
                    NSAttributedString(string: tag.id, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 17, weight: .bold),
                                                                    .foregroundColor: NSColor.black])
                        .draw(at: CGPoint(x: 4, y: CGFloat(h - mid) - 11))
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            return ctx.makeImage()
        }) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Pixel rows covered by a placement (fractions of the page from the top), clamped to the page.
    static func rows(_ p: Placement, in page: InkPage) -> Range<Int> {
        let y0 = max(0, Int((p.y0 * Double(page.height)).rounded(.down)))
        let y1 = min(page.height, Int((p.y1 * Double(page.height)).rounded(.up)))
        return y0..<max(y0, y1)
    }

    static func columns(_ p: Placement, in page: InkPage) -> Range<Int> {
        let x0 = max(0, Int((p.x0 * Double(page.width)).rounded(.down)))
        let x1 = min(page.width, Int((p.x1 * Double(page.width)).rounded(.up)))
        return x0..<max(x0, x1)
    }
}
