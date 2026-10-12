# Security

## Credential handling

- UsageBar는 API 키 입력을 요구하거나 별도로 저장하지 않습니다.
- Codex 한도는 로컬 `codex app-server` 프로세스를 통해 조회합니다.
- Claude는 기존 CLI OAuth 자격 증명을 읽기 전용으로 사용합니다. 자동 조회의 Keychain 읽기는 `LAContext.interactionNotAllowed = true` 및 `kSecUseAuthenticationUIFail`을 함께 지정해 인증창을 차단하며, 거부되면 기존 `claude -p /usage`로 일반 한도만 조회합니다. 사용자가 `추가 정보 연결…`을 직접 누르고 확인한 경우에만 Keychain 인증 UI를 허용합니다. UsageBar가 토큰을 갱신하거나 저장·수정하지 않습니다.
- Claude 자격 증명은 `api.anthropic.com`의 사용량 조회에만 사용합니다. 요청에는 캐시·쿠키를 사용하지 않으며 HTTP 리다이렉트를 따라가지 않습니다. 제한 초기화나 크레딧 소비 요청은 실행하지 않습니다.
- Gemini는 공식 CLI가 이미 저장한 OAuth 자격 증명을 읽기 전용으로 사용합니다.
- 액세스 토큰, 계정 식별자, 응답 원문을 로그나 UserDefaults, 소스 코드 또는 Git에 기록하지 않습니다.
- 브라우저 쿠키를 읽지 않습니다.

## Reporting

공개 이슈에 액세스 토큰이나 계정 식별자를 올리지 마세요. 저장소 소유자에게 GitHub Security Advisory로 비공개 제보해 주세요.
