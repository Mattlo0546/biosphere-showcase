import SwiftUI

/// Text with LaTeX maths in it, typeset natively (no web view, no third-party code). Hank writes formulas as
/// `\( … \)` (inline) or `\[ … \]` (on their own line); `$` is left alone because it means dollars in answers.
/// Prose stays ordinary wrapping `Text`; each formula is laid out by `MathView`, rendered to an image and
/// placed inline, so it wraps with the sentence. Covers what marking needs: fractions, sub/superscripts,
/// roots, Greek letters, arrows, operators and `\text{}`. Anything it doesn't know shows as written.
struct MathText: View {
    var source: String
    var size: CGFloat = 12.5
    var weight: Font.Weight = .regular
    var color: Color = Palette.text
    @Environment(\.displayScale) private var scale

    init(_ source: String, size: CGFloat = 12.5, weight: Font.Weight = .regular, color: Color = Palette.text) {
        self.source = source; self.size = size; self.weight = weight; self.color = color
    }

    var body: some View {
        let pieces = MathParser.split(source)
        if pieces.allSatisfy({ if case .prose = $0 { true } else { false } }) {
            Text(source).font(.system(size: size, weight: weight)).foregroundStyle(color)
        } else {
            pieces.reduce(Text("")) { text, piece in
                switch piece {
                case .prose(let s): return text + Text(s).font(.system(size: size, weight: weight)).foregroundStyle(color)
                case .math(let latex, let display):
                    guard let image = render(latex) else { return text + Text(latex).font(.system(size: size, design: .monospaced)) }
                    let picture = Text(Image(nsImage: image.0)).baselineOffset(-image.1)
                    return display ? text + Text("\n") + picture + Text("\n") : text + picture
                }
            }
        }
    }

    /// The formula as an image, plus how far it reaches below the text baseline (so it sits on the line).
    @MainActor private func render(_ latex: String) -> (NSImage, CGFloat)? {
        let node = MathParser.parse(latex)
        let renderer = ImageRenderer(content: MathView(node: node, size: size, color: color).fixedSize())
        renderer.scale = max(scale, 2)
        guard let image = renderer.nsImage else { return nil }
        let depth = max(0, (image.size.height - size * 1.2) / 2)
        return (image, depth)
    }
}

/// A parsed formula.
indirect enum MathNode: Equatable {
    case row([MathNode])
    case symbol(String, italic: Bool)
    case text(String)
    case frac(MathNode, MathNode)
    case script(MathNode, sup: MathNode?, sub: MathNode?)
    case sqrt(MathNode)
}

enum MathParser {
    enum Piece: Equatable { case prose(String), math(String, display: Bool) }

