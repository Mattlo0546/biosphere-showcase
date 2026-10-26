import AppKit
import CoreGraphics

/// Builds a session PDF by cropping question regions out of the original papers (vector, so
/// diagrams stay sharp) and stacking them on A4 pages under numbered headers.
enum PDFComposer {
    static let page = CGSize(width: 595.28, height: 841.89)
    static let side: CGFloat = 30
    static let top: CGFloat = 40
    static let bottom: CGFloat = 46
    static var contentWidth: CGFloat { page.width - side * 2 }

    static let purple = NSColor(calibratedRed: 0.43, green: 0.22, blue: 0.80, alpha: 1)
    static let lilac = NSColor(calibratedRed: 0.95, green: 0.92, blue: 1.0, alpha: 1)

    struct Output { var placements: [String: [Placement]]; var pageCount: Int }

    enum ComposeError: Error { case cannotCreate, missingPaper(String) }

    static func compose(session: StudySession, questions: [Question], bank: Bank, syllabus: Syllabus,
                        to url: URL) throws -> Output {
        var box = CGRect(origin: .zero, size: page)
        let info: [CFString: Any] = [kCGPDFContextTitle: "Biosphere \(session.id) – \(session.title)",
                                     kCGPDFContextCreator: "Biosphere"]
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { throw ComposeError.cannotCreate }
        let gfx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = gfx
        defer { NSGraphicsContext.current = nil }

        var docs: [String: CGPDFDocument] = [:]
        var placements: [String: [Placement]] = [:]
        var pageIndex = -1
        var cursor: CGFloat = 0           // distance from the top of the page
        let limit = page.height - bottom

        func newPage() {
            if pageIndex >= 0 { ctx.endPDFPage() }
            ctx.beginPDFPage(nil)
            pageIndex += 1
            cursor = top
            drawFooter(ctx: ctx, session: session, pageNumber: pageIndex + 1)
        }
        func place(_ qid: String, _ y0: CGFloat, _ y1: CGFloat) {
            placements[qid, default: []].append(Placement(page: pageIndex, x0: Double(side / page.width), y0: Double(y0 / page.height),
                                                          x1: Double((page.width - side) / page.width), y1: Double(y1 / page.height)))
        }

        newPage()
        let strategies = syllabus.isStrategyBank
        cursor = drawTitleBlock(session: session, questions: questions, maths: strategies)
        if strategies { cursor = drawStrategyCard(session: session, syllabus: syllabus, top: cursor) }

        for (i, q) in questions.enumerated() {
            guard let doc = docs[q.paperId] ?? CGPDFDocument(bank.paperURL(q.paperId) as CFURL) else {
                throw ComposeError.missingPaper(q.paperId)
            }
            docs[q.paperId] = doc
            // Keep the header with its first crop: if they don't fit together, start a new page.
            let maxCrop = limit - top - 34
            let firstH = min(q.regions.first.flatMap { regionSize(doc: doc, region: $0)?.height } ?? 100, maxCrop)
            if cursor + 30 + firstH > limit && cursor > top + 1 { newPage() }

            let headerTop = cursor
            drawHeader(number: i + 1, question: q, syllabus: syllabus, top: cursor, hideStrategy: strategies)
            cursor += 30
            var first = true
            for region in q.regions {
                guard let pg = doc.page(at: region.page + 1), let src = sourceRect(pg, region) else { continue }
                var scale = contentWidth / src.width
                let maxH = limit - top - 34
                if src.height * scale > maxH { scale = maxH / src.height }
                let h = src.height * scale
                if cursor + h > limit {
                    if first { place(q.id, headerTop, cursor) }
                    newPage()
                }
                let regionTop = first && cursor == headerTop + 30 ? headerTop : cursor
                let dest = CGRect(x: side + (contentWidth - src.width * scale) / 2, y: page.height - cursor - h,
                                  width: src.width * scale, height: h)
                drawCrop(ctx: ctx, page: pg, src: src, dest: dest)
                cursor += h + 4
                place(q.id, regionTop, cursor)
                first = false
            }
            if q.needsSpace && !q.isMCQ {
                var lines = min(max(q.marks * 3, 8), 60)
                if cursor + 60 > limit { newPage() }
                drawLabel(strategies ? "Working" : "Answer", at: cursor + 4)
                cursor += 18
                var blockTop = cursor
                while lines > 0 {
                    if cursor + 22 > limit {
                        place(q.id, blockTop, cursor)
                        newPage(); blockTop = cursor
                    }
                    ctx.setStrokeColor(NSColor(calibratedWhite: 0.78, alpha: 1).cgColor)
                    ctx.setLineWidth(0.6)
                    ctx.move(to: CGPoint(x: side + 8, y: page.height - cursor - 20))
                    ctx.addLine(to: CGPoint(x: page.width - side - 8, y: page.height - cursor - 20))
                    ctx.strokePath()
                    cursor += 22; lines -= 1
                }
                place(q.id, blockTop, cursor)
            }
            cursor += 16
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return Output(placements: placements, pageCount: pageIndex + 1)
    }

    // MARK: drawing helpers

    static func sourceRect(_ pg: CGPDFPage, _ r: Region) -> CGRect? {
        let b = pg.getBoxRect(.cropBox)
        guard b.width > 0 else { return nil }
        return CGRect(x: b.minX + r.x0 * b.width, y: b.maxY - r.y1 * b.height,
                      width: (r.x1 - r.x0) * b.width, height: (r.y1 - r.y0) * b.height)
    }

    static func regionSize(doc: CGPDFDocument, region: Region) -> CGSize? {
        guard let pg = doc.page(at: region.page + 1), let r = sourceRect(pg, region) else { return nil }
        let s = contentWidth / r.width
        return CGSize(width: r.width * s, height: r.height * s)
    }

    static func drawCrop(ctx: CGContext, page pg: CGPDFPage, src: CGRect, dest: CGRect) {
        ctx.saveGState()
        ctx.clip(to: dest)
        let s = dest.width / src.width
        ctx.translateBy(x: dest.minX - src.minX * s, y: dest.minY - src.minY * s)
        ctx.scaleBy(x: s, y: s)
        ctx.drawPDFPage(pg)
        ctx.restoreGState()
    }

    static func drawText(_ s: String, rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular,
                         color: NSColor = .black, align: NSTextAlignment = .left) {
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                   .foregroundColor: color, .paragraphStyle: p]).draw(in: rect)
    }

    /// Wrapping text measured from the top of the page; returns its height.
    @discardableResult
    static func drawWrapped(_ s: String, x: CGFloat, top: CGFloat, width: CGFloat, size: CGFloat,
                            weight: NSFont.Weight = .regular, color: NSColor = .black, draw: Bool = true) -> CGFloat {
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping
        let text = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                              .foregroundColor: color, .paragraphStyle: p])
        let h = ceil(text.boundingRect(with: CGSize(width: width, height: 2000), options: [.usesLineFragmentOrigin]).height)
        if draw { text.draw(with: rectFromTop(x: x, top: top, width: width, height: h), options: [.usesLineFragmentOrigin]) }
        return h
    }

    /// Maths: what the paper practises, before the first question.
    /// One strategy → "The move": how to spot it, the recipe, the booklet formula and the trap.
    /// A handful → "Your toolbox": the moves in play, without saying which question needs which (that's the skill).
    static func drawStrategyCard(session: StudySession, syllabus: Syllabus, top: CGFloat) -> CGFloat {
        let moves = session.scope.compactMap { syllabus.subtopic($0) }
        guard !moves.isEmpty, moves.count <= 12 else { return top }
        let x = side + 14, w = contentWidth - 28
        var lines: [(String, CGFloat, NSFont.Weight, NSColor, CGFloat)] = []   // text, size, weight, colour, gap after
        let grey = NSColor(white: 0.25, alpha: 1)
        if moves.count == 1, let m = moves.first {
            lines.append(("THE MOVE", 8, .bold, purple, 2))
            lines.append((m.name, 14, .bold, .black, 8))
            if let cues = m.cues, !cues.isEmpty {
                lines.append(("Spot it when you see", 8.5, .bold, purple, 2))
                lines.append((cues.map { "“\($0)”" }.joined(separator: "  ·  "), 9.5, .regular, grey, 7))
            }
            if let steps = m.steps, !steps.isEmpty {
                lines.append(("The recipe", 8.5, .bold, purple, 2))
                for (i, step) in steps.enumerated() { lines.append(("\(i + 1).  \(step)", 9.5, .regular, grey, 2)) }
                lines[lines.count - 1].4 = 7
            }
            if let f = m.formula { lines.append(("Formula booklet:  " + f, 9, .medium, grey, 3)) }
            if let t = m.trap { lines.append(("Watch out:  " + t, 9, .medium, NSColor(calibratedRed: 0.75, green: 0.35, blue: 0.1, alpha: 1), 3)) }
        } else {
            lines.append(("YOUR TOOLBOX FOR THIS PAPER", 8, .bold, purple, 3))
            lines.append(("Before each question, jot down which move it needs. Your results show the right one.", 9.5, .regular, grey, 6))
            for m in moves.sorted(by: { $0.id < $1.id }) { lines.append(("•  " + m.name, 9.5, .medium, grey, 1.5)) }
        }
        let height = lines.reduce(CGFloat(24)) { $0 + drawWrapped($1.0, x: x, top: 0, width: w, size: $1.1, weight: $1.2, draw: false) + $1.4 }
        let ctx = NSGraphicsContext.current!.cgContext
        let card = rectFromTop(x: side, top: top, width: contentWidth, height: height)
        ctx.setFillColor(lilac.cgColor)
        ctx.addPath(CGPath(roundedRect: card, cornerWidth: 10, cornerHeight: 10, transform: nil)); ctx.fillPath()
        ctx.setFillColor(purple.cgColor)
        ctx.fill(CGRect(x: card.minX, y: card.minY + 10, width: 3, height: card.height - 20))
        var y = top + 12
        for (text, size, weight, color, gap) in lines {
            y += drawWrapped(text, x: x, top: y, width: w, size: size, weight: weight, color: color) + gap
        }
        return top + height + 16
    }

    /// `top` is measured from the top of the page.
    static func rectFromTop(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x, y: page.height - top - height, width: width, height: height)
    }

    static func drawTitleBlock(session: StudySession, questions: [Question], maths: Bool = false) -> CGFloat {
        let ctx = NSGraphicsContext.current!.cgContext
        let band = rectFromTop(x: 0, top: 0, width: page.width, height: 118)
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor(calibratedRed: 0.36, green: 0.16, blue: 0.70, alpha: 1).cgColor,
                                       NSColor(calibratedRed: 0.62, green: 0.36, blue: 0.93, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1])!
        ctx.saveGState(); ctx.clip(to: band)
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: band.midY), end: CGPoint(x: page.width, y: band.midY), options: [])
        ctx.restoreGState()
        drawText("BIOSPHERE  ·  \(session.id)", rect: rectFromTop(x: side, top: 18, width: 400, height: 14),
                 size: 9, weight: .semibold, color: NSColor(white: 1, alpha: 0.75))
        drawText(session.title, rect: rectFromTop(x: side, top: 34, width: contentWidth, height: 28),
                 size: 21, weight: .bold, color: .white)
        drawText(session.subtitle, rect: rectFromTop(x: side, top: 62, width: contentWidth, height: 16),
                 size: 11, color: NSColor(white: 1, alpha: 0.9))
        let mcq = questions.filter(\.isMCQ).count
        let info = "\(questions.count) questions\(mcq > 0 ? " (\(mcq) multiple choice)" : "")  ·  \(session.totalMarks) marks  ·  suggested time \(session.minutes) min"
        drawText(info, rect: rectFromTop(x: side, top: 84, width: contentWidth, height: 16),
                 size: 10.5, weight: .medium, color: .white)
        drawText(maths ? "Show your working under each question: most marks are for method. Unsure? Add a * beside it and Hank will flag it. Then send this PDF back to your Mac for marking."
                       : "Write in the answer spaces and circle multiple-choice letters (or write them in the box). Unsure? Add a * or star beside the question or answer so Hank can flag it for review. When you're done, send this PDF back to your Mac for marking.",
                 rect: rectFromTop(x: side, top: 126, width: contentWidth, height: 40), size: 9, color: NSColor(white: 0.35, alpha: 1))
        return 174
    }

    /// `hideStrategy`: Maths never prints which strategy a question needs; spotting it is the point.
    static func drawHeader(number: Int, question q: Question, syllabus: Syllabus, top: CGFloat, hideStrategy: Bool = false) {
        let ctx = NSGraphicsContext.current!.cgContext
        let r = rectFromTop(x: side, top: top, width: contentWidth, height: 24)
        ctx.setFillColor(lilac.cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
        let pill = CGRect(x: r.minX, y: r.minY, width: 92, height: r.height)
        ctx.setFillColor(purple.cgColor)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
        drawText("Question \(number)", rect: pill.insetBy(dx: 8, dy: 5).offsetBy(dx: 0, dy: -1), size: 10.5, weight: .bold, color: .white, align: .center)
        let sub = syllabus.subtopic(q.primary).map { "\($0.id) \($0.name)" } ?? q.primary
        let marks = q.marks == 1 ? "1 mark" : "\(q.marks) marks"
        let rightW: CGFloat = q.isMCQ ? 150 : 70
        var left = hideStrategy ? q.sourceLabel : "\(sub)  ·  \(q.sourceLabel)"
        if let focus = q.focus, focus.count < q.parts.count {
            left += "  ·  your move: " + focus.joined(separator: ", ") + " (earlier parts lead in)"
        }
        drawText(left, rect: CGRect(x: pill.maxX + 10, y: r.minY + 5, width: r.width - pill.width - rightW - 16, height: 14),
                 size: 8.5, color: NSColor(white: 0.3, alpha: 1))
        if q.isMCQ {
            drawText("Answer:", rect: CGRect(x: r.maxX - 148, y: r.minY + 5, width: 50, height: 14), size: 9, weight: .semibold, color: purple)
            let ansBox = CGRect(x: r.maxX - 98, y: r.minY + 3, width: 30, height: 18)
            ctx.setFillColor(NSColor.white.cgColor); ctx.fill(ansBox)
            ctx.setStrokeColor(purple.cgColor); ctx.setLineWidth(1); ctx.stroke(ansBox)
            drawText(marks, rect: CGRect(x: r.maxX - 62, y: r.minY + 5, width: 56, height: 14), size: 9, weight: .semibold, color: purple, align: .right)
        } else {
            drawText(marks, rect: CGRect(x: r.maxX - rightW, y: r.minY + 5, width: rightW - 8, height: 14), size: 9, weight: .semibold, color: purple, align: .right)
        }
    }

    static func drawLabel(_ s: String, at top: CGFloat) {
        drawText(s, rect: rectFromTop(x: side + 8, top: top, width: 200, height: 14), size: 9, weight: .semibold, color: purple)
    }

    static func drawFooter(ctx: CGContext, session: StudySession, pageNumber: Int) {
        ctx.setStrokeColor(NSColor(calibratedWhite: 0.85, alpha: 1).cgColor); ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: side, y: 30)); ctx.addLine(to: CGPoint(x: page.width - side, y: 30)); ctx.strokePath()
        drawText("Biosphere · \(session.id) · \(session.title)", rect: CGRect(x: side, y: 14, width: 380, height: 12),
                 size: 7.5, color: NSColor(white: 0.5, alpha: 1))
        drawText("page \(pageNumber)", rect: CGRect(x: page.width - side - 100, y: 14, width: 100, height: 12),
                 size: 7.5, color: NSColor(white: 0.5, alpha: 1), align: .right)
    }
}
