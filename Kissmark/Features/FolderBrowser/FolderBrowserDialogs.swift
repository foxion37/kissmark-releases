import SwiftUI

/// New-document prompt, discard confirmation, error alert, and notice — shared by every platform layout.
struct FolderBrowserDialogs: ViewModifier {
    let workspace: FolderBrowserWorkspace
    @Binding var isNewDocumentPresented: Bool
    @Binding var newDocumentName: String
    let createDocument: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("새 문서", isPresented: $isNewDocumentPresented) {
                TextField("이름", text: $newDocumentName)
                Button("만들기", action: createDocument)
                Button("취소", role: .cancel) {}
            } message: {
                Text("선택한 폴더에 Markdown 문서를 만듭니다.")
            }
            .confirmationDialog(
                "저장하지 않은 변경을 버릴까요?",
                isPresented: Binding(
                    get: { workspace.pendingConfirmation == .discardChanges },
                    set: { if !$0 { workspace.cancelConfirmation() } }
                ),
                titleVisibility: .visible
            ) {
                Button("계속 편집", role: .cancel) { workspace.cancelConfirmation() }
                Button("변경 버리기", role: .destructive) { workspace.confirmDiscard() }
            }
            .alert(
                "작업을 완료하지 못했습니다",
                isPresented: Binding(
                    get: { workspace.errorMessage != nil },
                    set: { if !$0 { workspace.dismissError() } }
                )
            ) {
                Button("확인", role: .cancel) { workspace.dismissError() }
            } message: {
                Text(workspace.errorMessage ?? "")
            }
            .alert(
                workspace.notice?.title ?? "",
                isPresented: Binding(
                    get: { workspace.notice != nil },
                    set: { if !$0 { workspace.dismissNotice() } }
                )
            ) {
                Button("확인", role: .cancel) { workspace.dismissNotice() }
            } message: {
                Text(workspace.notice?.message ?? "")
            }
    }
}
