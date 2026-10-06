import SwiftUI
import UniformTypeIdentifiers

/// Settings › 미러: Mirror Targets, last result per target, and a manual full send.
struct MirrorSettingsView: View {
    @Environment(MirrorCoordinator.self) private var mirror
    @State private var isPickerPresented = false
    @State private var sendMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: KissmarkMetrics.settingsRowGap) {
                    if mirror.targets.isEmpty {
                        Text("아직 미러 폴더가 없습니다.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("폴더 추가…") { isPickerPresented = true }
                        .accessibilityIdentifier("settings-mirror-add")
                }
                ForEach(mirror.targets) { target in
                    row(target)
                }
            } header: {
                Text("미러")
            } footer: {
                Text("문서를 잠그거나 닫거나 바꿀 때 선택한 폴더에 사본을 씁니다. 삭제는 따라가지 않습니다.")
            }

            Section {
                Button("지금 모두 보내기") { sendAll() }
                    .disabled(mirror.targets.isEmpty)
                    .accessibilityIdentifier("settings-mirror-send-all")
                if let sendMessage {
                    Text(sendMessage).font(KissmarkType.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("현재 Folder의 모든 Markdown 문서를 미러 폴더에 다시 씁니다.")
            }
        }
        .formStyle(.grouped)
        .kissmarkSettingsNavigationTitle("미러")
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        sendMessage = String.kissmarkLocalized("폴더를 추가하지 못했습니다.")
                        return
                    }
                    do {
                        _ = try mirror.add(fromPicked: url)
                    } catch {
                        sendMessage = String.kissmarkLocalized("폴더를 추가하지 못했습니다.")
                    }
                case .failure:
                    sendMessage = String.kissmarkLocalized("폴더를 추가하지 못했습니다.")
                }
            },
            // Cancelling is not a failure: no message.
            onCancellation: {}
        )
    }

    private func row(_ target: MirrorTarget) -> some View {
        LabeledContent {
            Button("제거", role: .destructive) { mirror.remove(target.id) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings-mirror-remove-\(target.id.uuidString)")
        } label: {
            VStack(alignment: .leading) {
                Text(target.displayName)
                Text(mirror.folderURL(of: target.id)?.path ?? String.kissmarkLocalized("폴더를 다시 고르세요"))
                    .font(KissmarkType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let result = mirror.lastResults[target.id] {
                    Text(resultText(result))
                        .font(KissmarkType.caption)
                        .foregroundStyle(result.isFailure ? Color.red : Color.secondary)
                }
            }
        }
        .accessibilityIdentifier("settings-mirror-row-\(target.id.uuidString)")
    }

    private func resultText(_ result: MirrorResult) -> String {
        func shown(_ date: Date) -> String {
            date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(KissmarkLocalization.locale))
        }
        return switch result {
        case .ok(let date):
            String.kissmarkLocalized("마지막으로 쓴 시각 \(shown(date))")
        case .failed(let message, let date):
            String.kissmarkLocalized("실패 \(shown(date)): \(message)")
        }
    }

    private func sendAll() {
        guard let folder = try? FolderBookmarks().load(.main) else {
            sendMessage = String.kissmarkLocalized("먼저 Folder를 여세요.")
            return
        }
        let summary = mirror.mirrorAll(from: folder)
        // Every target's current result, not only the newly failing ones: a target that was
        // already failing and failed again must not read as sent.
        let failing = mirror.targets.filter { mirror.lastResults[$0.id]?.isFailure == true }
        var lines = [failing.isEmpty
            ? String.kissmarkLocalized("모든 미러 폴더에 보냈습니다.")
            : String.kissmarkLocalized("일부 미러 폴더에 쓰지 못했습니다: \(failing.map(\.displayName).joined(separator: ", "))")]
        if !summary.unreadable.isEmpty {
            lines.append(String.kissmarkLocalized("읽지 못한 문서 \(summary.unreadable.count)개"))
        }
        sendMessage = lines.joined(separator: "\n")
    }
}
