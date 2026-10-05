// Renders a document fixture through the shipped editor.html in a real WKWebView.
// List markers align with their first text line (DESIGN.md, Jev rule), and the
// opening block stays at the content padding with or without Crepe's leading widget.
// Run: swift scripts/check-list-alignment.swift
import Cocoa
import WebKit

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = repo.appendingPathComponent("Kissmark/Resources")
let stage = FileManager.default.temporaryDirectory.appendingPathComponent("kissmark-list-check")
try? FileManager.default.removeItem(at: stage)
try! FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
for (dir, only) in [("Editor", nil), ("Reader", "reader.css"), ("Fonts", nil)] as [(String, String?)] {
    let src = resources.appendingPathComponent(dir)
    for name in try! FileManager.default.contentsOfDirectory(atPath: src.path) where only == nil || name == only {
        try! FileManager.default.copyItem(at: src.appendingPathComponent(name), to: stage.appendingPathComponent(name))
    }
}

let fixture = """
**첫 소제목 Opening heading**

- 첫 번째 불릿 Bullet one
- 두 번째 항목이 아주 길어서 줄바꿈이 일어나는 경우를 확인하기 위한 문장입니다 long wrapping english words here too
  - 중첩 불릿 nested

1. 번호 항목 one
2. 두 번째 two
   1. 중첩 번호 nested
10. 두 자리 ten

- [ ] 할 일 task
- [x] 완료 done
"""

let measure = """
(() => {
  const baseline = (el, before) => { const s = document.createElement('span');
    s.style.cssText = 'display:inline-block;width:0;height:0;vertical-align:baseline';
    before ? el.insertBefore(s, el.firstChild) : el.appendChild(s);
    const y = s.getBoundingClientRect().top; s.remove(); return y; };
  const rows = [...document.querySelectorAll('li.list-item')].map(li => {
    const label = li.querySelector(':scope > .label-wrapper > .label');
    const p = li.querySelector(':scope > .children p');
    const text = p.firstChild; const r = document.createRange(); r.setStart(text, 0); r.setEnd(text, 1);
    const t = r.getClientRects()[0]; const svg = label.querySelector('svg');
    if (svg) { const b = svg.getBoundingClientRect();
      return { item: p.textContent.slice(0, 10), rule: 'center', delta: (b.top + b.bottom) / 2 - (t.top + t.bottom) / 2 }; }
    return { item: p.textContent.slice(0, 10), rule: 'baseline', delta: baseline(label, false) - baseline(p, true) };
  });
  const root = document.querySelector('.ProseMirror');
  const first = root.querySelector(':scope > p.km-strong-heading');
  // Remove transient entrance translation from the persistent layout measurement.
  const firstGap = rule => ({ item: 'opening bold paragraph', rule,
    delta: first.getBoundingClientRect().top - root.getBoundingClientRect().top
      - parseFloat(getComputedStyle(root).paddingTop)
      - (parseFloat(getComputedStyle(first).translate.split(/\\s+/)[1]) || 0) });
  rows.push(firstGap('first-block'));
  const widget = root.firstElementChild;
  if (widget?.classList.contains('ProseMirror-widget')) {
    widget.remove();
    rows.push(firstGap('first-block-no-widget'));
    root.insertBefore(widget, root.firstChild);
  }
  return rows;
})()
"""

let tolerance = 0.5
var failures = 0
var pending = ["read", "edit", "edit-insert"]
let app = NSApplication.shared
var views: [WKWebView] = []

func check(mode: String) {
    let config = WKWebViewConfiguration()
    let initial = mode == "edit-insert" ? "" : fixture
    let literal = String(data: try! JSONEncoder().encode([initial]), encoding: .utf8)!
    let surfaceMode = mode == "read" ? "read" : "edit"
    config.userContentController.addUserScript(WKUserScript(
        source: "window.__KISSMARK_INITIAL_MARKDOWN__=\(literal)[0];window.__KISSMARK_INITIAL_MODE__='\(surfaceMode)';",
        injectionTime: .atDocumentStart, forMainFrameOnly: true))
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 720, height: 900), configuration: config)
    views.append(view)
    view.loadFileURL(stage.appendingPathComponent("editor.html"), allowingReadAccessTo: stage)
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: DispatchWorkItem {
        let complete: (Any?, Error?) -> Void = { result, error in
            guard let json = result as? String,
                  let rows = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]],
                  !rows.isEmpty else {
                print("FAIL \(mode): no list items measured \(error.map { "\($0)" } ?? "")"); exit(1)
            }
            for row in rows {
                let delta = row["delta"] as! Double
                let ok = abs(delta) <= tolerance
                if !ok { failures += 1 }
                print("\(ok ? "ok  " : "FAIL") \(mode) \(row["rule"]!) \(String(format: "%+.2f", delta))px  \(row["item"]!)")
            }
            pending.removeAll { $0 == mode }
            if pending.isEmpty { exit(failures == 0 ? 0 : 1) }
        }
        if mode == "edit-insert" {
            Task {
                do {
                    let result = try await view.callAsyncJavaScript(
                        "await window.KissmarkEditor.setMarkdown(markdown); return JSON.stringify(\(measure));",
                        arguments: ["markdown": fixture], in: nil, contentWorld: .page)
                    complete(result, nil)
                } catch {
                    complete(nil, error)
                }
            }
        } else {
            view.evaluateJavaScript("JSON.stringify(\(measure))", completionHandler: complete)
        }
    })
}

pending.forEach(check)
app.run()
