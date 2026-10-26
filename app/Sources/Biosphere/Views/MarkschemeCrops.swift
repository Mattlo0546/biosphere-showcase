import SwiftUI

/// One page crop: a 0-based page of a PDF and a rectangle in fractions of that page, measured from the top.
struct PageCrop: Hashable {
    var page: Int
    var rect: CGRect
}

/// Crops of a PDF shown as one picture with a title, click to open the page full size. Used for the official
/// markscheme (Economics) and for her own handwriting beside it.
struct PaperCrops: View {
    var heading: String
    var tint: Color
    var background: Color
    var url: URL
    var crops: [PageCrop]
    var zoomTitle: String
    @State private var zoom: ZoomTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(heading).font(.system(size: 10.5, weight: .bold)).foregroundStyle(tint).textCase(.uppercase)
                Spacer()
                Image(systemName: "plus.magnifyingglass").font(.system(size: 10.5)).foregroundStyle(Palette.faint)
            }
            VStack(spacing: 0) {
                ForEach(Array(crops.enumerated()), id: \.offset) { _, c in
                    PDFCropImage(url: url, page: c.page, rectFromTop: c.rect)
                        .contentShape(Rectangle())
                        .onTapGesture { zoom = ZoomTarget(url: url, page: c.page, title: zoomTitle) }
                }
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.stroke))
            .help("Click to open the page full size")
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(background, in: RoundedRectangle(cornerRadius: 10))
        .sheet(item: $zoom) { ZoomSheet(target: $0) }
    }
}

/// The official markscheme for one part, cropped from the IB's own pages (Economics), so she can check
/// Hank's "what scores" against the real thing.
struct MarkschemeCrops: View {
    var url: URL
    var regions: [Region]
    var title: String

    var body: some View {
        PaperCrops(heading: "Official markscheme", tint: Palette.purple, background: Palette.cardHi, url: url,
                   crops: regions.map { PageCrop(page: $0.page, rect: CGRect(x: $0.x0, y: $0.y0, width: $0.x1 - $0.x0, height: $0.y1 - $0.y0)) },
                   zoomTitle: title)
    }
}

extension BusinessReading {
    /// Where she wrote one part on her returned paper: the reader's line rectangles (exact, from her ink) joined
    /// per page and widened to the writing area. Empty when the ink couldn't be separated (then the
    /// transcription is all there is).
    func handwritingCrops(for part: String) -> [PageCrop] {
        guard let anchors else { return [] }
        let rects = lines(for: part).compactMap { anchors[$0.id] }.filter(\.isValid)
        let others = lines.filter { !Self.same($0.part, part) }.compactMap { anchors[$0.id] }
        // A drawing is more than its labelled lines (axes, curves): run on down to where the next answer starts.
        let drawing = drawingParts.contains { Self.same($0, part) }
        let pages = Array(Set(rects.map(\.page))).sorted()
        return pages.map { page in
            let mine = rects.filter { $0.page == page }
            let top = max(0, (mine.map(\.y).min() ?? 0) - 0.012)
            let last = mine.map { $0.y + $0.height }.max() ?? 1
            var bottom = last + 0.012
            if drawing {
                let next = others.filter { $0.page == page && $0.y > last }.map(\.y).min()
                bottom = min(next.map { $0 - 0.004 } ?? last + 0.2, last + 0.25)
            }
            bottom = min(1, bottom)
            return PageCrop(page: page - 1, rect: CGRect(x: 0.04, y: top, width: 0.92, height: bottom - top))
        }
    }
}
