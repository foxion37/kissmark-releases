# Kissmark

AI 에이전트가 만든 Markdown 문서를 보여 주는 macOS 앱입니다. 터미널이나 다른 앱에서 일하는 에이전트가 MCP로 문서를 이 창에 띄우고, 사용자가 확인해야 할 곳을 표시합니다. Kissmark는 한 번 보여 준 문서를 기억해 두었다가 다시 찾아 주고, 쓸수록 기록이 쌓입니다.

평범한 Markdown 폴더 뷰어와 편집기로도 쓸 수 있습니다. 파일은 늘 디스크에 있는 원본 그대로이고, Kissmark는 사용자가 편집할 때만 파일에 씁니다.

## 할 수 있는 일

- **폴더 탐색**: 고른 폴더의 Markdown 문서를 트리로 봅니다. iCloud Drive, Google Drive 같은 Finder 폴더도 됩니다.
- **읽기와 편집**: 기본은 읽기 모드입니다. 잠금을 풀면 문서 모양 그대로 편집하고, 잠시 멈추면 자동 저장합니다. 원문 Markdown은 코드 보기로 봅니다.
- **에이전트 연결 (MCP)**: 에이전트가 문서를 열고, 확인할 곳을 지정하고, 사용자가 무엇을 확인했는지 읽어 갑니다.
- **검토 카드**: 문서 위 검토 카드에 확인할 곳을 모아 보여 주고, 본문의 해당 문장에 색을 칠합니다. 에이전트가 지정하지 않으면 결정, 경고, 실패, 할 일 같은 부분을 Kissmark가 직접 찾습니다. 동그라미를 눌러 확인하고, 코멘트를 남기고, 검토 완료로 마무리합니다.
- **최근**: 사이드바 맨 위에 최근에 본 문서가 폴더와 상관없이 나옵니다. 에이전트가 연 문서는 로봇 아이콘으로 표시합니다.
- **새로고침 (⌘R)**: 에이전트가 파일을 고친 뒤 창 전체를 디스크에서 다시 불러옵니다. 저장하지 않은 편집이 있으면 새로고침하지 않습니다.
- **테마와 디자인**: Catppuccin, Dracula, Nord 등 고정 테마, 포인트 컬러, 글자 크기와 간격을 설정에서 바꿉니다.
- **보관과 미러**: 문서를 Obsidian 같은 보관 폴더에 복사합니다. 미러 폴더를 정하면 문서를 잠그거나 닫을 때 그 폴더에 한 방향 사본을 둡니다.

## 요구 사항

- macOS 14 이상
- Apple Silicon과 Intel Mac 모두 지원

## 설치

1. [Releases](https://github.com/foxion37/kissmark-releases/releases/latest)에서 `Kissmark-<버전>.dmg`를 받습니다.
2. DMG를 열고 `Kissmark`를 `Applications` 폴더로 끌어다 놓습니다.
3. 터미널에서 다음 명령을 한 번 실행합니다.

   ```sh
   xattr -dr com.apple.quarantine /Applications/Kissmark.app
   ```

   이 빌드는 Apple 개발자 인증서로 서명하지 않았습니다. 그래서 macOS가 처음 실행을 막습니다. 위 명령은 인터넷에서 받은 파일에 붙는 격리 표시를 지웁니다. 앱과 에이전트 연결 도구가 함께 풀립니다.

   터미널을 쓰지 않으려면 앱을 한 번 연 뒤, **시스템 설정 › 개인정보 보호 및 보안**에서 Kissmark의 **그래도 열기**를 누릅니다. 다만 이렇게 하면 앱만 풀리고 에이전트 연결 도구는 막힐 수 있으니, MCP를 쓸 거라면 위 명령을 실행하세요.

4. Kissmark를 열고 **열기**(⌘O)로 폴더나 Markdown 파일을 고릅니다.

## 에이전트 연결 (MCP)

연결 도구 `kissmark-mcp`는 앱 안에 들어 있습니다.

```
/Applications/Kissmark.app/Contents/Helpers/kissmark-mcp
```

**Claude Code**

```sh
claude mcp add kissmark -- /Applications/Kissmark.app/Contents/Helpers/kissmark-mcp
```

**Codex** (`~/.codex/config.toml`)

```toml
[mcp_servers.kissmark]
command = "/Applications/Kissmark.app/Contents/Helpers/kissmark-mcp"
```

**Claude Desktop, Cursor 등 JSON 설정을 쓰는 앱**

```json
{
  "mcpServers": {
    "kissmark": {
      "command": "/Applications/Kissmark.app/Contents/Helpers/kissmark-mcp"
    }
  }
}
```

연결하면 에이전트가 다음 도구를 씁니다.

| 도구 | 하는 일 |
|---|---|
| `open_document(path, points?)` | `.md` 문서를 Kissmark에 띄웁니다. 확인할 곳을 함께 넘길 수 있습니다. 앱이 꺼져 있으면 실행합니다. |
| `add_review_points(path, points)` | 이미 띄운 문서에 확인할 곳을 더합니다. |
| `review_status(path)` | 사용자가 확인한 곳, 남긴 코멘트, 검토 완료 시각을 읽습니다. |
| `recent_documents(limit?, project?, agent?)` | 최근에 보여 준 문서 목록을 가져옵니다. |
| `search_documents(query, ...)` | 보여 준 문서를 제목과 본문으로 찾습니다. 한글도 됩니다. |

에이전트에게 이렇게 말하면 됩니다: "보고서를 Kissmark로 열어 줘", "어제 본 배포 계획 다시 보여 줘", "내가 검토한 결과 확인해".

## 데이터와 개인정보

- 문서 기록(메모리)은 이 Mac에만 저장됩니다: `~/Library/Containers/com.singandmong.kissmark/Data/Library/Application Support/Kissmark/`
- 기록에는 연 문서의 경로, 제목, 본문 사본(검색용), 검토 포인트와 코멘트, 문서를 연 에이전트와 프로젝트 경로가 들어갑니다.
- 네트워크는 새 버전 확인(GitHub) 한 곳에만 씁니다. 설정의 **업데이트 확인**을 끄면 그마저 쓰지 않습니다.
- 기록을 지우려면 앱을 끄고 위 `Kissmark` 폴더를 지웁니다.

## 이 빌드의 제한

- 서명하지 않은 빌드라 설치할 때 위 3단계가 필요합니다.
- 앱에 내장된 iCloud Kissmark 폴더 기능은 이 빌드에서 쓸 수 없습니다. iCloud Drive 안의 폴더를 직접 고르면 됩니다.
- iPhone과 iPad용은 배포하지 않습니다.

## 삭제

```sh
rm -rf /Applications/Kissmark.app
rm -rf ~/Library/Containers/com.singandmong.kissmark
```

MCP 설정에 추가한 `kissmark` 항목도 지웁니다.

## 문제 신고

[Issues](https://github.com/foxion37/kissmark-releases/issues)에 남겨 주세요.
