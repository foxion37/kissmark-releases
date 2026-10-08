import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Settings › 디자인 › 코드. Code font, line height, tracking, measure and line
/// wrapping, stored in `DesignOverrides` (`spacing` code fields + `code`); every
/// change applies to the open Document immediately. One `Section` inside the
/// 디자인 `Form`.
struct CodeSettingsSection: View {
    @AppStorage(DesignOverrides.storageKey) private var designJSON = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var installedFamilies: [String] = []
    @State private var customFamily = ""

    private var overrides: DesignOverrides { DesignOverrides.decode(designJSON) }

    private func update(_ change: (inout DesignOverrides) -> Void) {
        var next = overrides
        change(&next)
        designJSON = next.encoded()
    }

    private var isDefault: Bool {
        overrides.code == .init()
            && DesignOverrides.SpacingField.code.allSatisfy { $0.value(in: overrides.spacing) == nil }
    }

    var body: some View {
        Section {
            Picker("코드 글꼴", selection: Binding(
                get: { overrides.code.fontFamily ?? "" },
                set: { family in update { $0.code.fontFamily = family.isEmpty ? nil : family } }
            )) {
                Text("기본 (Jetendard)").tag("")
                if let current = overrides.code.fontFamily, !installedFamilies.contains(current) {
                    Text(current).tag(current)
                }
                ForEach(installedFamilies, id: \.self) { Text($0).tag($0) }
            }
            .accessibilityIdentifier("settings-code-font")
            TextField("직접 입력", text: $customFamily, prompt: Text("글꼴 이름"))
                .onSubmit {
                    let family = customFamily.trimmingCharacters(in: .whitespacesAndNewlines)
                    update { $0.code.fontFamily = family.isEmpty ? nil : family }
                }
                .accessibilityIdentifier("settings-code-font-custom")
            #if os(macOS)
            Button("글꼴 추가…") { Self.openFontBook() }
                .accessibilityIdentifier("settings-code-font-add")
            #endif
            ForEach(DesignOverrides.SpacingField.code) { field in DesignSpacingRow(field: field) }
            Toggle("긴 줄 자동 줄바꿈", isOn: Binding(
                get: { overrides.code.wrapsLines ?? true },
                set: { wraps in update { $0.code.wrapsLines = wraps ? nil : false } }
            ))
            .accessibilityIdentifier("settings-code-wrap")
            Button("코드 기본값으로") {
                withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) {
                    update { o in
                        o.code = .init()
                        DesignOverrides.SpacingField.code.forEach { $0.clear(in: &o.spacing) }
                    }
                }
                customFamily = ""
            }
            .accessibilityIdentifier("settings-code-reset")
            .disabled(isDefault)
        } header: {
            KissmarkSettingsSectionHeader(title: "코드")
        } footer: {
            Text("글꼴 목록은 설치된 고정폭 글꼴이며, 다른 글꼴은 이름을 직접 입력해 씁니다. 없는 글자는 Jetendard로 표시됩니다. 행간, 장폭, 자동 줄바꿈은 코드 블록에, 글꼴과 자간은 인라인 코드와 코드 보기에도 적용됩니다. 장폭의 기본은 본문 폭이며, 자동 줄바꿈을 끄면 긴 줄은 가로로 스크롤합니다.")
        }
        .kissmarkSettingsRowInsets()
        .onAppear {
            installedFamilies = Self.monospacedFamilies()
            customFamily = overrides.code.fontFamily ?? ""
        }
    }

    /// Installed fixed-pitch families, read on each appearance so fonts added
    /// meanwhile show up.
    private static func monospacedFamilies() -> [String] {
        #if os(macOS)
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter {
            manager.font(withFamily: $0, traits: [], weight: 5, size: 12)?.isFixedPitch == true
        }
        #else
        return UIFont.familyNames.sorted().filter { family in
            UIFont.fontNames(forFamilyName: family).first
                .flatMap { UIFont(name: $0, size: 12) }?
                .fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true
        }
        #endif
    }

    #if os(macOS)
    private static func openFontBook() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.FontBook") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    #endif
}
