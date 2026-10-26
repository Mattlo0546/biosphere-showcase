import SwiftUI
import PDFKit

/// Both reading choices stay attached to the exact syllabus section used by the part.
struct BusinessReadingLinks: View {
    var topics: [BusinessTopic]
    var stacked = false
    @State private var openNotes: BusinessTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(topics) { topic in
                if stacked {
                    VStack(alignment: .leading, spacing: 8) {
                        topicName(topic)
                        HStack(spacing: 12) {
                            readingActions(topic)
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    HStack(spacing: 10) {
                        topicName(topic)
                        Spacer(minLength: 8)
                        readingActions(topic)
                    }
                }
            }
        }
        .sheet(item: $openNotes) { BusinessNotesView(topic: $0) }
    }

    func topicName(_ topic: BusinessTopic) -> some View {
        Text(topic.displayName).font(.system(size: 11.5)).foregroundStyle(Palette.dim)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    func readingActions(_ topic: BusinessTopic) -> some View {
        if topic.notesPage != nil {
            Button { openNotes = topic } label: {
                Label("My notes", systemImage: "book").fixedSize()
            }.buttonStyle(GhostButtonStyle(compact: true))
        }
        if let link = topic.revisionDojoUrl, let url = URL(string: link) {
            Link(destination: url) {
                Label("RevisionDojo", systemImage: "arrow.up.right")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.purple)
                    .fixedSize()
            }
        }
    }
}

struct BusinessNotesView: View {
    var topic: BusinessTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.displayName).font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.text)
                    Text("My notes · page \(topic.notesPage ?? 1)")
                        .font(.system(size: 12)).foregroundStyle(Palette.dim)
                }
                Spacer()
                if let link = topic.revisionDojoUrl, let url = URL(string: link) {
                    Link("Read on RevisionDojo ↗", destination: url)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.purple)
                }
                Button { dismiss() } label: { Image(systemName: "xmark").padding(8) }.buttonStyle(.plain)
            }
            if FileManager.default.fileExists(atPath: BusinessBank.notesURL.path) {
                BusinessNotesPDF(topic: topic)
            } else {
                Text("Your notes PDF isn't available in this build. You can use the RevisionDojo link above.")
                    .font(.system(size: 13)).foregroundStyle(Palette.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20).frame(minWidth: 760, minHeight: 650).background(Palette.bg)
    }
}

struct BusinessNotesPDF: NSViewRepresentable {
    var topic: BusinessTopic
    final class Coordinator { var topicId: String? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: BusinessBank.notesURL)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.topicId != topic.id, let document = view.document,
              let page = document.page(at: max(0, (topic.notesPage ?? 1) - 1)) else { return }
        context.coordinator.topicId = topic.id
        let bounds = page.bounds(for: .cropBox)
        let top = max(0, (topic.notesY ?? 0) - 0.025)
        DispatchQueue.main.async {
            view.go(to: PDFDestination(page: page, at: CGPoint(x: bounds.minX, y: bounds.maxY - bounds.height * top)))
        }
    }
}
