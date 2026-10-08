# Kissmark 2.3.16 (32)

## 한국어

코드 블록에 언어 이름과 복사 버튼이 있는 머리글을 달고, VS Code처럼 문법 색을 입힙니다.

### 변경 사항

- 코드 블록 위에 머리글 줄을 추가했습니다. 왼쪽에 언어 이름, 오른쪽에 **복사** 버튼이 늘 보이며, 복사하면 잠시 **복사됨**으로 바뀝니다. 편집 모드에서는 언어 이름을 눌러 언어를 바꿀 수 있습니다. 언어가 없는 블록은 읽기 모드에서 이름을 비워 둡니다.
- 코드 색을 VS Code 기본 테마(라이트: Light+, 다크: Dark+)의 토큰 색으로 바꿨습니다. 키워드, 제어문, 함수, 타입과 클래스, 변수와 속성, 상수, 문자열, 숫자, 정규식, 주석, HTML 태그와 속성을 구분해 칠합니다. 연산자와 괄호는 본문 글자색을 씁니다.
- 코드 블록의 기본 글자색을 본문 글자색으로 바꿨습니다. 인라인 코드 색은 그대로입니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Code blocks get a header with the language name and a Copy button, and VS Code-style syntax colors.

### Changes

- A header bar sits above each code block: the language name on the left and an always-visible **Copy** button on the right, which briefly reads **Copied**. In Edit Mode the language name opens the language picker. Blocks without a language leave the name empty in Read Mode.
- Code colors follow VS Code's default themes (Light+ in light, Dark+ in dark): keywords, control flow, functions, types and classes, variables and properties, constants, strings, numbers, regular expressions, comments, and HTML tags and attributes. Operators and brackets use the text color.
- Code block text now defaults to the body text color; inline code keeps its color.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.15 (31)

## 한국어

설정의 디자인을 타이포그래피로 바꾸고, 코드 설정을 그 안에 합치고, 요소 색을 테마로 옮깁니다.

### 변경 사항

- **설정 → 디자인**의 이름을 **타이포그래피**로 바꿨습니다. 글자 크기, 정렬, 글꼴, 간격, 요소별 크기와 굵기를 여기서 조절합니다.
- 2.3.14의 **설정 → 코드**를 타이포그래피 안의 **코드** 섹션으로 합쳤습니다. 설정 상단 항목은 다시 여섯 개입니다.
- 요소별 색(본문, 제목, 코드, 인용, 표, 링크, 구분선)은 **설정 → 테마 → 요소 색**으로 옮겼습니다. 라이트와 다크에 따로 저장하며 모든 테마에 공통으로 적용합니다. 요소마다 **테마 색으로** 버튼이 있습니다.
- 타이포그래피의 **모두 초기화**는 요소 색을 유지합니다. 저장된 값은 형식이 바뀌지 않아 그대로 이어집니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Settings › 디자인 becomes Typography, absorbs the code settings, and element colors move to Theme.

### Changes

- **Settings → Design** is now **Typography**: text size, alignment, fonts, spacing, and per-element size and weight.
- The 2.3.14 **Settings → Code** pane is now the **Code** section inside Typography; the settings header is back to six items.
- Per-element colors moved to **Settings → Theme → Element Colors**, saved separately for Light and Dark and shared by every theme, each with **Use Theme Color**.
- Typography's **Reset All** keeps element colors. Saved values keep their format and carry over.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.14 (30)

## 한국어

코드 블록을 다시 선택하고 복사할 수 있게 하고, 코드 전용 설정을 추가합니다.

### 수정 사항

- 코드 블록을 마우스로 끌어 선택하고 복사할 수 있습니다. 문서를 누르는 순간 본문이 아래로 밀려 선택이 잡히지 않던 문제와 선택 영역이 코드 배경에 가려 보이지 않던 문제를 고쳤습니다. 읽기 모드에서는 코드 안에 커서와 현재 줄 강조를 표시하지 않습니다.
- 라이트 테마에서 코드 블록의 줄 번호가 검은 배경에 회색 글씨로 보이던 문제를 고쳤습니다. 코드 색은 이제 선택한 테마 색을 따릅니다.
- 긴 코드 줄은 블록 너비에서 자동으로 줄을 바꿉니다. 양끝 맞춤 문서에서도 코드 공백이 늘어나지 않습니다.

