import Foundation
import Testing
@testable import Kissmark

@MainActor
struct DocumentInfoBarTests {
    @Test("Edit Mode with pending edits reads 저장 중")
    func dirtyEditIsSaving() {
        let state = DocumentInfoBar.saveState(isDirty: true, mode: .edit, hasSaveError: false)

        #expect(state == .saving)
        #expect(state.text == String(localized: "저장 중"))
    }

    @Test("A clean Document reads 저장됨")
    func cleanDocumentIsSaved() {
        #expect(DocumentInfoBar.saveState(isDirty: false, mode: .edit, hasSaveError: false) == .saved)
        #expect(DocumentInfoBar.saveState(isDirty: false, mode: .read, hasSaveError: false) == .saved)
    }

    @Test("Read Mode reads 저장됨 even while the lock's final change is still pending")
    func readModeIsSaved() {
        #expect(DocumentInfoBar.saveState(isDirty: true, mode: .read, hasSaveError: false) == .saved)
    }

    @Test("A failed write wins over the dirty flag")
    func failureWinsOverDirty() {
        let state = DocumentInfoBar.saveState(isDirty: false, mode: .read, hasSaveError: true)

        #expect(state == .failed)
        #expect(state.text == String(localized: "저장 실패"))
        #expect(DocumentInfoBar.saveState(isDirty: true, mode: .edit, hasSaveError: true) == .failed)
    }
}
