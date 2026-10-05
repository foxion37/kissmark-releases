import Foundation

/// Payload of the surface's in-flow 검토 card (`window.KissmarkEditor.setReview`).
struct DocumentReview: Equatable, Codable {
    struct Point: Equatable, Codable {
        let id: Int64
        let source: String
        let kind: String
        let heading: String?
        let quote: String
        let note: String?
        let checked: Bool
        let comment: String?
    }

    var points: [Point]
    let completedLabel: String?
    var expanded: Bool

    static let expansionStorageKey = "kissmark.review.expanded"
}

/// What the surface's card asks for; the workspace performs it.
enum ReviewAction: Equatable {
    case check(id: Int64)
    case uncheck(id: Int64)
    case comment(id: Int64, comment: String)
    case complete
}

extension DocumentReview.Point {
    init(_ point: ReviewPoint) {
        self.init(
            id: point.id, source: point.source, kind: point.kind, heading: point.heading,
            quote: point.quote, note: point.note, checked: point.checkedAt != nil, comment: point.comment
        )
    }
}
