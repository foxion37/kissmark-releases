import SwiftUI

struct EditorFixtureScreen: View {
    let onClose: () -> Void
    @State private var session: DocumentSession?

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    DocumentEditorScreen(session: session)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                KissmarkToolbarCluster(items: fixtureItems(for: session))
                            }
                        }
                } else {
                    ProgressView()
                        .task { session = try? loadFixtureSession() }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor-fixture-container")
    }

    /// Fixture chrome: mode toggle + close only; the real actions live in `FolderBrowserWorkspace`.
    private func fixtureItems(for session: DocumentSession) -> [KissmarkToolbarCluster.Item] {
        let isEditing = session.mode == .edit
        return [
            .init(
                id: "kissmark.document.mode",
                title: isEditing ? "잠금" : "잠금 해제",
                icon: .lucide(isEditing ? .lockOpen : .lock),
                active: isEditing,
                opticalScale: KissmarkMetrics.toolbarLockOpticalScale,
                accessibilityIdentifier: "document-mode-button",
                accessibilityValue: isEditing ? "edit" : "read"
            ) {
                session.setMode(session.mode == .read ? .edit : .read)
            },
            .init(
                id: "kissmark.document.close",
                title: "닫기",
                icon: .lucide(.x),
                opticalScale: KissmarkMetrics.toolbarCloseOpticalScale,
                accessibilityIdentifier: "document-close-button",
                action: onClose
            ),
        ]
    }

    private func loadFixtureSession() throws -> DocumentSession {
        guard let fixture = Bundle.main.url(forResource: "agent-output", withExtension: "md") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("KissmarkEditorFixture-\(UUID().uuidString).md")
        let snapshot = try DocumentFileStore().saveAs(
            String(contentsOf: fixture, encoding: .utf8),
            to: destination
        )
        return DocumentSession(snapshot: snapshot)
    }
}
