import SwiftUI

/// A reversible, piecewise-linear scale: five semantic values sit at equal quarters.
/// Numeric values and numeric step sizes remain unchanged.
nonisolated struct SpacingSliderScale {
    let checkpoints: [Double]

    init(checkpoints: [Double]) {
        precondition(checkpoints.count == 5)
        precondition(zip(checkpoints, checkpoints.dropFirst()).allSatisfy { $0.0 < $0.1 })
        self.checkpoints = checkpoints
    }

    func position(for value: Double) -> Double {
        if value <= checkpoints[0] { return 0 }
        if value >= checkpoints[4] { return 1 }
        for index in 0..<4 where value <= checkpoints[index + 1] {
            let fraction = (value - checkpoints[index]) / (checkpoints[index + 1] - checkpoints[index])
            return (Double(index) + fraction) / 4
        }
        return 0.5
    }

    func value(at position: Double) -> Double {
        guard position.isFinite else { return checkpoints[2] }
        let scaled = min(max(position, 0), 1) * 4
        let index = min(Int(scaled), 3)
        return checkpoints[index] + (checkpoints[index + 1] - checkpoints[index]) * (scaled - Double(index))
    }
}

/// Native thumb over one joined track and five small, equally spaced reference markers.
/// The scale preserves true numeric values; laying out or updating never writes settings.
struct SettingsSpacingSlider: View {
    @Binding var value: Double
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DocumentTheme.storageKey) private var themeID = DocumentTheme.system.rawValue
    @AppStorage(ThemeAccentOverrides.storageKey) private var accentJSON = ""
    let step: Double
    let checkpoints: [Double]
    let label: String

    private var tint: Color {
        let theme = DocumentTheme(rawValue: themeID) ?? .system
        let accent = ThemeAccentOverrides.decode(accentJSON).accent(for: theme, scheme: colorScheme)
        return DocumentThemeResolver.chromeAccentHex(theme: theme, scheme: colorScheme, override: accent)
            .flatMap { Color(kissmarkHex: $0) } ?? .accentColor
    }

    var body: some View {
        let scale = SpacingSliderScale(checkpoints: checkpoints)
        let position = scale.position(for: value)
        return NativeSpacingSlider(value: $value, scale: scale, step: step, label: label)
            .frame(height: KissmarkMetrics.settingsSliderHeight)
            .background {
                GeometryReader { geometry in
                    let inset = KissmarkMetrics.settingsSliderTrackInset
                    let width = max(0, geometry.size.width - inset * 2)
                    let track = SpacingSliderTrack().path(in: CGRect(origin: .zero, size: geometry.size))
                    track
                        .fill(Color.primary.opacity(KissmarkMetrics.settingsSliderTrackBaseOpacity))
                        .overlay(alignment: .leading) {
                            track
                                .fill(tint.opacity(KissmarkMetrics.settingsSliderTrackFillOpacity))
                                .mask(alignment: .leading) {
                                    Rectangle().frame(width: inset + width * position)
                                }
                        }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }

}

/// One filled silhouette: overlapping subpaths never stack translucent colours.
private struct SpacingSliderTrack: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = KissmarkMetrics.settingsSliderTrackInset
        let width = max(0, rect.width - inset * 2)
        let height = KissmarkMetrics.settingsSliderTrackHeight
        var path = Path(roundedRect: CGRect(
            x: rect.minX + inset, y: rect.midY - height / 2,
            width: width, height: height
        ), cornerRadius: height / 2)
        let markerWidth = KissmarkMetrics.settingsSliderCheckpointWidth
        let markerHeight = KissmarkMetrics.settingsSliderCheckpointHeight
        for index in 0..<5 {
            path.addRoundedRect(in: CGRect(
                x: rect.minX + inset + width * CGFloat(index) / 4 - markerWidth / 2,
                y: rect.midY - markerHeight / 2,
                width: markerWidth, height: markerHeight
            ), cornerSize: CGSize(width: markerHeight / 2, height: markerHeight / 2))
        }
        return path
    }
}

#if os(macOS)
import AppKit

