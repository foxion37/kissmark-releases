import Testing
@testable import Kissmark

struct ReviewRulesTests {
    @Test func headingKindsMatchWholeAsciiWordsAndKoreanSubstrings() {
        #expect(ReviewRules.points(in: "## Context\n본문").isEmpty)
        #expect(ReviewRules.points(in: "## CONTEXTS\n본문").isEmpty)
        #expect(ReviewRules.points(in: "## 결정\n항목").map(\.kind) == ["decision"])
        #expect(ReviewRules.points(in: "## Risks\n항목").map(\.kind) == ["warning"])
        #expect(ReviewRules.points(in: "## 주의 사항\n항목").map(\.kind) == ["warning"])
        #expect(ReviewRules.points(in: "## Error\n항목").map(\.kind) == ["failure"])
        #expect(ReviewRules.points(in: "## Next steps\n항목").map(\.kind) == ["next"])
        #expect(ReviewRules.points(in: "## TODO\n항목").map(\.kind) == ["next"])
        #expect(ReviewRules.points(in: "## 할 일\n항목").map(\.kind) == ["next"])
        #expect(ReviewRules.points(in: "## 후속\n항목").map(\.kind) == ["next"])
    }

    @Test func sectionsYieldFirstContentLineWithMarkersStripped() {
        let points = ReviewRules.points(in: "## 경고\n- \n- 실제 내용")
        #expect(points.count == 1)
        #expect(points[0].quote == "실제 내용")
        let numbered = ReviewRules.points(in: "## 다음\n1. 첫 단계")
        #expect(numbered.map(\.quote) == ["첫 단계"])
        // An empty section yields no point.
        #expect(ReviewRules.points(in: "## 경고\n## 결정\n내용").map(\.kind) == ["decision"])
    }

    @Test func frontmatterAndFencedCodeAreSkipped() {
        let text = """
        ---
        title: 결정
        경고: 내용
        ---

        ```
        ## 경고
        코드 안 문장
        ```
        """
        #expect(ReviewRules.points(in: text).isEmpty)
    }

    @Test func tasksCollectedWithNearestHeading() {
        let text = "## 준비\n소개\n- [ ] 준비 작업\n- [x] 끝난 작업\n* [ ] 별표 작업"
        let points = ReviewRules.points(in: text)
        #expect(points.map { [$0.kind, $0.heading ?? "", $0.quote] } == [
            ["task", "준비", "준비 작업"],
            ["task", "준비", "별표 작업"],
        ])
    }

    @Test func changedParagraphsComeFromSnapshotDiff() {
        let snapshot = "첫 문단\n\n둘째 문단"
        let text = "첫 문단\n\n둘째 문단\n\n## 새 제목\n\n셋째 문단"
        let points = ReviewRules.points(in: text, snapshot: snapshot)
        #expect(points.map { [$0.kind, $0.heading ?? "", $0.quote] } == [
            ["changed", "새 제목", "셋째 문단"],
        ])
        #expect(ReviewRules.points(in: text, snapshot: text).isEmpty)
    }

    @Test func orderCapAndQuoteTrim() {
        let long = String(repeating: "가", count: 300)
        let text = "## 할 일\n- [ ] 작업\n## 경고\n\(long)\n## 결정\n내용\n## 오류\n내용\n## 다음\n내용"
        let points = ReviewRules.points(in: text)
        #expect(points.map(\.kind) == ["failure", "warning", "decision", "next", "task"])
        #expect(points[1].quote.count == 200)
        let many = (1...25).map { "- [ ] 항목 \($0)" }.joined(separator: "\n")
        #expect(ReviewRules.points(in: many).count == 20)
    }

    @Test func checkedPointsAreSkipped() {
        let text = "## 경고\n조심"
        let checked = [ReviewRules.Point(kind: "warning", heading: "경고", quote: "조심")]
        #expect(ReviewRules.points(in: text, checked: checked).isEmpty)
        #expect(ReviewRules.points(in: text).count == 1)
    }
}
