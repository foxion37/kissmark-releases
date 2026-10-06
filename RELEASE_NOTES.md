# Kissmark 2.3.2 (18)

## 한국어

이미 열린 문서에 MCP로 검토 항목을 추가했을 때 바로 반영되지 않던 문제를 수정합니다.

### 수정 사항

- 다른 폴더의 문서를 연 뒤 같은 문서에 검토 항목을 추가해도 검토 카드와 본문 강조가 갱신됩니다. 다른 문서를 열었다 돌아올 필요가 없습니다.
- 같은 문서에 연속으로 도착하는 검토 요청도 처리합니다.
- 검토 항목을 반영할 때 열려 있는 편집 세션을 그대로 사용합니다. 편집 모드와 미저장 내용을 버리거나 문서를 디스크에서 강제로 다시 읽지 않습니다.
- 실제 앱과 MCP 도구를 사용하는 격리 회귀 검사를 추가했습니다. 문서 파일을 변경하지 않고 검토 요청이 반영되는지 확인합니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요는 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다. 앱 내장 iCloud 폴더는 제공하지 않지만 Finder의 iCloud Drive 폴더는 직접 선택할 수 있습니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Fixes review points not appearing immediately when an agent adds them through MCP to an already-open document.

### Fixes

- After opening a document in another folder, adding review points to that same document updates the review card and document highlights. Switching to another document and back is no longer required.
- Consecutive review requests for the same document are processed as well.
- Review ingestion keeps the current editing session. It does not discard edit mode or unsaved text, or force a reload from disk.
- Adds an isolated regression check using the real application and MCP helper. It verifies review ingestion without modifying document files.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified. The built-in iCloud folder is unavailable, but an iCloud Drive folder can be selected through Finder.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.
