# Security

## Credential handling

- UsageBar는 API 키 입력을 요구하거나 별도로 저장하지 않습니다.
- Codex 한도는 로컬 `codex app-server` 프로세스를 통해 조회합니다.
- Claude와 Gemini는 각 공식 CLI가 이미 저장한 OAuth 자격 증명을 읽기 전용으로 사용합니다.
- 액세스 토큰, 계정 식별자, 응답 원문을 로그나 UserDefaults, 소스 코드 또는 Git에 기록하지 않습니다.
- 브라우저 쿠키를 읽지 않습니다.

## Reporting

공개 이슈에 액세스 토큰이나 계정 식별자를 올리지 마세요. 저장소 소유자에게 GitHub Security Advisory로 비공개 제보해 주세요.
