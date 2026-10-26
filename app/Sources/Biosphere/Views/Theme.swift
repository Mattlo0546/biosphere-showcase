import SwiftUI
import PDFKit

enum Palette {
    // Mostly white, with purple as the accent.
    static let bg = Color.white
    static let bg2 = Color(red: 0.973, green: 0.961, blue: 0.996)       // faint lavender wash (sidebar, panes)
    static let card = Color.white
    static let cardHi = Color(red: 0.953, green: 0.933, blue: 0.996)
    static let stroke = Color(red: 0.898, green: 0.871, blue: 0.957)
    static let purple = Color(red: 0.486, green: 0.227, blue: 0.929)     // #7C3AED
    static let violet = Color(red: 0.545, green: 0.361, blue: 0.965)     // #8B5CF6
    static let lilac = Color(red: 0.427, green: 0.157, blue: 0.851)      // accent text
    static let text = Color(red: 0.118, green: 0.078, blue: 0.200)
    static let dim = Color(red: 0.369, green: 0.329, blue: 0.459)
    static let faint = Color(red: 0.604, green: 0.565, blue: 0.686)

    static let red = Color(red: 0.902, green: 0.255, blue: 0.318)
    static let orange = Color(red: 0.961, green: 0.588, blue: 0.161)
    static let green = Color(red: 0.133, green: 0.725, blue: 0.420)
    static let empty = Color(red: 0.925, green: 0.906, blue: 0.961)

    static let gradient = LinearGradient(colors: [Color(red: 0.42, green: 0.20, blue: 0.85), Color(red: 0.70, green: 0.40, blue: 0.98)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)

    static func color(_ m: Mastery) -> Color {
        switch m {
        case .notStarted: empty
        case .red: red
        case .orange: orange
        case .green: green
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.stroke, lineWidth: 1))
            .shadow(color: Palette.purple.opacity(0.06), radius: 10, y: 3)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 10 : 16).padding(.vertical, compact ? 6 : 9)
            .background(Palette.gradient, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .shadow(color: Palette.purple.opacity(0.25), radius: 6, y: 2)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .foregroundStyle(Palette.lilac)
            .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 6 : 8)
            .background(configuration.isPressed ? Palette.stroke : Palette.cardHi, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
    }
}

struct MasterySquare: View {
    var mastery: Mastery
    var size: CGFloat = 14
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(Palette.color(mastery))
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.25).strokeBorder(.black.opacity(0.05)))
    }
}

struct Chip: View {
    var text: String
    var color: Color = Palette.violet
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// How much of her Claude plan Hank has used — the tightest limit window, as a ring.
struct UsageRing: View {
    var size: CGFloat = 26
    var showLabel = false
    @State private var hovering = false
    var usage = ClaudeUsage.shared

    var body: some View {
        let u = usage.primary?.utilization ?? 0
        let color = u >= 0.85 ? Palette.red : (u >= 0.6 ? Palette.orange : Palette.green)
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Palette.empty, lineWidth: size * 0.14)
                Circle().trim(from: 0, to: max(0.001, min(u, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if usage.refreshing && usage.primary == nil {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(usage.primary == nil ? "–" : "\(Int((u * 100).rounded()))")
                        .font(.system(size: size * 0.34, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                }
            }
            .frame(width: size, height: size)
            if showLabel {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hank usage").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(usage.primary.map { "\(Int(($0.utilization * 100).rounded()))% of \($0.name.lowercased())" } ?? "tap to check")
                        .font(.system(size: 10)).foregroundStyle(Palette.faint)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { Task { await usage.refresh() } }
        .popover(isPresented: $hovering, arrowEdge: .bottom) { UsageDetail(usage: usage) }
        .task { if usage.isStale { await usage.refresh() } }
    }
}

struct UsageDetail: View {
    var usage: ClaudeUsage
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HankAvatar(size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hank usage").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text)
                    Text("Your Claude plan limits").font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
            }
            if usage.windows.isEmpty {
                Text("No reading yet. Click the circle to check.").font(.system(size: 12)).foregroundStyle(Palette.dim)
            }
            ForEach(usage.windows) { w in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(w.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                        Spacer()
                        Text("\(Int((w.utilization * 100).rounded()))% used").font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(w.utilization >= 0.85 ? Palette.red : (w.utilization >= 0.6 ? Palette.orange : Palette.green))
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.empty)
                            Capsule().fill(Palette.gradient).frame(width: g.size.width * min(max(w.utilization, 0), 1))
                        }
                    }.frame(height: 6)
                    if let r = w.resetsAt {
                        Text("Resets \(r.formatted(.relative(presentation: .named))) · \(r.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 10.5)).foregroundStyle(Palette.faint)
                    }
                }
            }
            if usage.status == "rejected" {
                Text("Limit reached for now. Marking and chat come back after the reset.")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.red).fixedSize(horizontal: false, vertical: true)
            } else if (usage.primary?.utilization ?? 0) >= 0.85 {
                Text("Running low. Maybe save the rest for marking.").font(.system(size: 11.5).italic()).foregroundStyle(Palette.orange)
            }
            if let t = usage.updatedAt {
                Text("Updated \(t.formatted(.relative(presentation: .named))) · click the circle to refresh")
                    .font(.system(size: 10)).foregroundStyle(Palette.faint)
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}

enum HankLines {
    static let marking = [
        "Reading your answers. Neat handwriting, by the way.",
        "Checking every line against the markscheme…",
        "Spotting the key terms examiners love to see.",
        "Working out which marks you nailed and which are easy wins next time.",
        "Nearly there: writing up the bits worth remembering.",
    ]
    static let empty = [
        "No sessions yet. Pick a topic and let's go!",
        "Nothing here yet. Your first paper is one click away.",
    ]
    static func greeting(green: Int, total: Int, noun: String = "subtopic", nouns: String = "subtopics") -> String {
        switch green {
        case 0: "Hey! \(total) \(nouns) to turn green. Pick one and we'll start building momentum."
        case total: "Every single \(noun) is green. That's exam-ready. Seriously impressive."
        default: "\(green) of \(total) \(nouns) green. Nice. Let's keep the streak going."
        }
    }
}

/// Renders a region of a PDF page to an image (used for question crops and her handwriting).
struct PDFCropImage: View {
    var url: URL
    var page: Int
    var rectFromTop: CGRect          // fractions: x, y from top, width, height
    var width: CGFloat = 900
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Rectangle().fill(Palette.bg2).frame(height: 80)
            }
        }
        .task(id: "\(url.path)#\(page)#\(rectFromTop)") { image = await Self.render(url: url, page: page, rect: rectFromTop, width: width) }
    }

