# Kissmark

AI 에이전트가 만든 Markdown 문서를 열고 편집하고 검토하는 macOS 앱입니다. 일반 Markdown 파일을 그대로 사용하며, 에이전트 연결은 함께 제공하는 MCP 도구를 통해 이뤄집니다.

Kissmark is a macOS app for opening, editing, and reviewing Markdown documents from AI agents. It uses ordinary Markdown files and connects to agents through its bundled MCP helper.

## 설치 / Install

[최신 배포 파일 / Latest release](https://github.com/foxion37/kissmark-releases/releases/latest) · [설치 안내 / Installation](INSTALL.md) · [변경 사항 / Release notes](RELEASE_NOTES.md)

macOS 14 이상을 대상으로 하며 Apple Silicon과 Intel 바이너리를 제공합니다. 실제 실행 검증은 Apple Silicon의 macOS 27.0.1에서 진행했습니다. Intel과 macOS 14의 실제 실행은 미검증입니다. iOS 타깃은 포함하지만 배포하지 않습니다.

The app targets macOS 14 or later and includes Apple Silicon and Intel binaries. Runtime verification was performed on Apple Silicon with macOS 27.0.1. Intel and macOS 14 runtime remain unverified. An iOS target is included but is not distributed.

현재 배포물은 ad-hoc 서명이며 Apple 공증은 없습니다. 처음 실행할 때는 배포 페이지의 보안 승인 안내를 따르세요. 앱 내장 iCloud 폴더 기능은 제외되어 있지만, Finder의 iCloud Drive 폴더를 직접 선택해 사용할 수 있습니다.

Current releases are ad-hoc signed and not notarized by Apple. Follow the release page's security-approval instructions on first launch. The built-in iCloud folder is unavailable, but you can select an iCloud Drive folder through Finder.

## 주요 기능 / Features

- **읽기와 편집:** 폴더 탐색, 읽기·편집 모드, 자동 저장, Markdown 원문 보기.
  - **Read and edit:** folder browsing, read/edit modes, autosave, and Markdown source view.
- **검토와 기록:** 검토 카드, 본문 강조, 코멘트, 최근 문서와 로컬 검색.
  - **Review and history:** review cards, highlights, comments, recent documents, and local search.
- **문서 관리:** 보관 폴더로 복사하고, 선택한 미러 폴더에 한 방향 사본을 저장합니다.
  - **Document management:** copy documents to an archive and maintain one-way copies in selected mirror folders.
- **언어와 모양:** 한국어·영어 UI, 테마, 글자 크기와 간격, 영문 OS 기본·Inter 글꼴 선택. 언어와 영문 글꼴은 다음 실행부터 적용하며 문서 원문은 번역하지 않습니다.
  - **Language and appearance:** Korean/English UI, themes, text size and spacing, and OS-default/Inter English fonts. Language and English-font changes apply on the next launch; document content is never translated.

기록과 검토 정보는 이 Mac의 앱 컨테이너 안에 있는 SQLite에 저장됩니다. 문서 파일의 동기화와 앱의 로컬 검토 기록은 별개입니다.

History and review data are stored in SQLite inside the app container on this Mac. Document-file synchronization does not synchronize the app's local review history.

## 에이전트 연결 / Agent integration

`kissmark-mcp`는 앱의 `Contents/Helpers/kissmark-mcp`에 포함되며, Claude Desktop 확장은 `Contents/Resources/kissmark.mcpb`에 있습니다.

The app bundles `kissmark-mcp` at `Contents/Helpers/kissmark-mcp` and the Claude Desktop extension at `Contents/Resources/kissmark.mcpb`.

| 도구 / Tool | 기능 / Purpose |
|---|---|
| `open_document` | 문서 열기 / Open a document |
| `add_review_points` | 검토 항목 추가 / Add review points |
| `review_status` | 검토 결과 읽기 / Read review status |
| `recent_documents` | 최근 문서 조회 / List recent documents |
| `search_documents` | 기록된 문서 검색 / Search recorded documents |

설정 → 연결에서 후보를 검색하고 필요한 항목만 추가합니다. 설치와 MCP 등록은 CLI 안내를 확인한 뒤 사용자가 직접 승인합니다. 앱의 검색이나 목록 추가만으로 설치하거나 기존 세션을 강제로 바꾸지 않습니다.

Use Settings → Connect to find candidates and add only the connections you want. Installation and MCP registration require the user's explicit CLI approval. Searching or adding a list entry does not install anything or forcibly change existing sessions.

소스 빌드의 MCP 도구를 사용할 때는 `KISSMARK_BUNDLE_ID`와 `KISSMARK_STORE_DIR`로 대상 앱과 기록 저장소를 지정할 수 있습니다.

For a source-build helper, `KISSMARK_BUNDLE_ID` and `KISSMARK_STORE_DIR` can select another app bundle and memory store.

앱을 `/Applications`에 설치했다면 MCP 클라이언트의 실행 명령으로 `/Applications/Kissmark.app/Contents/Helpers/kissmark-mcp`를 사용합니다. 소스와 빌드 안내는 [이 공개 저장소](https://github.com/foxion37/kissmark-releases)에 있습니다.

When installed in `/Applications`, use `/Applications/Kissmark.app/Contents/Helpers/kissmark-mcp` as the MCP client's executable command. Source and build instructions are available in [this public repository](https://github.com/foxion37/kissmark-releases).

## 빌드와 테스트 / Build and test

macOS와 Xcode가 필요합니다. 확인한 개발 환경은 Xcode 27.0, Swift 6.4, Node 24.18.0입니다. 더 오래된 도구 버전에서의 빌드는 보장하지 않습니다.

macOS and Xcode are required. The verified toolchain is Xcode 27.0, Swift 6.4, and Node 24.18.0. Older toolchains are not guaranteed to work.

에디터의 사전 빌드 자원이 포함되어 있으므로 네이티브 앱 빌드에는 Node가 필요하지 않습니다. 아래 명령은 저장소 또는 압축을 푼 소스의 루트에서 실행합니다.

Prebuilt editor assets are included, so the native app build does not require Node. Run these commands from the repository or extracted source root.

```sh
xcodebuild build -project Kissmark.xcodeproj -scheme Kissmark \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/kissmark-build CODE_SIGNING_ALLOWED=NO

xcodebuild test -project Kissmark.xcodeproj -scheme Kissmark \
  -destination 'platform=macOS' -derivedDataPath /tmp/kissmark-tests \
  CODE_SIGNING_ALLOWED=NO -only-testing:KissmarkTests

swift test --package-path mcp
bash mcp/check.sh
swift scripts/check-list-alignment.swift
```

`_editor-build/`의 JavaScript를 수정하거나 에디터 테스트를 실행하려면 잠금 파일에 맞는 의존성을 먼저 설치합니다.

To modify `_editor-build/` JavaScript or run editor tests, install the locked dependencies first.

```sh
npm ci --prefix _editor-build
npm test --prefix _editor-build
bash scripts/build-editor-bundle.sh
```

## 로컬 설치와 패키징 / Local installation and packaging

다음 설치 명령은 `/Applications/Kissmark.app`을 교체합니다. 실행 중인 앱은 정상 종료를 요청하고, 설치 실패 시 이전 앱으로 되돌립니다. 기존 설치본을 교체할지 확인한 뒤 실행하세요.

The following command replaces `/Applications/Kissmark.app`. It requests a graceful quit and rolls back on installation failure. Run it only when you intend to replace the installed copy.

```sh
zsh scripts/install-macos.sh
```

설치본을 교체하지 않고 DMG만 만들려면 위에서 빌드한 앱을 지정합니다. 이 방식은 Git 이력이 없는 소스 스냅샷에서도 사용할 수 있습니다.

To create a DMG without replacing the installed app, provide the app built above. This also works from a source snapshot without Git history.

```sh
bash scripts/package-macos.sh \
  --app /tmp/kissmark-build/Build/Products/Release/Kissmark.app \
  --output-dir /tmp/kissmark-dmg
```

Developer ID를 지정하지 않으면 제한된 권한으로 ad-hoc 서명합니다. 앱과 MCP 도구에 arm64와 x86_64를 포함하며, MIT 및 외부 구성요소 고지문도 패키지에 넣습니다.

Without a Developer ID, packaging uses ad-hoc signing with reduced entitlements. The app and MCP helper include arm64 and x86_64, and the package includes project and third-party notices.

## 라이선스 / License

Kissmark 자체 코드는 [MIT License](LICENSE), `Copyright (c) 2026 foxion37`로 제공합니다. 무료 사용, 수정, 상업적 이용, 재배포와 판매를 허용합니다. 사본이나 상당 부분에는 저작권 고지와 MIT 전문을 유지해야 합니다. 파생 제품의 소스 공개나 별도 로고·화면 크레딧·웹사이트 링크는 의무가 아닙니다.

Original Kissmark code is available under the [MIT License](LICENSE), `Copyright (c) 2026 foxion37`. Free use, modification, commercial use, redistribution, and sale are permitted. Keep the copyright and full MIT notice in copies or substantial portions. Derivatives need not be open source, and no separate logo, on-screen credit, or website link is required.

외부 에디터 구성요소, 폰트와 아이콘은 각자의 라이선스를 유지합니다. [ThirdPartyNotices.txt](Kissmark/Resources/ThirdPartyNotices.txt)와 [폰트 고지문](Kissmark/Resources/Fonts/)을 함께 확인하세요. MIT 적용이 외부 구성요소의 조건을 없애지는 않습니다.

Editor dependencies, fonts, and icons retain their own licenses. See [ThirdPartyNotices.txt](Kissmark/Resources/ThirdPartyNotices.txt) and the [font notices](Kissmark/Resources/Fonts/). The MIT grant does not replace third-party terms.

## 문제 신고 / Issues

[GitHub Issues](https://github.com/foxion37/kissmark-releases/issues)
