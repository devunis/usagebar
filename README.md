# UsageBar

OpenAI, Claude(Anthropic), Gemini API 사용량을 한눈에 보여주는 네이티브 macOS 메뉴바 앱입니다.

## 현재 지원 범위

| 공급자 | 조회 데이터 | 인증 |
| --- | --- | --- |
| OpenAI | 최근 30일 입력/출력 토큰, 모델 요청 수 | 조직 Admin API 키 |
| Anthropic | 최근 30일 입력/캐시/출력 토큰 | 조직 Admin API 키 |
| Gemini API | 최근 30일 Cloud Monitoring 토큰/요청 지표 | `gcloud` ADC + 프로젝트 ID |

> ChatGPT, Claude.ai, Gemini 웹 구독의 개인 메시지 잔여량은 공식 공개 API가 아닙니다. UsageBar는 브라우저 쿠키를 훔치거나 비공개 엔드포인트를 호출하지 않고, 공식 API/Cloud 지표만 사용합니다.

## 요구 사항

- macOS 14 Sonoma 이상
- Swift 6 / Xcode Command Line Tools
- Gemini를 사용할 경우 [Google Cloud CLI](https://cloud.google.com/sdk/docs/install)

Command Line Tools의 Swift와 SDK 버전이 맞지 않는 환경에서는 전체 Xcode를 선택해 주세요.

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 실행

```bash
swift run UsageBar
```

설치 가능한 `.app` 번들을 만들려면:

```bash
./scripts/build-app.sh release
open UsageBar.app
```

앱을 메뉴바에서 연 뒤 **설정**에서:

1. OpenAI 조직 설정에서 발급한 Admin API 키를 입력합니다.
2. Anthropic Console에서 발급한 Admin API 키를 입력합니다.
3. Gemini는 아래 명령을 한 번 실행하고 Google Cloud 프로젝트 ID를 입력합니다.

```bash
gcloud auth application-default login
```

API 키는 macOS Keychain에 저장됩니다. Gemini OAuth 액세스 토큰은 저장하지 않고 필요할 때 `gcloud`에서 가져옵니다.

## 개발

```bash
swift test
swift build
```

구조:

- `Models`: 공통 사용량 모델
- `Services`: 공급자별 공식 API/Cloud Monitoring 어댑터
- `Store`: 상태, 자동 새로고침, 설정
- `Views`: 메뉴바 및 설정 UI

## 알려진 제한

- OpenAI와 Anthropic 조직 Usage API는 일반 프로젝트 키가 아닌 Admin 키가 필요합니다.
- Gemini Cloud Monitoring 지표는 수 분 늦게 표시될 수 있으며, 계정 티어별 지표 이름 변경의 영향을 받을 수 있습니다.
- Anthropic Usage API가 요청 수를 제공하지 않는 응답에서는 요청 수가 `0`으로 표시됩니다.
- 이 초기 버전은 개발자용 ad-hoc 서명입니다. 다른 Mac에 배포하려면 Apple Developer ID 서명과 notarization이 필요합니다.

## 보안

취약점 제보와 자격 증명 처리 원칙은 [SECURITY.md](SECURITY.md)를 확인해 주세요.

## 라이선스

MIT