### 새 기능

- **설정 → 코드**를 추가했습니다. 코드 글꼴(설치된 고정폭 글꼴 목록, 이름 직접 입력, 서체 관리자 열기), 행간, 자간, 장폭, 긴 줄 자동 줄바꿈을 조절합니다. 이전 디자인 탭의 코드 자간은 이 탭으로 옮겼으며 저장된 값은 유지됩니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Code blocks can be selected and copied again, and code gets its own settings pane.

### Fixes

- Dragging across a code block selects it and Copy works. Pressing in the document no longer pushes the page down under the pointer, and the selection is no longer hidden behind the code background. Read Mode shows no caret or active line inside code.
- In light themes the code block's current line number no longer shows gray on a black band; code colors follow the selected theme.
- Long code lines wrap at the block width, and justified documents no longer stretch spaces in code.

### New

- **Settings → 코드** sets the code font (installed monospaced fonts, a typed font name, or Font Book), line height, letter spacing, measure and long-line wrapping. Code letter spacing moved here from 디자인; saved values are kept.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.13 (29)

## 한국어

설정 섹션 머리글 색이 테마를 따라가게 합니다.

### 수정 사항

- 설정 섹션 머리글(본문, 글꼴, 간격 등)이 고정된 액센트 색 대신 선택한 테마의 포인트 색을 따릅니다. 시스템 테마에서는 시스템 액센트를 유지합니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

The settings section headers now follow the selected theme's accent.

### Fixes

- Settings section headers (본문, 글꼴, 간격…) use the chrome palette's accent instead of a fixed tint, so they recolor with the selected theme. 시스템 keeps the platform accent.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.12 (28)

## 한국어

설정 헤더의 섹션 알약을 하나의 캡슐로 묶고 동작 버튼을 정리합니다.

### 수정 사항

- 섹션 알약(일반…미러)을 하나의 캡슐 박스로 묶었습니다. 알약 높이는 닫기 아이콘 버튼과 같은 28pt입니다.
- 초기화·저장 버튼을 없애고 닫기만 오른쪽에 남겼습니다. 설정은 바뀔 때마다 적용되므로 별도 저장 동작이 필요 없습니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Groups the settings section pills into one capsule and trims the actions.

### Fixes

- The section pills (일반…미러) sit inside a single outlined capsule, and their height matches the 닫기 icon button's 28pt.
- 초기화 and 저장 are gone; only 닫기 remains on the right. Settings apply live, so no separate save action is needed.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.11 (27)

## 한국어

연결 탭 배치를 다듬고 설정 섹션 머리글을 본문과 구분합니다.

### 수정 사항

- 진단의 상태(확인 필요 / 응답 확인됨)를 뱃지로 연결 검색 기능 옆에 표시하고, 검색 버튼을 같은 행 오른쪽 끝으로 옮겼습니다.
- 연결 탭의 첫 행에서 안내 텍스트는 왼쪽, 연결 검색·CLI 설치 버튼은 오른쪽 끝에 나란히 배치했습니다. CLI 설치…의 줄임표를 뗐습니다.
- 설정 섹션 머리글(본문, 글꼴, 간격 등)을 작고 굵은 포인트 색으로 바꿔 본문 텍스트와 구분됩니다.
- 설정 행 박스의 안쪽 여백을 다시 넓혔습니다(세로 16pt, 가로 20pt).

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Refines the connections pane layout and distinguishes settings section headers.

### Fixes

- The diagnostics state (확인 필요 / 응답 확인됨) is a small badge next to the 연결 검색 기능 label, and 검색 moves to the row's trailing end.
- The connections pane's first row puts the empty-state text on the left with 연결 검색 · CLI 설치 side by side on the right; CLI 설치… drops its ellipsis.
- Settings section headers (본문, 글꼴, 간격…) render small, semibold and in the accent color so they read as labels, not body text.
- Settings row boxes widen their inner insets again (16pt vertical, 20pt horizontal).

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.10 (26)

## 한국어

설정 헤더의 항목과 동작 버튼 모양을 다듬습니다.

### 수정 사항

