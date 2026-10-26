import XCTest
import SwiftUI
@testable import Biosphere

final class MathTextTests: XCTestCase {
    func testSplitsProseFromInlineAndDisplayMathButLeavesDollarsAlone() {
        XCTAssertEqual(MathParser.split("Costs US$14 000, so $5 more."), [.prose("Costs US$14 000, so $5 more.")])
        XCTAssertEqual(MathParser.split(#"PES is \(\frac{a}{b}\) here"#),
                       [.prose("PES is "), .math(#"\frac{a}{b}"#, display: false), .prose(" here")])
        XCTAssertEqual(MathParser.split(#"Work: \[x = 2\] done"#),
                       [.prose("Work: "), .math("x = 2", display: true), .prose(" done")])
        XCTAssertEqual(MathParser.split(#"Unclosed \(x"#), [.prose(#"Unclosed \(x"#)])
    }

    func testParsesTheFormulasMarkingNeeds() {
        let pes = MathParser.parse(#"\text{PES} = \dfrac{\%\Delta Q_s}{\%\Delta P} = \dfrac{29.73}{4.94} = 6.02"#)
        guard case .row(let items) = pes else { return XCTFail("\(pes)") }
        XCTAssertEqual(items.first, .text("PES"))
        XCTAssertTrue(items.contains(.frac(.row([.symbol("29.73", italic: false)]).flattened, .row([.symbol("4.94", italic: false)]).flattened)))
        XCTAssertTrue(items.contains(.symbol("6.02", italic: false)))
        guard case .frac(let top, _) = items[2], case .row(let num) = top else { return XCTFail("\(items)") }
        XCTAssertEqual(num, [.symbol("%", italic: false), .symbol("Δ", italic: false), .script(.symbol("Q", italic: true), sup: nil, sub: .symbol("s", italic: true))])
        XCTAssertEqual(MathParser.parse("x^2_1"), .script(.symbol("x", italic: true), sup: .symbol("2", italic: false), sub: .symbol("1", italic: false)))
        XCTAssertEqual(MathParser.parse(#"\sqrt{16}"#), .sqrt(.symbol("16", italic: false)))
        XCTAssertEqual(MathParser.parse(#"a \times b"#), .row([.symbol("a", italic: true), .symbol("×", italic: false), .symbol("b", italic: true)]))
        XCTAssertEqual(MathParser.parse(#"\unknown"#), .symbol("unknown", italic: false), "unknown commands show as written")
    }

    @MainActor
    func testFormulaRendersToAnImage() {
        let renderer = ImageRenderer(content: MathView(node: MathParser.parse(#"\frac{1100}{3700} \times 100"#), size: 13, color: .black).fixedSize())
        let image = renderer.nsImage
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.height ?? 0, 20, "a stacked fraction is taller than one line")
    }

    func testHandwritingCropsJoinHerLinesPerPage() {
        let reading = BusinessReading(lines: [.init(id: "L1", part: "a", text: "x"), .init(id: "L2", part: "a", text: "y"),
                                              .init(id: "L3", part: "b", text: "z"), .init(id: "L4", part: "a", text: "w")],
                                      starredParts: [], drawingParts: [], unclearParts: [], note: "",
                                      anchors: ["L1": .init(page: 6, x: 0.1, y: 0.20, width: 0.5, height: 0.02),
                                                "L2": .init(page: 6, x: 0.1, y: 0.23, width: 0.6, height: 0.02),
                                                "L3": .init(page: 6, x: 0.1, y: 0.50, width: 0.6, height: 0.02),
                                                "L4": .init(page: 7, x: 0.1, y: 0.10, width: 0.6, height: 0.02)])
        let crops = reading.handwritingCrops(for: "a")
        XCTAssertTrue(BusinessReading.same("(a)(i)", "a(i)") && BusinessReading.same("a (i)", "A(i)") && !BusinessReading.same("a(i)", "a(ii)"))
        XCTAssertEqual(crops.map(\.page), [5, 6], "0-based pages, one crop per page")
        XCTAssertEqual(crops[0].rect.minY, 0.188, accuracy: 0.0001)
        XCTAssertEqual(crops[0].rect.maxY, 0.262, accuracy: 0.0001)
        XCTAssertTrue(BusinessReading(lines: [], starredParts: [], drawingParts: [], unclearParts: [], note: "").handwritingCrops(for: "a").isEmpty)
        // A drawing runs on down to the next answer (part b's line at y 0.50), not just its labelled lines.
        var drawn = reading; drawn.drawingParts = ["(a)"]
        XCTAssertEqual(drawn.handwritingCrops(for: "a")[0].rect.maxY, 0.496, accuracy: 0.0001)
    }
}

private extension MathNode {
    /// A one-item row parses as the item itself.
    var flattened: MathNode { if case .row(let items) = self, items.count == 1 { return items[0] }; return self }
}
