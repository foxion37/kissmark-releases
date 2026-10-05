//
//  KissmarkApp.swift
//  Kissmark
//
//  Created by 김성규 on 7/14/26.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct KissmarkApp: App {
    @State private var updateController = KissmarkUpdateController()
    @State private var mirror = MirrorCoordinator()

    init() {
        KissmarkLocalization.captureLaunchPreferences()
        KissmarkType.registerFontsIfNeeded()
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            AppRootView()
                .environment(updateController)
                .environment(mirror)
                .frame(
                    minWidth: KissmarkWindowChrome.minimumContentSize.width,
                    minHeight: KissmarkWindowChrome.minimumContentSize.height
                )
                #if DEBUG
                .onAppear {
                    if AppLaunchRoute.isUITestGate() {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                #endif
        }
        .windowStyle(.titleBar)
        .defaultSize(width: launchWindowSize.width, height: launchWindowSize.height)
        .windowResizability(.contentMinSize)
        .commands { openCommands }

        // A plain `Window` scene instead of `Settings`: SwiftUI's Settings scene
        // ignores `windowResizability`, reports a finite content maximum, and
        // re-fits itself on every tab switch, so the user could not resize it.
        // ⌘, is restored by the `.appSettings` command below.
        Window(String.kissmarkLocalized("설정"), id: KissmarkWindowChrome.settingsWindowID) {
            KissmarkSettingsView()
                .environment(updateController)
                .environment(mirror)
        }
        .defaultSize(
            width: KissmarkMetrics.settingsDefaultSize.width,
            height: KissmarkMetrics.settingsDefaultSize.height
        )
        .windowResizability(.contentMinSize)
        #else
        WindowGroup {
            AppRootView()
                .environment(updateController)
                .environment(mirror)
        }
        .commands { openCommands }
        #endif
    }

    #if os(macOS)
    /// The window opens at the Document reading column width; the Folder browser
    /// re-applies the same size once its window exists, clamped to the screen.
    private var launchWindowSize: CGSize { KissmarkWindowChrome.launchContentSize() }
    #endif

    @CommandsBuilder
    private var openCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String.kissmarkLocalized("열기")) {
                NotificationCenter.default.post(name: .kissmarkChooseFolder, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])
        }
        CommandGroup(before: .toolbar) {
            Button(String.kissmarkLocalized("새로고침")) {
                NotificationCenter.default.post(name: .kissmarkReload, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
        #if os(macOS)
        CommandGroup(after: .undoRedo) {
            Button(String.kissmarkLocalized("텍스트 정리")) {
                NotificationCenter.default.post(name: .kissmarkCleanTypography, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .appSettings) {
            KissmarkSettingsCommand()
        }
        #endif
    }
}

#if os(macOS)
/// Replaces the standard Settings item so ⌘, opens the Kissmark settings window.
private struct KissmarkSettingsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(String.kissmarkLocalized("설정…")) {
            openWindow(id: KissmarkWindowChrome.settingsWindowID)
        }
        .keyboardShortcut(",", modifiers: [.command])
    }
}
#endif