private struct NativeSpacingSlider: NSViewRepresentable {
    @Binding var value: Double
    let scale: SpacingSliderScale
    let step: Double
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(value: $value, scale: scale) }

    func makeNSView(context: Context) -> SpacingStepSlider {
        let slider = SpacingStepSlider()
        slider.cell = SpacingTrackCell()
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        return slider
    }

    func updateNSView(_ slider: SpacingStepSlider, context: Context) {
        context.coordinator.scale = scale
        slider.scale = scale
        slider.minValue = 0
        slider.maxValue = 1
        slider.step = step
        slider.isEnabled = context.environment.isEnabled
        slider.setAccessibilityLabel(label)
        let position = scale.position(for: value)
        if slider.doubleValue != position { slider.doubleValue = position }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        var scale: SpacingSliderScale
        init(value: Binding<Double>, scale: SpacingSliderScale) {
            self.value = value
            self.scale = scale
        }

        /// The setter quantizes; show the snapped value the model actually holds.
        @objc func changed(_ sender: NSSlider) {
            value.wrappedValue = scale.value(at: sender.doubleValue)
            sender.doubleValue = scale.position(for: value.wrappedValue)
        }
    }
}

/// Native knob and drag; arrows and accessibility increment by `step`, not the
/// control's default 1% (which the quantizing binding would snap straight back).
final class SpacingStepSlider: NSSlider {
    var step = 1.0
    var scale = SpacingSliderScale(checkpoints: [0, 0.25, 0.5, 0.75, 1])
    var numericValue: Double {
        get { scale.value(at: doubleValue) }
        set { doubleValue = scale.position(for: newValue) }
    }


    private func nudge(_ direction: Double) -> Bool {
        guard isEnabled else { return false }
        numericValue = min(max(numericValue + direction * step, scale.checkpoints[0]), scale.checkpoints[4])
        sendAction(action, to: target)
        return true
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow?, .downArrow?: _ = nudge(-1)
        case .rightArrow?, .upArrow?: _ = nudge(1)
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool { nudge(1) }
    override func accessibilityPerformDecrement() -> Bool { nudge(-1) }

    override func accessibilityValue() -> Any? { numericValue }
    override func accessibilityMinValue() -> Any? { scale.checkpoints[0] }
    override func accessibilityMaxValue() -> Any? { scale.checkpoints[4] }
    override func setAccessibilityValue(_ value: Any?) {
        guard isEnabled, let number = value as? NSNumber, number.doubleValue.isFinite else { return }
        numericValue = number.doubleValue
        sendAction(action, to: target)
    }
}

/// SwiftUI paints the joined silhouette; AppKit still owns the thumb and input.
private final class SpacingTrackCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {}
}
#else
import UIKit

private struct NativeSpacingSlider: UIViewRepresentable {
    @Binding var value: Double
    let scale: SpacingSliderScale
    let step: Double
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeUIView(context: Context) -> SpacingTouchSlider {
        let slider = SpacingTouchSlider()
        slider.minimumTrackTintColor = .clear
        slider.maximumTrackTintColor = .clear
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return slider
    }

    func updateUIView(_ slider: SpacingTouchSlider, context: Context) {
        slider.scale = scale
        slider.step = step
        slider.isEnabled = context.environment.isEnabled
        slider.accessibilityLabel = label
        slider.numericValue = value
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }

        @objc func changed(_ sender: SpacingTouchSlider) {
            value.wrappedValue = sender.numericValue
            sender.numericValue = value.wrappedValue
        }
    }
}

final class SpacingTouchSlider: UISlider {
    var step = 1.0
    var scale = SpacingSliderScale(checkpoints: [0, 0.25, 0.5, 0.75, 1])
    var numericValue: Double {
        get { scale.value(at: Double(value)) }
        set { value = Float(scale.position(for: newValue)) }
    }

    override func thumbRect(forBounds bounds: CGRect, trackRect rect: CGRect, value: Float) -> CGRect {
        let thumb = super.thumbRect(forBounds: bounds, trackRect: rect, value: value)
        let inset = KissmarkMetrics.settingsSliderTrackInset
        let centre = bounds.minX + inset + (bounds.width - 2 * inset) * CGFloat(value)
        return thumb.offsetBy(dx: centre - thumb.midX, dy: 0)
    }

    override var accessibilityValue: String? {
        get { String(numericValue) }
        set { super.accessibilityValue = newValue }
    }

    private func nudge(_ direction: Double) {
        guard isEnabled else { return }
        numericValue = min(max(numericValue + direction * step, scale.checkpoints[0]), scale.checkpoints[4])
        sendActions(for: .valueChanged)
    }

    override func accessibilityIncrement() { nudge(1) }
    override func accessibilityDecrement() { nudge(-1) }
}
#endif