- 설정 섹션 항목(일반…미러) 각각이 알약 버튼을 가집니다. 항목 사이 여백이 넓어졌고, 선택한 알약만 유리 채움 위에 살짝 어두운 선택색이 얹힙니다.
- 닫기·초기화·저장이 텍스트에서 아이콘 원형 버튼으로 바뀌었습니다(닫기 ✕, 초기화 ↺, 저장 ✓). 앱 툴바의 아이콘 버튼과 같은 모양입니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Refines the settings header's section pills and action buttons.

### Fixes

- Each settings section item (일반…미러) is its own capsule button now, spaced further apart; only the selected pill carries the glass fill plus a soft ink wash.
- 닫기 · 초기화 · 저장 move from text to icon circle buttons (x / rotate-ccw / check) matching the app's toolbar buttons.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.9 (25)

## 한국어

헤더 폴더 버튼의 아이콘 대비를 높입니다.

### 수정 사항

- 헤더 폴더 버튼의 폴더 아이콘과 양쪽 꺽쇠가 흐린 회색으로 그려져 유리 채움 위에서 잘 보이지 않았습니다. 이제 라벨과 같은 잉크 색으로 그려집니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Raises the contrast of the header folder button's glyphs.

### Fixes

- The folder icon and the up-down switch chevron in the header folder button were drawn in a muted gray that vanished against the glass fill; they render in the label's ink now.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.8 (24)

## 한국어

본문 글자 크기 체계를 다시 잡고, 설정 헤더와 폴더 버튼 모양을 다듬습니다.

### 수정 사항

- 글자 크기 다섯 단계를 12/13/14/18/21px로 다시 정했습니다. 중간(기본)은 이전 기본보다 4px 작아지고, 크게는 이전 기본 크기(18px), 아주 크게는 이전 크기(21px)입니다. 24px 단계는 사라졌습니다.
- 문서 정보와 검토 카드의 글자 크기를 본문과 같게 통일했습니다. 이전에는 본문의 80%로 표시됐습니다. Frontmatter 박스는 종전처럼 한 단계 작게 유지합니다.
- 헤더의 폴더 버튼을 알약 모양으로 바꿨습니다(유리 채움과 테두리 모두).
- 설정 헤더 박스도 알약 모양으로 바꾸고, 섹션 항목은 왼쪽에, 닫기·초기화·저장 세 버튼을 오른쪽 끝에 배치했습니다. 초기화는 한 번 되물은 뒤 화면 모드·테마·글자 크기·간격·언어·글꼴 등 설정을 기본값으로 되돌립니다(폴더·문서·검토 기록은 그대로).

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Re-cuts the body text size ladder and refines the settings header and folder button shapes.

### Fixes

- The five body sizes are now 12/13/14/18/21px at the wide viewport: 중간 (기본) drops 4px from the old 18px default, 크게 takes the old default's 18px, 아주 크게 takes the old 크게's 21px, and the 24px step is gone.
- The 문서 정보 and 검토 cards render at the body size instead of 80% of it. The Frontmatter box keeps its smaller metadata step.
- The header folder button is a full capsule (glass fill and outline).
- The settings header box is a capsule too, with section labels on the left and 닫기 · 초기화 · 저장 on the trailing end. 초기화 asks once and resets the settings keys — appearance, theme, text size, spacing, language, fonts and update checks — never folders, documents or review history.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.7 (23)

## 한국어

설정 창 헤더의 잔움직임을 없애고 행 여백을 넓힙니다.

### 수정 사항

- 설정 헤더를 고정된 박스와 텍스트로 바꾸고, 선택한 항목에만 글래스 캡슐이 부드럽게 이동합니다. 시스템 탭 캡슐의 선택 모핑(항목 폭이 달라 클릭마다 헤더가 흔들리던 것)을 대체합니다. 글래스모피즘은 그대로 유지합니다.
- 설정 창이 처음 열릴 때 화면 전체 크기로 열리던 문제를 고쳤습니다. 680×600 기본 크기로 가운데 정렬해 다시 열립니다.
- 설정의 모든 행(박스) 안쪽 여백을 넓혀 텍스트가 박스에 바짝 붙지 않습니다. 세로 12pt, 가로 16pt.
- 일반 탭에서 텍스트 정리가 머리글과 항목으로 두 번 반복되던 것을 AI 슬롭 검사(머리글) / 슬롭 제거(항목)로 바꿨습니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Calms the Settings header and widens row padding.

