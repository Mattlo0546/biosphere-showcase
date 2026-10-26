import SwiftUI
import PDFKit

struct BusinessMarkedPaperView: View {
    @Environment(AppModel.self) var model
    var session: StudySession
    var result: BusinessResult
    @State private var updated: BusinessResult?
    @State private var selected: PaperComment?
    @StateObject private var zoom = PDFZoom()
    var current: BusinessResult { updated ?? result }
    var comments: [PaperComment] { BusinessAnnotations.comments(current) }
    var busy: Bool { model.businessAnnotating.contains(session.id) }
    var hasLocations: Bool { comments.contains { !($0.sentence.anchors ?? []).isEmpty } }
    var paperURL: URL {
        let marked = model.annotatedBusinessURL(session)
        return hasLocations && FileManager.default.fileExists(atPath: marked.path) ? marked : model.completedURL(session)
    }

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Your paper, marked by Hank", systemImage: "pencil.tip.crop.circle")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                    Spacer()
                    PDFZoomBar(zoom: zoom)
                    Button { NSWorkspace.shared.open(paperURL) } label: { Label("Open PDF", systemImage: "arrow.up.right.square") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                }
                HStack(spacing: 14) {
                    Label("What worked", systemImage: "circle.fill").foregroundStyle(Palette.green)
                    Label("How to improve", systemImage: "circle.fill").foregroundStyle(Palette.orange)
                    Text("Click a highlight or comment icon to read Hank's note.").foregroundStyle(Palette.dim)
                }.font(.system(size: 11.5))
                if !hasLocations {
                    HStack(spacing: 12) {
                        Text("Add your saved essay feedback to the handwriting on these pages.")
                            .font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                        Spacer()
                        if busy { ProgressView().controlSize(.small); Text("Placing comments…").font(.system(size: 12)) }
                        else {
                            Button { Task { await model.addBusinessAnnotations(session) } } label: {
                                Label("Add comments to my paper", systemImage: "highlighter")
                            }.buttonStyle(PrimaryButtonStyle(compact: true))
                        }
                    }
                }
                if let error = model.businessAnnotationErrors[session.id] {
                    Text(error).font(.system(size: 12)).foregroundStyle(Palette.red)
                }
                HStack(alignment: .top, spacing: 12) {
                    TeacherPDFView(url: paperURL, selectedId: selected?.id, comments: comments, firstPage: session.answerPages?.first, zoom: zoom) { id in
                        selected = comments.first { $0.id == id }
                    }
                    .id(paperURL)
                    .frame(minHeight: 650)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    if let comment = selected {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("\(comment.number). \(comment.title)").font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(comment.isStrength ? Palette.green : Palette.orange)
                                Spacer()
                                Button { selected = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                            }
                            Text("Question \(BusinessPart.display(comment.part)) · \(comment.sentence.label.capitalized)")
                                .font(.system(size: 11)).foregroundStyle(Palette.faint)
                            Text(comment.sentence.text).font(.system(size: 13)).foregroundStyle(Palette.text).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider()
                            Text(comment.sentence.note.isEmpty ? (comment.isStrength ? "This sentence contributes to the answer." : "This sentence needs a clearer link to the question.") : comment.sentence.note)
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if (comment.sentence.anchors ?? []).isEmpty {
                                Text("Hank couldn't confidently locate this sentence on the page. The comment is kept here.")
                                    .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                            }
                            if let set = model.businessSet(for: session), let part = set.parts.first(where: { $0.label == comment.part }), session.caseSubject == .business, let bank = model.business {
                                BusinessReadingLinks(topics: part.topicIds.compactMap { bank.topic($0) }, stacked: true)
                            }
                        }.padding(18).frame(width: 320, alignment: .topLeading)
                            .layoutPriority(1)
                            .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(comments) { comment in
                            Button { selected = comment } label: {
                                Text("\(comment.number) · \(comment.sentence.label.capitalized)")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(comment.isStrength ? Palette.green : Palette.orange)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(selected?.id == comment.id ? Palette.cardHi : Palette.bg2, in: Capsule())
                            }.buttonStyle(.plain).help(comment.sentence.note)
                        }
                    }
                }
                let unplaced = comments.filter { ($0.sentence.anchors ?? []).isEmpty }.count
                if hasLocations && unplaced > 0 {
                    Text("\(unplaced) comment\(unplaced == 1 ? "" : "s") couldn't be placed confidently. Select their buttons above to read them.")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                }
            }
        }
        .task { refresh() }
        .onChange(of: busy) { _, running in if !running { refresh() } }
    }

    func refresh() {
        updated = model.businessResults(session) ?? result
        if hasLocations, !FileManager.default.fileExists(atPath: model.annotatedBusinessURL(session).path) {
            do { try BusinessAnnotations.write(result: current, source: model.completedURL(session), to: model.annotatedBusinessURL(session)) }
            catch { model.businessAnnotationErrors[session.id] = error.localizedDescription }
        }
    }
}

