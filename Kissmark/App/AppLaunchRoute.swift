import Foundation

enum AppLaunchRoute: Equatable {
    case folderSelection
    case readerFixture
    case editorFixture

    static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebug: Bool = {
            #if DEBUG
            true
            #else
            false
            #endif
        }()
    ) -> Self {
        guard isDebug,
              isUITestGate(arguments: arguments, environment: environment),
              let index = arguments.firstIndex(of: "-ui-test-state"),
              arguments.indices.contains(index + 1),
              ["reader-fixture", "editor-fixture"].contains(arguments[index + 1]) else {
            return .folderSelection
        }
        if arguments[index + 1] == "editor-fixture" { return .editorFixture }
        return .readerFixture
    }

    /// Accept either process environment or `-KISSMARK_UI_TEST 1` launch argument.
    /// XCTest on macOS sometimes fails to forward `launchEnvironment` alone.
    static func isUITestGate(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment["KISSMARK_UI_TEST"] == "1" { return true }
        if let index = arguments.firstIndex(of: "-KISSMARK_UI_TEST"),
           arguments.indices.contains(index + 1),
           arguments[index + 1] == "1" {
            return true
        }
        return false
    }
}