### Fixes

- The settings header is now a static box of labels with a glass capsule that glides behind the selected section. This replaces the system tab capsule whose selection morph (labels of different widths) read as the whole header wobbling on every click. The glassmorphism stays.
- A fresh settings window no longer opens at full screen; it opens centered at the 680×600 default.
- Every settings row (box) applies shared inner insets — 12pt vertical, 16pt horizontal — so text no longer hugs the box edges.
- 일반's duplicated 텍스트 정리 header/toggle become AI 슬롭 검사 (header) / 슬롭 제거 (item).

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.6 (22)

## 한국어

설정 창의 주기적인 버벅임을 없애고 여백을 넓힙니다.

### 수정 사항

- 연결 탭은 5초마다 검색 결과를 확인하는데, 내용이 바뀌지 않아도 화면 전체를 다시 그려 설정 창이 주기적으로 버벅였습니다. 이제 변화가 있을 때만 다시 그립니다.
- 설정 행 사이 간격을 8→12pt로, 행 안 내용 블록 사이를 12→16pt로, 디자인 탭 슬라이더 행 안쪽을 4→8pt로 넓혔습니다.
- 연결 탭 진단 행의 꺽쇠를 12pt에서 16pt로 키웠습니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Removes the periodic stutter in the Settings window and widens spacing.

### Fixes

- The connections pane polled discovery every 5 seconds and re-rendered the whole Form even when nothing changed; identical snapshots are skipped now.
- Settings row gaps grow from 8 to 12pt, in-row content blocks from 12 to 16pt, and the design tab's slider rows from 4 to 8pt.
- The diagnostics row chevron grows from 12 to 16pt.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.


# Kissmark 2.3.5 (21)

## 한국어

연결 탭의 진단 공개 행을 고칩니다.

### 수정 사항

- 진단 행의 꺽쇠가 라벨 왼쪽에 있던 것을 오른쪽 끝으로 옮겼습니다. 펼칠 때 꺽쇠가 아래로 회전합니다.
- 진단을 펼쳤을 때 아래 내용 글자가 진단 라벨보다 커 보이던 문제를 고쳤습니다. 라벨을 본문 크기로 명시해 내용과 같은 위계를 가집니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Fixes the diagnostics disclosure row in the 연결 tab.

### Fixes

- The diagnostics row's chevron sat left of the label; it is on the trailing edge now and rotates downward when expanded.
- Expanding 진단 showed body text larger than the label itself; the label is explicitly body-sized, so it holds the same hierarchy as the rows it reveals.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.

# Kissmark 2.3.4 (20)

## 한국어

설정 창의 디자인 문제를 고칩니다.

### 수정 사항

- 설정 창 위 탭 메뉴를 누를 때마다 헤더가 흔들리던 문제를 고쳤습니다. 탭마다 창 제목이 따로 바뀌던 것이 원인이었고, 이제 설정 창 제목은 어떤 탭에서도 설정으로 유지됩니다.
- 연결 탭의 행이 다른 탭과 다른 선택 표시를 함께 그리던 문제를 고쳤습니다. 디자인 탭과 같은 공개 행 구성으로 돌렸습니다.
- 연결 검색 창이 다른 설정 화면과 다른 여백과 행 구성을 쓰던 문제를 고쳤습니다. CLI 설치 창과 같은 grouped Form 스타일로 바꿨습니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Fixes design problems in the Settings window.

### Fixes

- The header no longer wobbles each time a settings tab is clicked. Every tab used to swap the window title, which re-laid out the macOS 26 glass header; the Settings window title now stays 설정 on every tab.
- The rows in the 연결 tab drew a second, custom selection state next to the system disclosure treatment; they are plain disclosure rows like the 디자인 tab again.
- The 연결 검색 sheet used different margins and row construction from every other pane; it is a grouped Form now, matching the CLI 설치 sheet.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.

# Kissmark 2.3.3 (19)

## 한국어

문서 경로를 에이전트에게 바로 넘기는 경로 복사 버튼과, 폴더를 옮겨 다닐 때 최근 목록과 폴더 권한·iCloud 폴더를 안정적으로 유지하는 수정을 담습니다.

### 새 기능

