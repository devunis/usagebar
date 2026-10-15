# Security

## Credential handling

- UsageBar는 API 키 입력을 요구하거나 별도로 저장하지 않습니다.
- Codex 한도는 로컬 `codex app-server` 프로세스를 통해 조회합니다.
- Claude는 기존 CLI OAuth 자격 증명을 읽기 전용으로 사용합니다. 자동 조회는 `LAContext.interactionNotAllowed = true`, `kSecUseAuthenticationUIFail` 외에 `SecKeychainSetUserInteractionAllowed(false)`로 구형 로그인 키체인의 허용창도 차단합니다. 이 프로세스 전역 설정의 변경·조회·복원은 잠금으로 직렬화하며, 차단 설정에 실패하면 읽지 않습니다. 접근 거부나 통신 실패 시 Claude CLI를 자동 실행하지 않고, 이전 값을 유지하며 다음 갱신 주기에 인증 UI 없이 재시도합니다. 사용자가 `다시 연결…`을 직접 누르고 확인한 경우에만 Keychain 인증 UI를 허용합니다. UsageBar가 토큰을 갱신하거나 저장·수정하지 않습니다.
- Claude 자격 증명은 `api.anthropic.com`의 사용량 조회에만 사용합니다. 요청에는 캐시·쿠키를 사용하지 않으며 HTTP 리다이렉트를 따라가지 않습니다. 제한 초기화나 크레딧 소비 요청은 실행하지 않습니다.
- Gemini는 공식 CLI가 이미 저장한 OAuth 자격 증명을 읽기 전용으로 사용합니다.
- 액세스 토큰, 계정 식별자, 응답 원문을 로그나 UserDefaults, 소스 코드 또는 Git에 기록하지 않습니다.
- 브라우저 쿠키를 읽지 않습니다.

## Local code signing

- 로컬 설치에는 사용자 키체인의 `UsageBar Local Signing` 자체 서명 인증서와 동일한 앱 식별자 `com.usagebar.app`을 재사용합니다. 임시 서명처럼 빌드별 코드 해시에만 의존하지 않아 macOS가 기존 허용을 업데이트에서도 식별할 수 있습니다.
- `scripts/setup-local-signing.sh`는 사용자가 명시적으로 실행할 때만 인증서를 생성하며 기존 인증서가 있으면 재생성하지 않습니다. 생성한 개인 키는 추출 불가로 가져오며 서명 접근은 `/usr/bin/codesign`에만 허용합니다. 시스템/사용자 신뢰 루트나 Claude 자격 증명 ACL은 변경하지 않습니다.
- 생성 중 임시 개인 키/PKCS#12 파일은 소유자만 접근 가능한 임시 폴더에 두고 종료 시 제거합니다. 키와 인증서를 저장소에 넣지 않습니다.
- 로컬 서명 실패 시 임시 서명으로 대체하지 않습니다. CI는 별도의 명시적 설정으로만 임시 서명을 사용하며, 해당 앱은 허용 유지가 필요한 로컬 설치용이 아닙니다.

## Reporting

공개 이슈에 액세스 토큰이나 계정 식별자를 올리지 마세요. 저장소 소유자에게 GitHub Security Advisory로 비공개 제보해 주세요.