    static func render(url: URL, page: Int, rect: CGRect, width: CGFloat) async -> NSImage? {
        await Task.detached {
            guard let doc = PDFDocument(url: url), let pg = doc.page(at: page) else { return nil }
            let b = pg.bounds(for: .cropBox)
            let crop = CGRect(x: b.minX + rect.minX * b.width, y: b.maxY - rect.maxY * b.height,
                              width: rect.width * b.width, height: rect.height * b.height)
            guard let cg = Marking.render(pg, width: width, crop: crop) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        }.value
    }
}

/// Holds the live PDFView so SwiftUI buttons can zoom it.
@MainActor
final class PDFZoom: ObservableObject {
    weak var view: PDFView?
    @Published var percent = 100

    func zoomIn() { view?.autoScales = false; view?.zoomIn(nil); sync() }
    func zoomOut() { view?.autoScales = false; view?.zoomOut(nil); sync() }
    func fit() { view?.autoScales = true; sync() }
    func sync() {
        let next = Int(((view?.scaleFactor ?? 1) * 100).rounded())
        if percent != next { percent = next }
    }
}

struct PDFKitView: NSViewRepresentable {
    var url: URL
    var page: Int = 0
    var zoom: PDFZoom? = nil

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.minScaleFactor = 0.25
        v.maxScaleFactor = 6
        v.displayMode = .singlePageContinuous
        v.backgroundColor = NSColor(Palette.bg2)
        v.document = PDFDocument(url: url)
        if page > 0, let pg = v.document?.page(at: page) { DispatchQueue.main.async { v.go(to: pg) } }
        zoom?.view = v
        NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: v, queue: .main) { _ in
            MainActor.assumeIsolated { zoom?.sync() }
        }
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
        zoom?.view = v
    }
}

/// − / % / + / Fit controls for a PDFKitView. ⌘+ ⌘− ⌘0 work while it's on screen.
struct PDFZoomBar: View {
    @ObservedObject var zoom: PDFZoom
    var body: some View {
        HStack(spacing: 2) {
            Button { zoom.zoomOut() } label: { Image(systemName: "minus.magnifyingglass").frame(width: 28, height: 26) }
                .keyboardShortcut("-", modifiers: .command).help("Zoom out (⌘−)")
            Text("\(zoom.percent)%").font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.dim).frame(width: 44)
            Button { zoom.zoomIn() } label: { Image(systemName: "plus.magnifyingglass").frame(width: 28, height: 26) }
                .keyboardShortcut("=", modifiers: .command).help("Zoom in (⌘+)")
            Divider().frame(height: 16)
            Button { zoom.fit() } label: { Text("Fit").font(.system(size: 11.5, weight: .semibold)).frame(width: 34, height: 26) }
                .keyboardShortcut("0", modifiers: .command).help("Fit to width (⌘0)")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.purple)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.stroke))
        .shadow(color: Palette.purple.opacity(0.12), radius: 6, y: 2)
    }
}

struct ZoomTarget: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    var page: Int
    var title: String
}

/// Full-size, zoomable view of a page (opened by clicking a question or handwriting image).
struct ZoomSheet: View {
    var target: ZoomTarget
    @Environment(\.dismiss) var dismiss
    @StateObject private var zoom = PDFZoom()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(target.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                Spacer()
                PDFZoomBar(zoom: zoom)
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                    .padding(.leading, 8)
            }
            .padding(14)
            Divider().overlay(Palette.stroke)
            PDFKitView(url: target.url, page: target.page, zoom: zoom)
        }
        .frame(minWidth: 820, idealWidth: 1000, minHeight: 640, idealHeight: 900)
        .background(Palette.bg2)
    }
}
