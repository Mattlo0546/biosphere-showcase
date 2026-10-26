import Foundation

/// The subjects on the Topics page. Biology and Maths share the question-bank engine (`Bank`, `Selector`,
/// `PDFComposer`, SM-2); Business has its own. Raw values are what `@AppStorage("subject")` stores.
enum Subject: String, CaseIterable, Identifiable {
    case biology, business, maths
    var id: String { rawValue }

    /// Bank folder name, also stored as `StudySession.subject` (nil there still means Biology).
    var slug: String {
        switch self {
        case .biology: "biology-sl"
        case .business: "business-hl"
        case .maths: "maths-aa-sl"
        }
    }

    var title: String {
        switch self {
        case .biology: "Biology SL"
        case .business: "Business HL"
        case .maths: "Maths AA SL"
        }
    }

    var icon: String {
        switch self {
        case .biology: "leaf.fill"
        case .business: "briefcase.fill"
        case .maths: "function"
        }
    }

    /// The one she last picked on the Topics page.
    static var current: Subject { Subject(rawValue: UserDefaults.standard.string(forKey: "subject") ?? "") ?? .biology }
}
