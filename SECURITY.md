# Security

## Credential handling

- OpenAI와 Anthropic Admin 키는 macOS Keychain에만 저장합니다.
- 키를 로그, UserDefaults, 소스 코드 또는 Git에 기록하지 않습니다.
- Gemini 액세스 토큰은 `gcloud auth application-default print-access-token`으로 필요할 때 가져오며 영구 저장하지 않습니다.
- UsageBar는 웹 브라우저 쿠키나 비공개 소비자 API를 읽지 않습니다.

## Reporting

공개 이슈에 API 키, 액세스 토큰 또는 계정 식별자를 올리지 마세요. 저장소 소유자에게 GitHub Security Advisory로 비공개 제보해 주세요.
