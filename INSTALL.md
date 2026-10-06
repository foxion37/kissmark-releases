# Kissmark 2.3.2 (18): 설치 / Installation

## 한국어

### 다운로드와 설치

1. [2.3.2 릴리스](https://github.com/foxion37/kissmark-releases/releases/tag/v2.3.2)에서 DMG와 `SHA256SUMS`를 받습니다. 파일 이름에 있는 짧은 커밋 값과 전체 소스 커밋은 같은 릴리스의 `release-manifest.json`으로 확인할 수 있습니다.
2. 다운로드한 폴더에서 아래 명령으로 DMG의 체크섬을 확인합니다. 결과가 `OK`일 때만 계속합니다. 소스 ZIP도 받았다면 같은 명령으로 함께 검사합니다.
3. 기존 Kissmark에서 편집을 저장하고 앱을 종료합니다. DMG를 열고 `Kissmark.app`을 Applications로 복사합니다. 기존 설치본이 있다면 앱만 교체하며, 문서나 설정을 초기화할 필요는 없습니다.
4. Applications의 Kissmark를 실행합니다. 설정 → 일반에서 한국어·영어와 영문 글꼴을 선택할 수 있습니다. 언어와 영문 글꼴 변경은 다음 실행부터 적용됩니다.

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
```

### 첫 실행의 보안 승인

이 배포물은 **ad-hoc 서명이며 Apple 공증은 없습니다.** macOS가 실행을 막으면 다운로드 출처와 체크섬을 확인한 뒤 시스템 설정 → 개인정보 보호 및 보안에서 해당 앱의 실행을 승인합니다. macOS 보안 기능 전체를 끄지 마세요.

신뢰한 앱을 명령으로 승인해야 하는 경우에만 다음을 실행합니다. 이 명령은 Kissmark와 내장 MCP 실행 파일의 격리 표시를 제거합니다. 다른 앱이나 다운로드 폴더 전체에 적용하지 마세요.

```sh
xattr -dr com.apple.quarantine /Applications/Kissmark.app
```

### MCP 연결

설정 → 연결에서 이 Mac의 후보를 검색하고 필요한 항목만 추가합니다. CLI 설치나 MCP 등록은 표시된 명령과 대상 에이전트, 사용자 공통(global) 또는 프로젝트 범위를 확인한 뒤 직접 승인합니다. 검색과 목록 추가만으로 설치하거나 기존 세션을 강제로 바꾸지 않습니다.

직접 MCP 클라이언트를 설정할 때의 실행 파일은 다음과 같습니다. Claude Desktop 확장 파일은 `/Applications/Kissmark.app/Contents/Resources/kissmark.mcpb`에 있습니다.

```text
/Applications/Kissmark.app/Contents/Helpers/kissmark-mcp
```

### 지원 범위와 고지

- macOS 14 이상용 arm64·x86_64 바이너리를 제공합니다. 실제 실행 검수 범위는 릴리스의 `validation.json`에 기록합니다. Intel, macOS 14, iOS에서의 실제 실행은 미검증입니다.
- 앱 내장 iCloud 폴더는 제공하지 않습니다. Finder의 iCloud Drive 폴더를 직접 선택할 수는 있습니다.
- 앱의 `Contents/Resources/Kissmark-LICENSE.txt`에 MIT 전문이 있습니다. `ThirdPartyNotices.txt`, 폰트 OFL 고지문과 `Jetendard-Upstream-Notices.txt`도 함께 포함됩니다.
- 소스와 빌드 안내: [README](README.md). 이번 변경: [릴리스 노트](RELEASE_NOTES.md).

## English

### Download and install

1. Download the DMG and `SHA256SUMS` from the [2.3.2 release](https://github.com/foxion37/kissmark-releases/releases/tag/v2.3.2). The release's `release-manifest.json` records the full source commit corresponding to the short commit in the filename.
2. Run the command below in the download directory to verify the DMG. Continue only when it reports `OK`. If you also downloaded the source ZIP, the same command checks it too.
3. Save edits and quit the existing Kissmark app. Open the DMG and copy `Kissmark.app` to Applications. Replace only the existing app; documents and settings do not need to be reset.
4. Launch Kissmark from Applications. Settings → General lets you choose Korean/English and an English font. Language and English-font changes take effect on the next launch.

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
```

### First-launch security approval

This distribution is **ad-hoc signed and not notarized by Apple.** If macOS blocks it, check the download source and checksum, then approve the app in System Settings → Privacy & Security. Do not disable macOS security globally.

Only if you need to approve this trusted app from the command line, run the following. It removes quarantine attributes from Kissmark and its bundled MCP executable. Do not apply it to other apps or your entire Downloads folder.

```sh
xattr -dr com.apple.quarantine /Applications/Kissmark.app
```

### MCP integration

Use Settings → Connect to search this Mac and add only the candidates you need. Explicitly approve CLI installation or MCP registration after checking the displayed command, agent, and global or project scope. Searching and adding a list entry do not install anything or forcibly modify existing sessions.

For manual MCP client setup, use the executable below. The Claude Desktop extension is at `/Applications/Kissmark.app/Contents/Resources/kissmark.mcpb`.

```text
/Applications/Kissmark.app/Contents/Helpers/kissmark-mcp
```

### Support and notices

- The app includes arm64/x86_64 binaries targeting macOS 14 or later. The release's `validation.json` records the runtime checks actually performed. Intel, macOS 14, and iOS runtime remain unverified.
- The built-in iCloud folder is unavailable. You can select an iCloud Drive folder through Finder.
- The full MIT license is at `Contents/Resources/Kissmark-LICENSE.txt`. The app also includes `ThirdPartyNotices.txt`, font OFL notices, and `Jetendard-Upstream-Notices.txt`.
- Source and build instructions: [README](README.md). Changes in this version: [release notes](RELEASE_NOTES.md).
