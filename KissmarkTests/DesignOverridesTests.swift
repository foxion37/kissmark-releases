import SwiftUI
import Testing
@testable import Kissmark
#if os(iOS)
import UIKit
#endif

struct DesignOverridesTests {
    @Test("No overrides produce no CSS variables")
    func emptyProducesNothing() {
        #expect(DesignOverrides().cssVariables(for: .light).isEmpty)
        #expect(DesignOverrides().isEmpty)
    }

    @Test("Spacing values map to --km-user-*: bare numbers for the registered ones, ch for the measure")
    func spacingMaps() {
        var o = DesignOverrides()
        o.spacing = .init(lineHeight: 1.8, letterSpacingEm: -0.01, measureCh: 72, paragraphSpacingEm: 1.2)
        #expect(o.cssVariables(for: .light) == [
            "--km-user-line-height": "1.8",
            "--km-user-letter-spacing": "-0.01",
            "--km-user-measure": "72ch",
            "--km-user-paragraph-spacing": "1.2",
        ])
    }

    @Test("Element size, weight, and color map by element name")
    func elementsMap() {
        var o = DesignOverrides()
        o[element: .h1] = .init(sizeScale: 1.25, weight: 700, color: .init(light: "#112233", dark: nil))
        o[element: .codeBlock] = .init(sizeScale: 0.9, weight: nil, color: nil)
        #expect(o.cssVariables(for: .light) == [
            "--km-user-h1-size": "1.25",
            "--km-user-h1-weight": "700",
            "--km-user-h1-color": "#112233",
            "--km-user-code-block-size": "0.9",
        ])
    }

    @Test("Colors follow the active scheme and never leak across")
    func colorsFollowScheme() {
        var o = DesignOverrides()
        o[element: .link] = .init(sizeScale: nil, weight: nil, color: .init(light: "#AA0000", dark: nil))
        #expect(o.cssVariables(for: .light)["--km-user-link-color"] == "#AA0000")
        #expect(o.cssVariables(for: .dark)["--km-user-link-color"] == nil)
    }

    @Test("Unsupported properties, bad colors, and out-of-range values are dropped or clamped")
    func valuesAreClamped() {
        var o = DesignOverrides()
        o.spacing = .init(lineHeight: 9, letterSpacingEm: -1, measureCh: 10, paragraphSpacingEm: nil)
        o[element: .rule] = .init(sizeScale: 1.5, weight: 700, color: .init(light: "red; background:url(x)", dark: nil))
        o[element: .body] = .init(sizeScale: 0.1, weight: 900, color: nil)
        let vars = o.cssVariables(for: .light)
        #expect(vars["--km-user-line-height"] == "2.2")
        #expect(vars["--km-user-letter-spacing"] == "-0.05")
        #expect(vars["--km-user-measure"] == "40ch")
        #expect(vars["--km-user-rule-size"] == nil)
        #expect(vars["--km-user-rule-weight"] == nil)
        #expect(vars["--km-user-rule-color"] == nil)
        #expect(vars["--km-user-body-size"] == "0.7")
        #expect(vars["--km-user-body-weight"] == nil, "weights outside {400,500,600,700} are dropped")
    }

    @Test("List indent maps to a bare --km-user-indent number and clamps to its range")
    func indentMaps() {
        var o = DesignOverrides()
        o.spacing.indentEm = 1.4
        #expect(o.cssVariables(for: .light)["--km-user-indent"] == "1.4")
        o.spacing.indentEm = 9
        #expect(o.cssVariables(for: .light)["--km-user-indent"] == "2")
        o.spacing.indentEm = 0.1
        #expect(o.cssVariables(for: .light)["--km-user-indent"] == "0.5")
        o.spacing.indentEm = nil
        #expect(o.cssVariables(for: .light)["--km-user-indent"] == nil)
    }

    @Test("A spacing value written before indentEm existed still decodes")
    func spacingWithoutIndentDecodes() {
        let old = DesignOverrides.decode(#"{"spacing":{"lineHeight":1.8,"measureCh":72}}"#)
        #expect(old.spacing.lineHeight == 1.8)
        #expect(old.spacing.indentEm == nil)
        #expect(old.cssVariables(for: .light)["--km-user-indent"] == nil)
        #expect(old.cssVariables(for: .light)["--km-user-line-height"] == "1.8")
    }

    @Test("Code tracking maps to its own --km-user-code-letter-spacing channel and clamps")
    func codeLetterSpacingMaps() {
        var o = DesignOverrides()
        o.spacing.letterSpacingEm = 0.02
        #expect(o.cssVariables(for: .light)["--km-user-code-letter-spacing"] == nil,
                "the body 자간 override never reaches the code channel")
        o.spacing.codeLetterSpacingEm = 0.02
        #expect(o.cssVariables(for: .light)["--km-user-code-letter-spacing"] == "0.02")
        o.spacing.codeLetterSpacingEm = -0.4
        #expect(o.cssVariables(for: .light)["--km-user-code-letter-spacing"] == "-0.05")
        o.spacing.codeLetterSpacingEm = nil
        #expect(o.cssVariables(for: .light)["--km-user-code-letter-spacing"] == nil)
    }

    @Test("A spacing value written before codeLetterSpacingEm existed still decodes")
    func spacingWithoutCodeLetterSpacingDecodes() {
        let old = DesignOverrides.decode(#"{"spacing":{"letterSpacingEm":0.01}}"#)
        #expect(old.spacing.letterSpacingEm == 0.01)
        #expect(old.spacing.codeLetterSpacingEm == nil)
        #expect(old.cssVariables(for: .light)["--km-user-code-letter-spacing"] == nil)
        #expect(old.cssVariables(for: .light)["--km-user-letter-spacing"] == "0.01")
    }

    @Test("Code settings map to the code channels: line height, measure, wrap off, quoted font family")
    func codeSettingsMap() {
        var o = DesignOverrides()
        o.spacing.codeLineHeight = 9
        o.spacing.codeMeasureCh = 72
        o.code.wrapsLines = false
        o.code.fontFamily = #"  My "Mono" \ Font  "#
        let vars = o.cssVariables(for: .light)
        #expect(vars["--km-user-code-line-height"] == "2.2")
        #expect(vars["--km-user-code-measure"] == "72ch")
        #expect(vars["--km-code-white-space"] == "pre")
        #expect(vars["--km-font-mono"] == #""My \"Mono\" \\ Font", "# + DesignOverrides.monoFallbackStack)
        #expect(vars["--km-user-line-height"] == nil, "code line height never moves the body")

        o.code = .init(fontFamily: " \n ", wrapsLines: true)
        #expect(o.cssVariables(for: .light)["--km-font-mono"] == nil)
        #expect(o.cssVariables(for: .light)["--km-code-white-space"] == nil)
        #expect(DesignOverrides.decode(#"{"spacing":{}}"#).code == .init(), "values saved before Settings › 코드 still decode")
    }

    @Test("타이포그래피 reset clears everything but the element colors owned by 테마")
    func typographyResetKeepsElementColors() {
        var o = DesignOverrides()
        o.spacing.lineHeight = 1.8
        o.code.wrapsLines = false
        o[element: .h1].sizeScale = 1.2
        o[element: .h1].color = .init(light: "#AA0000", dark: nil)
        o[element: .link].weight = 600
        let kept = o.keepingOnlyElementColors()
        #expect(kept.cssVariables(for: .light) == ["--km-user-h1-color": "#AA0000"])
        #expect(kept.keepingOnlyElementColors() == kept)
        #expect(DesignOverrides().keepingOnlyElementColors().isEmpty)
    }

    @Test("Every spacing field belongs to exactly one section")
    func spacingFieldsPartitionIntoTabs() {
        let body = DesignOverrides.SpacingField.body, code = DesignOverrides.SpacingField.code
        #expect(Set(body).isDisjoint(with: code))
        #expect(Set(body).union(code) == Set(DesignOverrides.SpacingField.allCases))
    }

    @Test("Round trip and corrupt JSON")
    func corruptJSONFallsBackToNoOverrides() {
        var o = DesignOverrides()
        o[element: .h2] = .init(sizeScale: 1.1, weight: 500, color: .init(light: "#000000", dark: "#FFFFFF"))
        #expect(DesignOverrides.decode(o.encoded()) == o)
        #expect(DesignOverrides.decode("{not json") == DesignOverrides())
        #expect(DesignOverrides.decode("") == DesignOverrides())
    }

    @Test("Hex colors round-trip and only ASCII hex is accepted")
    func hexColors() {
        #expect(Color(kissmarkHex: "#AF3029")!.kissmarkHex == "#AF3029")
        #expect(Color(kissmarkHex: "#af3029")!.kissmarkHex == "#AF3029")
        #expect(Color(kissmarkHex: "nope") == nil)
        #expect(Color(kissmarkHex: nil) == nil)
        #expect(DesignOverrides.isHexColor("#ＦＦ００００") == false, "fullwidth hex digits are not a CSS color")
        #expect(Color(kissmarkHex: "#ＦＦ００００") == nil)
    }

    @Test("A JSON value that omits spacing or elements still decodes")
    func missingTopLevelKeysDecode() {
        let elementsOnly = DesignOverrides.decode(#"{"elements":{"h1":{"sizeScale":1.2}}}"#)
        #expect(elementsOnly[element: .h1].sizeScale == 1.2)
        #expect(elementsOnly.spacing == .init())
        #expect(elementsOnly.cssVariables(for: .light) == ["--km-user-h1-size": "1.2"])

        let spacingOnly = DesignOverrides.decode(#"{"spacing":{"lineHeight":1.8}}"#)
        #expect(spacingOnly.spacing.lineHeight == 1.8)
        #expect(spacingOnly.elements.isEmpty)
        #expect(spacingOnly.cssVariables(for: .light) == ["--km-user-line-height": "1.8"])
    }

    @Test("Unknown top-level and element keys still decode and survive a round trip")
    func unknownKeysSurvive() {
        let json = """
        {"spacing":{"lineHeight":1.9},"elements":{"h1":{"sizeScale":1.2},"marquee":{"sizeScale":1.1}},"future":{"a":1}}
        """
        let decoded = DesignOverrides.decode(json)
        #expect(decoded.spacing.lineHeight == 1.9)
        #expect(decoded[element: .h1].sizeScale == 1.2)
        #expect(decoded.elements["marquee"]?.sizeScale == 1.1, "an element key outside ElementKey is kept")
        let roundTripped = DesignOverrides.decode(decoded.encoded())
        #expect(roundTripped == decoded)
        #expect(roundTripped.elements["marquee"]?.sizeScale == 1.1)
    }

    @Test("The slider accepts values between the five reference checkpoints")
    func fineSpacingValuesRemainSelectable() {
        var overrides = DesignOverrides()
        DesignOverrides.SpacingField.lineHeight.set(value: 1.6, in: &overrides.spacing)
        DesignOverrides.SpacingField.paragraphSpacing.set(value: 0.8, in: &overrides.spacing)
        DesignOverrides.SpacingField.indent.set(value: 1.2, in: &overrides.spacing)
        DesignOverrides.SpacingField.letterSpacing.set(value: 0.01, in: &overrides.spacing)
        DesignOverrides.SpacingField.codeLetterSpacing.set(value: -0.03, in: &overrides.spacing)
        DesignOverrides.SpacingField.measure.set(value: 74, in: &overrides.spacing)
        let vars = overrides.cssVariables(for: .light)
        #expect(vars["--km-user-line-height"] == "1.6")
        #expect(vars["--km-user-paragraph-spacing"] == "0.8")
        #expect(vars["--km-user-indent"] == "1.2")
        #expect(vars["--km-user-letter-spacing"] == "0.01")
        #expect(vars["--km-user-code-letter-spacing"] == "-0.03")
        #expect(vars["--km-user-measure"] == "74ch")
    }

    @Test("Returning to the default clears only that field; existing fine values are not migrated")
    func spacingDefaultsAndLegacyValues() {
        var overrides = DesignOverrides.decode(#"{"spacing":{"lineHeight":1.85,"measureCh":72,"paragraphSpacingEm":0.8}}"#)
        #expect(DesignOverrides.SpacingField.lineHeight.effectiveValue(in: overrides.spacing) == 1.85)
        #expect(overrides.cssVariables(for: .light)["--km-user-line-height"] == "1.85")
        DesignOverrides.SpacingField.paragraphSpacing.set(value: 1.05, in: &overrides.spacing)
        #expect(overrides.spacing.paragraphSpacingEm == nil)
        #expect(overrides.spacing.lineHeight == 1.85 && overrides.spacing.measureCh == 72)
        #expect(overrides.cssVariables(for: .light)["--km-user-paragraph-spacing"] == nil)
    }

    @Test("Slider edits use uniform increments and stay within each field's bounds")
    func spacingStepsClampAndRound() {
        var spacing = DesignOverrides.Spacing()
        let line = DesignOverrides.SpacingField.lineHeight
        line.set(value: 1.61, in: &spacing)
        #expect(abs((spacing.lineHeight ?? 0) - 1.6) < 1e-9)
        line.set(value: 1.69, in: &spacing)
        #expect(spacing.lineHeight == nil)
        line.set(value: -10, in: &spacing)
        #expect(spacing.lineHeight == 1.2)
        line.set(value: 10, in: &spacing)
        #expect(spacing.lineHeight == 2.2)
        let code = DesignOverrides.SpacingField.codeLetterSpacing
        code.set(value: 0.012, in: &spacing)
        #expect(abs((spacing.codeLetterSpacingEm ?? 0) - 0.01) < 1e-9)
        #expect(spacing.letterSpacingEm == nil)
    }

    @Test("Halved steps make 1.55 / 0.005 / 0.015 selectable")
    func halvedStepsSelectIntermediateValues() {
        var spacing = DesignOverrides.Spacing()
        DesignOverrides.SpacingField.lineHeight.set(value: 1.55, in: &spacing)
        DesignOverrides.SpacingField.letterSpacing.set(value: 0.005, in: &spacing)
        DesignOverrides.SpacingField.codeLetterSpacing.set(value: 0.015, in: &spacing)
        #expect(spacing.lineHeight == 1.55)
        #expect(spacing.letterSpacingEm == 0.005)
        #expect(spacing.codeLetterSpacingEm == 0.015)
    }

    @Test("Reference checkpoints occupy equal quarters while the middle still means the baseline")
    func checkpointsHaveEqualVisualSpacing() {
        for field in DesignOverrides.SpacingField.allCases {
            let scale = SpacingSliderScale(checkpoints: field.checkpoints)
            for index in field.checkpoints.indices {
                let position = Double(index) / 4
                #expect(abs(scale.position(for: field.checkpoints[index]) - position) < 1e-9)
                #expect(abs(scale.value(at: position) - field.checkpoints[index]) < 1e-9)
            }
            #expect(abs(scale.value(at: 0.5) - field.baseline) < 1e-9)
        }
    }

    @Test("Values between checkpoints round-trip without changing saved numeric values")
    func checkpointScalePreservesIntermediateValues() {
        let measure = SpacingSliderScale(checkpoints: DesignOverrides.SpacingField.measure.checkpoints)
        #expect(abs(measure.value(at: measure.position(for: 74)) - 74) < 1e-9)
        #expect(measure.position(for: -10) == 0)
        #expect(measure.position(for: 999) == 1)
        #expect(measure.value(at: -1) == 40)
        #expect(measure.value(at: 2) == 120)
        let line = SpacingSliderScale(checkpoints: DesignOverrides.SpacingField.lineHeight.checkpoints)
        #expect(abs(line.value(at: line.position(for: 1.85)) - 1.85) < 1e-9)
        #expect(abs(line.value(at: line.position(for: 1.55)) - 1.55) < 1e-9)
    }

    #if os(macOS)
    @Test("Native accessibility moves by one field step, clamps at bounds, and respects disabled state")
    @MainActor
    func nativeSliderStepsByFieldStep() {
        let slider = SpacingStepSlider(frame: NSRect(x: 0, y: 0, width: 500, height: 24))
        slider.scale = SpacingSliderScale(checkpoints: DesignOverrides.SpacingField.lineHeight.checkpoints)
        slider.minValue = 0
        slider.maxValue = 1
        slider.step = 0.05
        slider.numericValue = 1.7
        #expect(slider.accessibilityValue() as? Double == 1.7)
        #expect(slider.accessibilityMinValue() as? Double == 1.2)
        #expect(slider.accessibilityMaxValue() as? Double == 2.2)
        #expect(slider.accessibilityPerformIncrement())
        #expect(abs(slider.numericValue - 1.75) < 1e-9)
        #expect(slider.accessibilityPerformDecrement())
        #expect(slider.accessibilityPerformDecrement())
        #expect(abs(slider.numericValue - 1.65) < 1e-9)
        slider.setAccessibilityValue(NSNumber(value: 1.85))
        #expect(abs(slider.numericValue - 1.85) < 1e-9)
        slider.numericValue = 2.2
        _ = slider.accessibilityPerformIncrement()
        #expect(slider.numericValue == 2.2)
        slider.isEnabled = false
        #expect(!slider.accessibilityPerformDecrement())
        #expect(slider.numericValue == 2.2)
    }
    #elseif os(iOS)
    @Test("Touch thumb matches the checkpoint ruler and accessibility uses bounded numeric steps")
    @MainActor
    func touchSliderMatchesRulerAndSteps() {
        let slider = SpacingTouchSlider(frame: CGRect(x: 0, y: 0, width: 500, height: 24))
        slider.scale = SpacingSliderScale(checkpoints: DesignOverrides.SpacingField.lineHeight.checkpoints)
        slider.step = 0.05
        slider.numericValue = 1.7
        let track = slider.trackRect(forBounds: slider.bounds)
        for position: Float in [0, 0.25, 0.5, 0.75, 1] {
            let thumb = slider.thumbRect(forBounds: slider.bounds, trackRect: track, value: position)
            let inset = KissmarkMetrics.settingsSliderTrackInset
            let expected = inset + (slider.bounds.width - 2 * inset) * CGFloat(position)
            #expect(abs(thumb.midX - expected) < 1e-6)
        }
        slider.accessibilityIncrement()
        #expect(abs(slider.numericValue - 1.75) < 1e-6)
        slider.accessibilityDecrement()
        #expect(abs(slider.numericValue - 1.7) < 1e-6)
        slider.numericValue = 2.2
        slider.accessibilityIncrement()
        #expect(abs(slider.numericValue - 2.2) < 1e-6)
        slider.isEnabled = false
        slider.accessibilityDecrement()
        #expect(abs(slider.numericValue - 2.2) < 1e-6)
    }
    #endif
}
