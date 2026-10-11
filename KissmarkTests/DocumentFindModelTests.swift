import Foundation
import Testing
@testable import Kissmark

@MainActor
struct DocumentFindModelTests {
    private func result(_ model: DocumentFindModel, total: Int, active: Int, invalid: Bool = false) -> DocumentFindResult {
        DocumentFindResult(id: model.request.id, total: total, active: active, invalidRegex: invalid)
    }

    @Test("Each session owns one find model; sessions never share find state")
    func sessionsOwnSeparateFindModels() {
        let first = DocumentSession(newDocumentNamed: "A", text: "x")
        let second = DocumentSession(newDocumentNamed: "B", text: "x")
        first.find.present()

        #expect(first.find.isPresented)
        #expect(!second.find.isPresented)
    }

    @Test("Only the newest request's answer is accepted")
    func staleAnswersAreIgnored() {
        let model = DocumentFindModel()
        model.present()
        model.query = "a"
        model.search()
        let stale = result(model, total: 9, active: 3)
        model.query = "ab"
        model.search()
        #expect(model.receive(stale) == false)
        #expect(model.total == 0 && model.activeIndex == nil)
        #expect(model.receive(result(model, total: 2, active: 1)))
        #expect(model.total == 2 && model.activeIndex == 1)
    }

    @Test("No match and invalid regex are distinct states")
    func invalidRegexIsNotAnEmptySuccess() {
        let model = DocumentFindModel()
        model.present()
        model.query = "("
        model.useRegex = true
        model.search()
        model.receive(result(model, total: 0, active: -1, invalid: true))
        #expect(model.isInvalidRegex && model.activeIndex == nil)
        model.query = "zzz"
        model.search()
        #expect(model.isInvalidRegex == false, "a new search drops the previous error")
        model.receive(result(model, total: 0, active: -1))
        #expect(model.isInvalidRegex == false && model.total == 0 && model.activeIndex == nil)
    }

    @Test("Close clears results, sends an empty query, keeps the typed text and ignores late answers")
    func closeClears() {
        let model = DocumentFindModel()
        model.present()
        model.query = "word"
        model.search()
        model.receive(result(model, total: 3, active: 0))
        let pending = result(model, total: 3, active: 1)
        model.close()
        #expect(!model.isPresented && model.total == 0 && model.activeIndex == nil)
        #expect(model.request.query.isEmpty)
        #expect(model.query == "word")
        #expect(model.receive(pending) == false)
    }

    @Test("Present refocuses an open bar and re-runs a remembered query; next on a closed bar only opens it")
    func presentAndNext() {
        let model = DocumentFindModel()
        model.query = "x"
        model.next()
        #expect(model.isPresented && model.request.query == "x" && model.request.step == 0)
        let token = model.focusToken
        let id = model.request.id
        model.present()
        #expect(model.focusToken == token + 1 && model.request.id > id)
        model.close()
        model.previous()
        #expect(model.isPresented && model.request.step == 0)
    }

    @Test("Stepping with an empty query sends nothing")
    func emptyQueryNoStep() {
        let model = DocumentFindModel()
        model.present()
        let id = model.request.id
        model.next()
        model.previous()
        #expect(model.request.id == id)
    }
}