final class TeacherPDF: PDFView {
    var commentClicked: ((String) -> Void)?
    var commentIds: [Int: String] = [:]
    private func comment(at point: CGPoint) -> String? {
        guard bounds.contains(point), let page = page(for: point, nearest: false) else { return nil }
        let target = convert(point, to: page)
        for annotation in page.annotations.reversed() where annotation.bounds.insetBy(dx: -3, dy: -3).contains(target) {
            if let number = BusinessAnnotations.commentNumber(annotation), let id = commentIds[number] { return id }
        }
        return nil
    }

    // PDFKit's document subview normally consumes clicks. Route teacher annotations to this view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if comment(at: convert(point, from: superview)) != nil { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        if let id = comment(at: convert(event.locationInWindow, from: nil)) {
            commentClicked?(id)
            return
        }
        super.mouseDown(with: event)
    }
}

struct TeacherPDFView: NSViewRepresentable {
    var url: URL
    var selectedId: String?
    var comments: [PaperComment]
    var firstPage: Int?
    var zoom: PDFZoom
    var onSelect: (String) -> Void
    final class Coordinator {
        var selectedId: String?
        var scaleObserver: NSObjectProtocol?
        deinit { if let scaleObserver { NotificationCenter.default.removeObserver(scaleObserver) } }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> TeacherPDF {
        let view = TeacherPDF()
        view.autoScales = true
        view.minScaleFactor = 0.25
        view.maxScaleFactor = 6
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor(Palette.bg2)
        view.document = PDFDocument(url: url)
        view.commentIds = Dictionary(uniqueKeysWithValues: comments.map { ($0.number, $0.id) })
        view.commentClicked = onSelect
        zoom.view = view
        context.coordinator.scaleObserver = NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: view, queue: .main) { [weak zoom] _ in
            MainActor.assumeIsolated { zoom?.sync() }
        }
        let firstAnchor = comments.compactMap { $0.sentence.anchors?.first }.first
        if let number = firstAnchor?.page ?? firstPage, let page = view.document?.page(at: number - 1) {
            DispatchQueue.main.async {
                if let firstAnchor { view.go(to: BusinessAnnotations.rect(firstAnchor, bounds: page.bounds(for: .cropBox)).insetBy(dx: -20, dy: -60), on: page) }
                else { view.go(to: page) }
            }
        }
        return view
    }
    func updateNSView(_ view: TeacherPDF, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        view.commentIds = Dictionary(uniqueKeysWithValues: comments.map { ($0.number, $0.id) })
        view.commentClicked = onSelect
        zoom.view = view
        if context.coordinator.selectedId != selectedId {
            context.coordinator.selectedId = selectedId
            if let selectedId, let document = view.document {
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index), let annotation = page.annotations.first(where: {
                        BusinessAnnotations.commentNumber($0).flatMap { view.commentIds[$0] } == selectedId
                    }) else { continue }
                    view.go(to: annotation.bounds.insetBy(dx: -20, dy: -50), on: page)
                    break
                }
            }
        }
    }
}
