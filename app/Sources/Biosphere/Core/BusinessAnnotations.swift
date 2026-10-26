import AppKit
import PDFKit

struct PaperComment: Identifiable, Hashable {
    var id: String
    var number: Int
    var part: String
    var sentence: EssaySentence
    var isStrength: Bool { sentence.judgement.map { $0 == "strength" } ?? (sentence.label != "none") }
    var title: String { isStrength ? "What worked" : "How to improve" }
    var color: NSColor { isStrength ? .systemGreen : .systemOrange }
}

enum BusinessAnnotations {
    /// PDFKit strips /NM on write. The visible comment number survives in standard /Contents.
    static func commentNumber(_ annotation: PDFAnnotation) -> Int? {
        guard annotation.userName == "Hank", ["Highlight", "Text"].contains(annotation.type ?? ""),
              let first = annotation.contents?.split(separator: ".", maxSplits: 1).first else { return nil }
        return Int(first)
    }
    static func comments(_ result: BusinessResult) -> [PaperComment] {
        var out: [PaperComment] = []
        for essay in result.essays {
            for (index, sentence) in essay.sentences.enumerated() {
                out.append(.init(id: "hank-\(essay.label)-\(index)", number: out.count + 1, part: essay.label, sentence: sentence))
            }
        }
        return out
    }

    static func rect(_ anchor: EssayAnchor, bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + anchor.x * bounds.width,
               y: bounds.maxY - (anchor.y + anchor.height) * bounds.height,
               width: anchor.width * bounds.width, height: anchor.height * bounds.height)
    }

    /// Creates an annotated copy. completed.pdf stays the student's untouched submission.
    @discardableResult
    static func write(result: BusinessResult, source: URL, to destination: URL) throws -> Int {
        guard let document = PDFDocument(url: source) else { throw ClaudeCLI.CLIError.failed("Couldn't open your submitted paper.") }
        var count = 0
        for comment in comments(result) {
            let anchors = (comment.sentence.anchors ?? []).filter { $0.isValid && $0.page <= document.pageCount }
            for anchor in anchors {
                guard let page = document.page(at: anchor.page - 1) else { continue }
                let bounds = page.bounds(for: .cropBox)
                let rect = rect(anchor, bounds: bounds)
                let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                annotation.quadrilateralPoints = [
                    NSValue(point: CGPoint(x: 0, y: rect.height)), NSValue(point: CGPoint(x: rect.width, y: rect.height)),
                    NSValue(point: .zero), NSValue(point: CGPoint(x: rect.width, y: 0))]
                annotation.color = comment.color.withAlphaComponent(0.28)
                annotation.userName = "Hank"
                annotation.contents = "\(comment.number). \(comment.title) · \(comment.part)\n\(comment.sentence.text)\n\(comment.sentence.note)"
                page.addAnnotation(annotation)
                count += 1
            }
            // A conventional PDF sticky note, also clickable in the app and other PDF readers.
            if let first = anchors.first, let page = document.page(at: first.page - 1) {
                let bounds = page.bounds(for: .cropBox)
                let target = rect(first, bounds: bounds)
                let noteRect = CGRect(x: min(bounds.maxX - 20, max(bounds.minX + 2, target.maxX + 3)),
                                      y: min(bounds.maxY - 18, max(bounds.minY, target.maxY - 18)), width: 18, height: 18)
                let note = PDFAnnotation(bounds: noteRect, forType: .text, withProperties: nil)
                note.iconType = .comment
                note.color = comment.color
                note.userName = "Hank"
                note.contents = "\(comment.number). \(comment.title) · \(comment.part)\n\(comment.sentence.text)\n\(comment.sentence.note)"
                page.addAnnotation(note)
            }
        }
        guard document.write(to: destination) else { throw ClaudeCLI.CLIError.failed("Couldn't save the marked paper.") }
        return count
    }

    struct LocatedSentence: Codable { var part: String; var index: Int; var judgement: String; var note: String; var anchors: [EssayAnchor] }
    struct Locations: Codable { var sentences: [LocatedSentence] }

    static func apply(_ locations: Locations, to result: BusinessResult, answerPages: [Int]) throws -> BusinessResult {
        var copy = result
        var seen: Set<String> = []
        for location in locations.sentences {
            guard let essay = copy.essays.firstIndex(where: { $0.label == location.part }),
                  copy.essays[essay].sentences.indices.contains(location.index),
                  seen.insert("\(location.part):\(location.index)").inserted,
                  ["strength", "improve"].contains(location.judgement),
                  location.anchors.allSatisfy({ $0.isValid && answerPages.contains($0.page) }) else {
                throw ClaudeCLI.CLIError.failed("Hank couldn't match the comments to your paper. Your previous marks are saved.")
            }
            copy.essays[essay].sentences[location.index].anchors = location.anchors
            copy.essays[essay].sentences[location.index].judgement = location.judgement
            copy.essays[essay].sentences[location.index].note = location.note
        }
        guard seen.count == result.essays.reduce(0, { $0 + $1.sentences.count }) else {
            throw ClaudeCLI.CLIError.failed("Hank didn't finish placing every comment. Your previous marks are saved.")
        }
        return copy
    }

    /// Sentence → reader line ids, for placing older feedback on her paper.
    struct Match: Codable { var part: String; var index: Int; var lines: [String] }
    struct Matches: Codable { var sentences: [Match] }

    static let matchSchema = """
    {"type":"object","required":["sentences"],"properties":{"sentences":{"type":"array","items":{"type":"object","required":["part","index","lines"],"properties":{"part":{"type":"string"},"index":{"type":"integer","minimum":0},"lines":{"type":"array","items":{"type":"string"}}}}}}}
    """
}