    /// Splits prose from `\( … \)` and `\[ … \]`. An unclosed opener stays prose.
    static func split(_ s: String) -> [Piece] {
        var out: [Piece] = []
        var rest = Substring(s)
        while true {
            let inline = rest.range(of: #"\("#), display = rest.range(of: #"\["#)
            guard let start = [inline, display].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else { break }
            let isDisplay = start == display
            guard let close = rest.range(of: isDisplay ? #"\]"# : #"\)"#, range: start.upperBound..<rest.endIndex) else { break }
            if start.lowerBound > rest.startIndex { out.append(.prose(String(rest[..<start.lowerBound]))) }
            out.append(.math(String(rest[start.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces), display: isDisplay))
            rest = rest[close.upperBound...]
        }
        if !rest.isEmpty { out.append(.prose(String(rest))) }
        return out
    }

    static let symbols: [String: String] = [
        "times": "×", "div": "÷", "cdot": "·", "pm": "±", "mp": "∓", "approx": "≈", "neq": "≠", "ne": "≠",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "rightarrow": "→", "to": "→", "leftarrow": "←",
        "Rightarrow": "⇒", "implies": "⇒", "uparrow": "↑", "downarrow": "↓", "infty": "∞", "sum": "Σ",
        "Delta": "Δ", "delta": "δ", "alpha": "α", "beta": "β", "gamma": "γ", "lambda": "λ", "mu": "μ",
        "pi": "π", "sigma": "σ", "Sigma": "Σ", "theta": "θ", "epsilon": "ε", "varepsilon": "ε", "rho": "ρ",
        "%": "%", "$": "$", "&": "&", "#": "#", "_": "_", "{": "{", "}": "}", "ldots": "…", "dots": "…",
        "cdots": "⋯", "degree": "°", "circ": "°", "prime": "′", "lt": "<", "gt": ">",
        ",": "\u{2009}", ";": "\u{2005}", ":": "\u{2005}", " ": " ", "quad": "\u{2003}", "qquad": "\u{2003}\u{2003}",
    ]

    /// Parses a LaTeX formula into nodes. Never fails: unknown commands become their own name.
    static func parse(_ latex: String) -> MathNode {
        var chars = Array(latex)
        var i = 0
        func group() -> MathNode {
            // One argument: {…} or a single token.
            while i < chars.count, chars[i] == " " { i += 1 }
            guard i < chars.count else { return .row([]) }
            if chars[i] == "{" {
                i += 1
                let inner = row(until: "}")
                i += 1
                return inner
            }
            return atom() ?? .row([])
        }
        func rawGroup() -> String {
            while i < chars.count, chars[i] == " " { i += 1 }
            guard i < chars.count, chars[i] == "{" else { return "" }
            var depth = 0, out = ""
            while i < chars.count {
                let c = chars[i]; i += 1
                if c == "{" { depth += 1; if depth == 1 { continue } }
                if c == "}" { depth -= 1; if depth == 0 { break } }
                out.append(c)
            }
            return out
        }
        func atom() -> MathNode? {
            guard i < chars.count else { return nil }
            let c = chars[i]
            if c == "\\" {
                i += 1
                guard i < chars.count else { return .symbol("\\", italic: false) }
                var name = ""
                if chars[i].isLetter {
                    while i < chars.count, chars[i].isLetter { name.append(chars[i]); i += 1 }
                } else { name = String(chars[i]); i += 1 }
                switch name {
                case "frac", "dfrac", "tfrac": let a = group(); let b = group(); return .frac(a, b)
                case "sqrt": return .sqrt(group())
                case "text", "mathrm", "textrm", "textbf", "mathbf", "operatorname": return .text(rawGroup())
                case "left", "right", "big", "Big", "displaystyle": return .row([])
                default: return .symbol(symbols[name] ?? name, italic: false)
                }
            }
            i += 1
            if c == "{" { let inner = row(until: "}"); i += 1; return inner }
            if c == " " { return .row([]) }
            if c == "*" { return .symbol("×", italic: false) }
            if c == "-" { return .symbol("−", italic: false) }
            if "+=<>()[],.:;/!|".contains(c) || c.isNumber { return .symbol(String(c), italic: false) }
            return .symbol(String(c), italic: c.isLetter)
        }
        func row(until end: Character?) -> MathNode {
            var items: [MathNode] = []
            while i < chars.count, chars[i] != end {
                if chars[i] == "^" || chars[i] == "_" {
                    let isSup = chars[i] == "^"; i += 1
                    let arg = group()
                    let base = items.popLast() ?? .row([])
                    if case .script(let b, let sup, let sub) = base {
                        items.append(.script(b, sup: isSup ? arg : sup, sub: isSup ? sub : arg))
                    } else {
                        items.append(.script(base, sup: isSup ? arg : nil, sub: isSup ? nil : arg))
                    }
                    continue
                }
                if let a = atom() { items.append(a) }
            }
            // Digits typed one by one read better as one number ("29.73").
            var merged: [MathNode] = []
            for item in items {
                if case .symbol(let s, false) = item, s.allSatisfy({ $0.isNumber || $0 == "." }),
                   case .symbol(let prev, false)? = merged.last, prev.allSatisfy({ $0.isNumber || $0 == "." }) {
                    merged[merged.count - 1] = .symbol(prev + s, italic: false)
                } else if case .row(let inner) = item, inner.isEmpty {
                    continue
                } else { merged.append(item) }
            }
            return merged.count == 1 ? merged[0] : .row(merged)
        }
        return row(until: nil)
    }
}

/// Lays out a `MathNode` with SwiftUI stacks (system font, so it matches the text around it).
struct MathView: View {
    var node: MathNode
    var size: CGFloat
    var color: Color

    var body: some View {
        switch node {
        case .row(let items):
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in MathView(node: item, size: size, color: color) }
            }
        case .symbol(let s, let italic):
            let spaced = "=+−×÷±≈≠≤≥→←⇒<>".contains(s) ? " \(s) " : s
            Text(spaced).font(.system(size: size, design: italic ? .serif : .default)).italic(italic).foregroundStyle(color)
        case .text(let s):
            Text(s).font(.system(size: size)).foregroundStyle(color)
        case .frac(let a, let b):
            VStack(spacing: 1) {
                MathView(node: a, size: size * 0.85, color: color)
                Rectangle().fill(color).frame(height: max(0.8, size / 16))
                MathView(node: b, size: size * 0.85, color: color)
            }
            .fixedSize()
            .padding(.horizontal, 2)
        case .script(let base, let sup, let sub):
            HStack(alignment: .center, spacing: 1) {
                MathView(node: base, size: size, color: color)
                VStack(alignment: .leading, spacing: 0) {
                    if let sup { MathView(node: sup, size: size * 0.68, color: color) } else { Color.clear.frame(width: 1, height: size * 0.4) }
                    if let sub { MathView(node: sub, size: size * 0.68, color: color) } else { Color.clear.frame(width: 1, height: size * 0.4) }
                }
            }
        case .sqrt(let inner):
            HStack(alignment: .center, spacing: 1) {
                Text("√").font(.system(size: size * 1.1)).foregroundStyle(color)
                MathView(node: inner, size: size, color: color)
                    .padding(.top, 2)
                    .overlay(alignment: .top) { Rectangle().fill(color).frame(height: max(0.8, size / 16)) }
            }
        }
    }
}
