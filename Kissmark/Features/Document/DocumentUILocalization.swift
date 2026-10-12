import Foundation

/// Editor-surface copy resolved natively and injected as `window.__KISSMARK_UI__`
/// before the editor mounts. Keys are the catalogue's Korean source strings;
/// `_editor-build` looks them up through `uiText(key)` and never carries its own
/// translations. Only app-owned chrome belongs here, never document content.
struct DocumentUILocalization: Encodable, Equatable {
    let language: String
    let messages: [String: String]

    /// Every key `uiText(...)` is called with in `_editor-build`.
    static let keys = [
        "문서 읽기", "문서 편집", "원문",
        "문서 정보", "폴더", "수정일", "생성일", "선택한 폴더",
        "검토", "검토 완료됨", "검토할 포인트가 없습니다.", "검토 완료", "코멘트 (선택)",
        "에이전트", "결정", "경고", "실패", "다음", "할 일", "변경",
        "블록 전환", "블록 검색", "전환",
        "텍스트", "제목 1", "제목 2", "제목 3", "제목 4", "제목 5",
        "할 일 목록", "글머리 기호 목록", "번호 매기기 목록", "인용", "콜아웃",
        "구분선", "목록", "고급", "코드 블록", "표",
        "내용을 입력하세요…", "링크를 붙여넣으세요…",
        "굵게", "기울임", "취소선", "코드", "링크",
        "언어 검색", "복사", "복사됨", "결과 없음",
    ]

    init(language: String, bundle: Bundle) {
        self.language = language
        messages = Dictionary(uniqueKeysWithValues: Self.keys.map {
            ($0, bundle.localizedString(forKey: $0, value: $0, table: nil))
        })
    }

    /// Launch-pinned like the rest of the native UI: a pending language choice
    /// never changes a running surface.
    static let current = DocumentUILocalization(
        language: KissmarkLocalization.languageCode,
        bundle: KissmarkLocalization.bundle
    )
}
