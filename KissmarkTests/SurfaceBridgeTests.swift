import Foundation
import Testing
@testable import Kissmark

@MainActor
struct SurfaceBridgeTests {
    final class Recorder: SurfaceCommands {
        var log: [String] = []
        func setMode(_ mode: DocumentMode) { log.append("mode:\(mode == .read ? "read" : "edit")") }
        func setViewMode(_ mode: DocumentViewMode) { log.append("view:\(mode == .source ? "source" : "render")") }
        func setMarkdown(_ markdown: String) { log.append("md:\(markdown)") }
        func setStyle(_ variables: [String: String], crossfade: Bool) {
            log.append((crossfade ? "fade:" : "style:") + variables.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))
        }
        func reload() { log.append("reload") }
        func setDocumentInfo(_ info: DocumentInfo) {
            log.append("info:\(info.path),\(info.saveState),\(info.expanded)")
        }
        func setReview(_ review: DocumentReview) {
            log.append("review:\(review.points.count),\(review.expanded)")
        }
    }

    private func makeBridge() -> (SurfaceBridge, Recorder, () -> [String], () -> [String?]) {
        let recorder = Recorder()
        var texts: [String] = []
        var errors: [String?] = []
        let bridge = SurfaceBridge(
            commands: recorder,
            onTextChange: { texts.append($0) },
            onError: { errors.append($0) }
        )
        return (bridge, recorder, { texts }, { errors })
    }

    private func review(_ count: Int, expanded: Bool = true) -> DocumentReview {
        DocumentReview(
            points: (0..<count).map {
                .init(id: Int64($0), source: "rule", kind: "task", heading: nil, quote: "q", note: nil, checked: false, comment: nil)
            },
            completedLabel: nil,
            expanded: expanded
        )
    }

    @Test("Review is queued before ready, pushed after info, and not re-pushed when unchanged")
    func reviewPushOrderAndDedupe() {
        let (bridge, recorder, _, _) = makeBridge()
        bridge.didStartLoading()
        bridge.update(text: "# A", mode: .read, viewMode: .render, style: [:])
        bridge.update(review: review(2))
        bridge.update(info: DocumentInfo(path: "a.md", saveState: "saved", saveLabel: "", modified: "", created: "", expanded: true))
        #expect(recorder.log.isEmpty)

        bridge.receive(.ready(markdown: "# A", mode: .read))
        #expect(recorder.log == ["style:", "info:a.md,saved,true", "review:2,true"])

        bridge.update(review: review(2))
        #expect(recorder.log.count == 3, "identical review pushes nothing")

        bridge.update(review: review(2, expanded: false))
        #expect(recorder.log.last == "review:2,false")

        bridge.didStartLoading()
        bridge.receive(.ready(markdown: "# A", mode: .read))
        #expect(recorder.log.last == "review:2,false", "a reload re-pushes the review")
    }

    @Test("Nothing is pushed before ready; ready seeds the last-pushed state")
    func pushesWaitForReady() {
        let (bridge, recorder, _, _) = makeBridge()
        bridge.didStartLoading()
        bridge.update(text: "# A", mode: .read, viewMode: .render, style: ["--km-font-scale": "1"])
        #expect(recorder.log.isEmpty)

        bridge.receive(.ready(markdown: "# A", mode: .read))
        #expect(recorder.log == ["style:--km-font-scale=1"])

        bridge.update(text: "# A", mode: .read, viewMode: .render, style: ["--km-font-scale": "1"])
        #expect(recorder.log == ["style:--km-font-scale=1"], "identical state pushes nothing")

        bridge.update(text: "# B", mode: .edit, viewMode: .render, style: ["--km-font-scale": "1.1"])
        #expect(recorder.log == [
            "style:--km-font-scale=1",
            "mode:edit",
            "style:--km-font-scale=1.1",
            "md:# B",
        ])
    }

    @Test("Only a palette change after the first push crossfades; spacing and size changes glide instead")
    func paletteChangesCrossfade() {
        let (bridge, recorder, _, _) = makeBridge()
        let dark = ["--km-theme-bg": "#1E1E2E", "--km-theme-scheme": "dark"]
        bridge.update(text: "# A", mode: .read, viewMode: .render, style: dark)
        bridge.receive(.ready(markdown: "# A", mode: .read))
        #expect(recorder.log.last?.hasPrefix("style:") == true, "the post-load push restates the bootstrap")

        bridge.update(text: "# A", mode: .read, viewMode: .render, style: dark.merging(["--km-user-line-height": "1.9"]) { $1 })
        #expect(recorder.log.last?.hasPrefix("style:") == true)

        bridge.update(text: "# A", mode: .read, viewMode: .render, style: ["--km-theme-bg": "#FAF4ED", "--km-user-line-height": "1.9"])
        #expect(recorder.log.last?.hasPrefix("fade:") == true, "a theme color and scheme change repaint the page")

        bridge.update(text: "# A", mode: .read, viewMode: .render, style: ["--km-theme-bg": "#FAF4ED", "--km-user-h1-color": "#112233"])
        #expect(recorder.log.last?.hasPrefix("fade:") == true, "an element color override repaints too")

        bridge.didStartLoading()
        bridge.receive(.ready(markdown: "# A", mode: .read))
        #expect(recorder.log.last?.hasPrefix("style:") == true, "a reload has nothing to fade from")
    }

    @Test("A JS change updates the text once and suppresses the echo push")
    func changeSuppressesEcho() {
        let (bridge, recorder, texts, _) = makeBridge()
        bridge.didStartLoading()
        bridge.receive(.ready(markdown: "", mode: .edit))
        bridge.update(text: "", mode: .edit, viewMode: .render, style: [:])

        bridge.receive(.change(markdown: "typed", isFinal: false))
        #expect(texts() == ["typed"])
        bridge.update(text: "typed", mode: .edit, viewMode: .render, style: [:])
        #expect(!recorder.log.contains("md:typed"), "the echo of our own change is not pushed back")

        bridge.update(text: "typed more", mode: .edit, viewMode: .render, style: [:])
        #expect(recorder.log.last == "md:typed more")
    }

    @Test("A change while in Read Mode is ignored")
    func changeInReadModeIsIgnored() {
        let (bridge, _, texts, _) = makeBridge()
        bridge.didStartLoading()
        bridge.receive(.ready(markdown: "# A", mode: .read))
        bridge.update(text: "# A", mode: .read, viewMode: .render, style: [:])

        bridge.receive(.change(markdown: "# A\nremount echo", isFinal: false))
        #expect(texts().isEmpty)
    }

    @Test("Ready timeout reports an error only if still not ready")
    func readyTimeout() {
        let (bridge, _, _, errors) = makeBridge()
        bridge.didStartLoading()
        bridge.readyTimedOut()
        #expect(errors().last! != nil)
        #expect(!bridge.isReady)

        bridge.didStartLoading()
        bridge.receive(.ready(markdown: nil, mode: nil))
        bridge.readyTimedOut()
        #expect(errors().last! == nil, "ready clears the error and a late timeout is ignored")
    }

    @Test("First termination reloads once; the second reports an error")
    func secondTerminationReportsError() {
        let (bridge, recorder, _, errors) = makeBridge()
        bridge.didStartLoading()
        bridge.receive(.ready(markdown: nil, mode: nil))

        bridge.processDidTerminate()
        #expect(recorder.log.contains("reload"))
        #expect(!bridge.isReady)

        bridge.receive(.ready(markdown: nil, mode: nil))
        bridge.processDidTerminate()

        #expect(recorder.log.filter { $0 == "reload" }.count == 2, "ready resets the reload budget")

        bridge.processDidTerminate()
        #expect(recorder.log.filter { $0 == "reload" }.count == 2)
        #expect(errors().last! != nil)
    }

    @Test("The suppressed push does not record unsent text as pushed")
    func suppressedPushDoesNotSwallowNewText() {
        let (bridge, recorder, _, _) = makeBridge()
        bridge.didStartLoading()
        bridge.receive(.ready(markdown: "", mode: .edit))
        bridge.update(text: "", mode: .edit, viewMode: .render, style: [:])

        bridge.receive(.change(markdown: "typed", isFinal: false))
        bridge.update(text: "external", mode: .edit, viewMode: .render, style: [:])
        #expect(!recorder.log.contains("md:external"), "the first update after a change is swallowed once")

        bridge.update(text: "external", mode: .edit, viewMode: .render, style: [:])
        #expect(recorder.log.last == "md:external", "the same text must still reach the editor")
    }

    @Test("A final change is accepted even after the surface switched to Read Mode")
    func finalChangeInReadModeIsAccepted() {
        let (bridge, recorder, texts, _) = makeBridge()
        bridge.didStartLoading()
        bridge.receive(.ready(markdown: "typed", mode: .edit))
        bridge.update(text: "typed", mode: .edit, viewMode: .render, style: [:])
        bridge.update(text: "typed", mode: .read, viewMode: .render, style: [:])

        bridge.receive(.change(markdown: "typed + last keystroke", isFinal: true))
        #expect(texts() == ["typed + last keystroke"])
        bridge.update(text: "typed + last keystroke", mode: .read, viewMode: .render, style: [:])
        #expect(!recorder.log.contains("md:typed + last keystroke"), "the final change is not echoed back")
    }

    @Test("A final change that repeats the known text does not swallow the next push")
    func sameTextFinalKeepsSuppressionOff() {
        let (bridge, recorder, texts, _) = makeBridge()
        bridge.didStartLoading()
        bridge.receive(.ready(markdown: "a", mode: .edit))
        bridge.update(text: "a", mode: .edit, viewMode: .render, style: [:])
        bridge.update(text: "a", mode: .read, viewMode: .render, style: [:])

        bridge.receive(.change(markdown: "a", isFinal: true))
        #expect(texts() == ["a"])

        bridge.update(text: "b", mode: .read, viewMode: .render, style: [:])
        #expect(recorder.log.last == "md:b", "the next real push still reaches the editor")
    }

    @Test("A final change restores an edit that the debounced change lost")
    func finalChangeRestoresDeletedEdit() {
        let (bridge, _, texts, _) = makeBridge()
        bridge.didStartLoading()
        bridge.receive(.ready(markdown: "a", mode: .edit))
        bridge.update(text: "a", mode: .edit, viewMode: .render, style: [:])

        bridge.receive(.change(markdown: "ab", isFinal: false))
        #expect(texts() == ["ab"])
        bridge.update(text: "ab", mode: .edit, viewMode: .render, style: [:])
        bridge.update(text: "ab", mode: .read, viewMode: .render, style: [:])

        bridge.receive(.change(markdown: "a", isFinal: true))
        #expect(texts() == ["ab", "a"], "the deleted text is restored even though it equals the ready markdown")
    }

    @Test("A queued source view waits for ready, then is not sent twice")
    func viewModeWaitsForReady() {
        let (bridge, recorder, _, _) = makeBridge()
        bridge.didStartLoading()
        bridge.update(text: "# A", mode: .read, viewMode: .source, style: ["--km-font-scale": "1"])
        #expect(recorder.log.isEmpty, "nothing reaches JS before ready")

        bridge.receive(.ready(markdown: "# A", mode: .read))
        #expect(recorder.log == ["view:source", "style:--km-font-scale=1"])

        bridge.update(text: "# A", mode: .read, viewMode: .source, style: ["--km-font-scale": "1"])
        #expect(recorder.log == ["view:source", "style:--km-font-scale=1"], "the same view mode is not re-sent")
    }

    @Test("A fresh page starts rendered, so the render view is never pushed")
    func renderViewIsNotPushed() {
        let (bridge, recorder, _, _) = makeBridge()
        bridge.didStartLoading()
        bridge.update(text: "# A", mode: .read, viewMode: .render, style: ["--km-font-scale": "1"])

        bridge.receive(.ready(markdown: "# A", mode: .read))

        #expect(recorder.log == ["style:--km-font-scale=1"])
    }

    @Test("Returning to the rendered view is pushed")
    func returningToRenderIsPushed() {
        let (bridge, recorder, _, _) = makeBridge()
        bridge.didStartLoading()
        bridge.update(text: "# A", mode: .read, viewMode: .source, style: ["--km-font-scale": "1"])
        bridge.receive(.ready(markdown: "# A", mode: .read))

        bridge.update(text: "# A", mode: .read, viewMode: .render, style: ["--km-font-scale": "1"])

        #expect(recorder.log.filter { $0.hasPrefix("view:") } == ["view:source", "view:render"])
    }

    @Test("A crash reload re-applies the queued source view")
    func viewModeReappliedAfterReload() {
        let (bridge, recorder, _, _) = makeBridge()
        bridge.didStartLoading()
        bridge.update(text: "# A", mode: .read, viewMode: .source, style: ["--km-font-scale": "1"])
        bridge.receive(.ready(markdown: "# A", mode: .read))

        bridge.processDidTerminate()
        bridge.receive(.ready(markdown: "# A", mode: .read))

        #expect(
            recorder.log.filter { $0 == "view:source" }.count == 2,
            "the reloaded page mounts rendered and must be told again"
        )
    }

}
