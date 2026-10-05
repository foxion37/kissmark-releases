# Kissmark 2.3.1 (17)

## 한국어

이번 버전은 소스 공개와 라이선스 고지를 위한 배포입니다. 2.3.0의 문서 읽기·편집, 한국어·영어 UI, 검토 기록과 MCP 연결 동작을 유지합니다.

### 변경 사항

- 앱, 에디터, MCP 도구의 최종 소스와 테스트, 빌드 파일을 함께 제공합니다. [공개 저장소](https://github.com/foxion37/kissmark-releases)에서 소스를 확인하고 직접 빌드할 수 있습니다.
- Kissmark 자체 코드에 표준 MIT License를 적용합니다. 무료 사용, 수정, 상업적 이용, 재배포와 판매를 허용하며, 사본이나 상당 부분에는 저작권 고지와 MIT 전문을 유지해야 합니다. 파생 제품의 소스 공개나 별도 화면 크레딧은 요구하지 않습니다.
- 앱 패키지에 프로젝트 MIT 전문과 에디터 의존성, 아이콘, 폰트의 라이선스 고지문을 포함합니다. 외부 구성요소에는 각자의 라이선스가 계속 적용됩니다.
- 내장 Claude Desktop 확장에도 MIT 전문과 라이선스 선언을 포함합니다.
- 한국어·영어 README와 설치 안내를 제공합니다. 기본 패키징은 유료 서명 없이 ad-hoc 서명을 사용합니다.

### 설치와 지원 범위

[설치 안내](INSTALL.md)를 따라 기존 앱을 교체하세요. 문서와 설정을 초기화할 필요는 없습니다.

Apple Silicon·Intel 바이너리를 포함하지만 Intel, macOS 14, iOS 실제 실행은 미검증입니다. Apple 공증과 앱 내장 iCloud 폴더는 제공하지 않습니다. Finder에서 iCloud Drive 폴더를 직접 선택할 수 있습니다. 외부 에이전트의 GUI 설치창에서 최종 승인하는 과정은 검수 범위에 포함하지 않습니다.

정확한 소스 커밋, 파일 체크섬과 검수 범위는 같은 릴리스의 `release-manifest.json`, `SHA256SUMS`, `validation.json`에 기록합니다.

## English

This release prepares Kissmark's source distribution and license notices. It preserves the document reading/editing, Korean/English UI, review history, and MCP connection behavior of 2.3.0.

### Changes

- Final application, editor, and MCP helper source are provided with tests and build files. Use the [public repository](https://github.com/foxion37/kissmark-releases) to inspect and build the source.
- Original Kissmark code uses the standard MIT License. Free use, modification, commercial use, redistribution, and sale are permitted. Keep the copyright and full MIT notice in copies or substantial portions. Derivatives do not need to be open source or provide separate on-screen credits.
- The app package includes the project MIT text and license notices for editor dependencies, icons, and fonts. Third-party components retain their own licenses.
- The bundled Claude Desktop extension includes the MIT text and a license declaration.
- Korean/English README and installation instructions are included. Default packaging uses ad-hoc signing without a paid signing identity.

### Installation and support

Follow the [installation guide](INSTALL.md) to replace the existing app. Documents and settings do not need to be reset.

Apple Silicon and Intel binaries are included, but Intel, macOS 14, and iOS runtime remain unverified. Apple notarization and the built-in iCloud folder are unavailable. An iCloud Drive folder can be selected through Finder. Final approval in external agents' graphical installers is outside the verification scope.

The same release's `release-manifest.json`, `SHA256SUMS`, and `validation.json` record the exact source commit, artifact checksums, and verification scope.
