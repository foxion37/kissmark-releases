import Foundation
import Testing
@testable import Kissmark

struct SurfaceStyleScriptTests {
    @Test("Dropped keys are removed, kept keys are set, nothing else is removed")
    func replacesInsteadOfMerging() {
        let script = SurfaceStyleScript.styleScript(
            applying: ["a": "1"],
            removing: ["a", "b"]
        )
        #expect(script.contains("removeProperty(\"b\");"))
        #expect(script.contains("setProperty(\"a\", \"1\");"))
        #expect(!script.contains("removeProperty(\"a\")"))
    }

    @Test("Keys and values are emitted as JSON string literals")
    func escapesQuotesBackslashesAndNewlines() {
        let script = SurfaceStyleScript.styleScript(
            applying: ["--x": "a'b\\c\nd"],
            removing: []
        )
        #expect(script == "document.documentElement.style.setProperty(\"--x\", \"a'b\\\\c\\nd\");")
    }

    @Test("The theme scheme key writes documentElement.dataset, not a CSS property")
    func schemeKeyBecomesDataset() {
        let applied = SurfaceStyleScript.styleScript(
            applying: [SurfaceStyleScript.schemeKey: "dark"],
            removing: []
        )
        #expect(applied == "document.documentElement.dataset.kmScheme = \"dark\";")

        let removed = SurfaceStyleScript.styleScript(
            applying: [:],
            removing: [SurfaceStyleScript.schemeKey]
        )
        #expect(removed == "delete document.documentElement.dataset.kmScheme;")

        let mixed = SurfaceStyleScript.styleScript(
            applying: ["--km-theme-bg": "#282A36", SurfaceStyleScript.schemeKey: "light"],
            removing: []
        )
        #expect(mixed.contains("document.documentElement.style.setProperty(\"--km-theme-bg\", \"#282A36\");"))
        #expect(mixed.contains("document.documentElement.dataset.kmScheme = \"light\";"))
        #expect(!mixed.contains("setProperty(\"--km-theme-scheme\""))
    }
}
