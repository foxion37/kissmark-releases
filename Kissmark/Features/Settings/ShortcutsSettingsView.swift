import SwiftUI

/// Settings › 단축키. The app's own keyboard shortcuts, listed for discovery —
/// these are the bindings the app and the Document surface actually register;
/// the list is documentation, not a configuration surface.
struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                shortcutRow("폴더 열기", "⌘O")
                shortcutRow("새로고침", "⌘R")
                shortcutRow("실행 취소", "⌘Z")
                shortcutRow("다시 실행", "⇧⌘Z")
                shortcutRow("텍스트 정리", "⇧⌘L")
            } header: {
                Text("문서")
            } footer: {
                Text("새로고침은 창 전체를 디스크에서 다시 불러오고 열린 문서를 다시 엽니다. 저장되지 않은 변경이 있으면 새로고침하지 않습니다. 텍스트 정리는 설정 › 일반에서 끌 수 있습니다. 편집 모드에서만 동작합니다.")
            }

            Section {
                shortcutRow("블록 메뉴", "⌘/")
                shortcutRow("텍스트, 제목 1–3, 할 일, 글머리 기호, 번호 목록", "⌘⌥0–6")
                shortcutRow("인용", "⌘⌥.")
                shortcutRow("구분선", "⌘⌥-")
                shortcutRow("콜아웃", "⌘⌥C")
                shortcutRow("굵게", "⌘B")
                shortcutRow("기울임", "⌘I")
                shortcutRow("인라인 코드", "⌘E")
            } header: {
                Text("편집 모드")
            } footer: {
                Text("블록 전환 단축키는 커서가 놓인 블록에 적용됩니다.")
            }

            Section {
                shortcutRow("설정", "⌘,")
            } header: {
                Text("앱")
            }
        }
        .formStyle(.grouped)
        .kissmarkSettingsNavigationTitle("단축키")
    }

    private func shortcutRow(_ action: LocalizedStringKey, _ keys: String) -> some View {
        LabeledContent {
            Text(verbatim: keys)
                .monospaced()
                .foregroundStyle(.secondary)
        } label: {
            Text(action)
        }
    }
}