- 툴바에 경로 복사 버튼이 생겼습니다. 보관과 설정 사이에 있고, 열린 문서의 파일 경로를 클립보드에 일반 텍스트와 파일 URL로 동시에 넣습니다. 에이전트 대화창에 바로 붙여 넣을 수 있고, 연결된 에이전트는 MCP의 recent_documents로도 같은 경로를 가져올 수 있습니다. 문서가 없으면 비활성입니다.
- 설정 › 디자인에 글꼴 섹션이 생겼습니다. 영문 글꼴 선택이 여기로 이동했고, 한글은 Pretendard, 코드는 Jetendard로 표시됩니다. 설정 › 일반의 언어 섹션은 앱 언어 선택만 보여줍니다.

### 수정 사항

- 폴더가 바뀌거나 에이전트가 다른 폴더의 문서를 열어도 최근 목록이 사라지지 않고, 열린 문서가 항상 최상위에 기록됩니다. iCloud에서 아직 내려받지 못한 문서처럼 열기가 실패해도 최근에 올라와 나중에 다시 열 수 있습니다.
- 현재 문서의 폴더 열기…(부모 폴더 권한)을 같은 문서에서 다시 요청하면 패널이 다시 나타납니다. 한 번 나타나지 않은 뒤 버튼이 죽어 있던 경우를 막습니다.
- 폴더 선택 패널이 한 번 사라지지 못한 뒤 버튼이 계속 무반응이던 경우를 자가 복구합니다.
- iCloud 폴더의 북마크가 stale로 표시되면 저장된 폴더를 버리지 않고 새 북마크로 갱신합니다. 재실행 시 폴더가 다른 폴더로 조용히 바뀌던 경우를 막습니다.
- 설정 창이 자체 680pt 고정 상한을 두지 않습니다. 넓은 창에서 항목 배경과 스크롤바가 여백 한가운데 끊기지 않습니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 앱만 교체하세요. 문서, 설정, 검토 기록이나 에이전트 연결 설정을 초기화할 필요가 없습니다.

프로젝트 MIT License와 외부 구성요소 고지는 그대로 유지합니다. 배포물은 Apple Silicon·Intel 바이너리를 포함하는 ad-hoc 서명 앱이며 Apple 공증은 없습니다. Intel, macOS 14, iOS 실제 실행과 외부 GUI 설치창의 최종 승인은 미검증입니다. 앱 내장 iCloud 폴더는 제공하지 않지만 Finder의 iCloud Drive 폴더는 직접 선택할 수 있습니다.

정확한 소스 커밋, 체크섬과 검수 범위는 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

Adds a copy-path toolbar action that hands a document path straight to an agent, plus fixes that keep the recents list, folder prompts, and the iCloud folder stable while switching folders.

### New

- A 경로 복사 (copy path) toolbar button sits between Archive and Settings. With a Document open it copies the file path to the clipboard as both plain text and a file URL — paste it straight into an agent chat; a connected agent can also read the same path through the MCP recent_documents tool. It is disabled without an open Document.
- Settings › 디자인 gains a 글꼴 (fonts) section that owns the English font choice; Hangul stays Pretendard and code stays Jetendard. The language section in Settings › 일반 now shows only the app language.

### Fixes

- The recents list survives folder changes and agent opens, and every open — including a failed load such as a not-yet-downloaded iCloud copy — records the Document at the top so it can be retried later.
- Repeating 현재 문서의 폴더 열기… (the parent-folder grant) for the same Document presents the panel again instead of leaving a lost prompt behind.
- The Folder picker un-sticks itself when a previous presentation failed silently.
- A stale iCloud folder bookmark is re-persisted fresh instead of dropping the saved Folder, which used to switch the next launch to a fallback folder.
- Settings no longer imposes its own 680pt width cap, so row washes and the scrollbar do not stop short of the margins on wider windows.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace only the app. Documents, settings, review history, and agent connection configuration do not need to be reset.

The project MIT License and third-party notices are unchanged. The distribution includes Apple Silicon/Intel binaries with ad-hoc signing and no Apple notarization. Intel, macOS 14, iOS runtime and final approval in external graphical installers remain unverified. The built-in iCloud folder is unavailable, but an iCloud Drive folder can be selected through Finder.

`release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.

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
