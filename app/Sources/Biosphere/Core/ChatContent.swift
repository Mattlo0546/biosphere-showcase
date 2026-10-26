import Foundation

/// Separates ordinary Markdown from fenced drawings without reformatting SVG while it streams.
enum ChatBlock: Equatable {
    case paragraph(String), bullet(String, String), heading(String), callout(String)
    case diagram(SVGDiagram), pendingDiagram, unavailableDiagram, code(String)

    static func parse(_ text: String, isStreaming: Bool = false) -> [ChatBlock] {
        var blocks: [ChatBlock] = []
        var paragraph: [String] = []
        var fence: String?
        var language = ""
        var code: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if line.hasPrefix(marker), line.dropFirst(marker.count).allSatisfy({ $0 == marker.first! }) {
                    let source = code.joined(separator: "\n")
                    if language == "svg" {
                        blocks.append(SVGDiagram(source).map(ChatBlock.diagram) ?? .unavailableDiagram)
                    } else { blocks.append(.code(source)) }
                    fence = nil; code = []
                } else { code.append(raw) }
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flush()
                let character = line.first!
                let count = line.prefix(while: { $0 == character }).count
                fence = String(repeating: String(character), count: count)
                language = line.dropFirst(count).trimmingCharacters(in: .whitespaces).lowercased()
                continue
            }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush(); blocks.append(.heading(line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))); continue
            }
            if line.hasPrefix(">") {
                flush()
                let body = String(line.drop(while: { $0 == ">" || $0 == " " }))
                if case .callout(let previous)? = blocks.last { blocks[blocks.count - 1] = .callout(previous + "\n" + body) }
                else { blocks.append(.callout(body)) }
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush(); blocks.append(.bullet("•", String(line.dropFirst(2)))); continue
            }
            if let range = line.range(of: "^\\d+[.)] ", options: .regularExpression) {
                flush(); blocks.append(.bullet(String(line[range]).trimmingCharacters(in: .whitespaces), String(line[range.upperBound...]))); continue
            }
            paragraph.append(line)
        }
        flush()
        if fence != nil { blocks.append(language == "svg" ? (isStreaming ? .pendingDiagram : .unavailableDiagram) : .code(code.joined(separator: "\n"))) }
        return blocks
    }
}

/// A self-contained, static SVG. Only drawing elements and presentation attributes enter the web view.
struct SVGDiagram: Equatable {
    let markup: String
    let aspectRatio: Double
    let title: String

    init?(_ source: String) {
        guard source.utf8.count <= 200_000,
              source.range(of: "<!DOCTYPE|<!ENTITY", options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        let validator = SVGValidator()
        let parser = XMLParser(data: Data(source.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = validator
        guard parser.parse(), validator.valid, let aspectRatio = validator.aspectRatio else { return nil }
        self.markup = validator.output
        self.aspectRatio = aspectRatio
        let title = validator.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.isEmpty ? "Biology diagram" : String(title.prefix(120))
    }

    var html: String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src 'none'; connect-src 'none'; font-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:white;color:#1e1433}
        body>svg{display:block;width:100%;height:100%;font-family:-apple-system,BlinkMacSystemFont,sans-serif}</style>
        </head><body>\(markup)</body></html>
        """
    }
}

private final class SVGValidator: NSObject, XMLParserDelegate {
    var valid = true
    var output = ""
    var title = ""
    var aspectRatio: Double?
    private var elements: [String] = []
    private var count = 0

    private let allowedElements: Set<String> = [
        "svg", "g", "defs", "path", "line", "polyline", "polygon", "rect", "circle", "ellipse",
        "text", "tspan", "title", "desc", "marker", "linearGradient", "radialGradient", "stop", "clipPath"
    ]
    private let allowedAttributes: Set<String> = [
        "xmlns", "viewBox", "width", "height", "preserveAspectRatio", "id", "role", "aria-label", "aria-labelledby",
        "x", "y", "x1", "y1", "x2", "y2", "dx", "dy", "cx", "cy", "r", "rx", "ry", "d", "points", "transform",
        "fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-opacity", "stroke-linecap", "stroke-linejoin",
        "stroke-dasharray", "stroke-dashoffset", "opacity", "font-family", "font-size", "font-weight", "font-style",
        "text-anchor", "dominant-baseline", "alignment-baseline", "letter-spacing", "textLength", "lengthAdjust",
        "marker-start", "marker-mid", "marker-end", "markerWidth", "markerHeight", "markerUnits", "refX", "refY", "orient",
        "gradientUnits", "gradientTransform", "spreadMethod", "offset", "stop-color", "stop-opacity", "fx", "fy",
        "clip-path", "clipPathUnits", "vector-effect"
    ]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        count += 1
        guard allowedElements.contains(elementName), count <= 2_000, elements.count < 32,
              (!elements.isEmpty || elementName == "svg"), !(elementName == "svg" && !elements.isEmpty) else { reject(parser); return }
        if elements.isEmpty {
            let values = (attributes["viewBox"] ?? "").split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap { Double($0) }
            guard values.count == 4, values.allSatisfy(\.isFinite), values[2] > 0, values[3] > 0,
                  values[2] <= 10_000, values[3] <= 10_000, (0.25...4).contains(values[2] / values[3]) else { reject(parser); return }
            aspectRatio = values[2] / values[3]
        }
        var safeAttributes: [String: String] = [:]
        for (key, value) in attributes {
            guard allowedAttributes.contains(key), value.count <= 40_000,
                  key != "xmlns" || value == "http://www.w3.org/2000/svg" else { reject(parser); return }
            // Paint servers and clipping may reference internal ids only; no resource URLs or CSS escapes.
            if value.contains("\\") || value.range(of: "(?:https?:|file:|data:|javascript:|//)", options: [.regularExpression, .caseInsensitive]) != nil {
                if key != "xmlns" { reject(parser); return }
            }
            if value.range(of: "url", options: .caseInsensitive) != nil {
                guard value.range(of: "^url\\(#[A-Za-z_][A-Za-z0-9_.-]*\\)$", options: [.regularExpression, .caseInsensitive]) != nil else { reject(parser); return }
            }
            // The host owns the outer dimensions so drawings scale with the chat panel.
            if elements.isEmpty && ["width", "height", "preserveAspectRatio"].contains(key) { continue }
            safeAttributes[key] = value
        }
        if elements.isEmpty {
            safeAttributes["xmlns"] = "http://www.w3.org/2000/svg"
            safeAttributes["preserveAspectRatio"] = "xMidYMid meet"
        }
        elements.append(elementName)
        output += "<" + elementName
        for key in safeAttributes.keys.sorted() { output += " \(key)=\"\(escape(safeAttributes[key]!))\"" }
        output += ">"
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if elements.last == "title" { title += string }
        output += escape(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        guard elements.last == elementName else { reject(parser); return }
        elements.removeLast()
        output += "</\(elementName)>"
    }

    private func reject(_ parser: XMLParser) { valid = false; parser.abortParsing() }
    private func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
