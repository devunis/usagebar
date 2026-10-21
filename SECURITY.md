# Security

## Credential handling

- UsageBar는 API 키 입력을 요구하거나 별도로 저장하지 않습니다.
- 설치 안내의 자동 감지는 실행 파일 존재 여부만 검사합니다. 설치 명령어는 화면 표시/명시적 복사만 가능하며, 터미널 열기는 명령어를 주입하거나 실행하지 않습니다. 원격 설치 스크립트를 앱에서 다운로드/실행하거나 Homebrew·CLI를 자동 설치하지 않습니다. 공식 문서 링크와 설치 스크립트 URL은 고정된 공급자 주소이며 로그인은 공급자의 공식 CLI에서 사용자가 직접 진행합니다.
- Codex 한도는 로컬 `codex app-server` 프로세스를 통해 조회합니다.
- Claude는 공식 CLI의 구조화된 `get_usage` 요청으로 먼저 조회합니다. 성공하면 UsageBar는 Claude 자격 증명을 읽지 않습니다. 조회용 CLI는 전용 폴더에서 `--safe-mode`, `--strict-mcp-config`, 도구/훅/Remote Control/세션 저장 비활성화 상태로 실행합니다. 사용자 프롬프트나 모델 턴 없이 initialize/get_usage만 보내고, `skip_behaviors: true`로 대화 내역 분석을 생략합니다. 응답 크기·시간 제한과 취소 처리가 있으며, 해당 자식 프로세스만 종료합니다. 원시 stderr는 저장/출력하지 않습니다. Claude Code 자체가 로그인과 토큰 갱신을 관리하며, 그 프로세스에 적용되는 macOS 인증 요구는 UsageBar가 우회하지 않습니다.
- CLI가 없거나 조회가 실패할 때만 기존 OAuth 자격 증명을 읽기 전용으로 시도합니다. 대체 조회는 `LAContext.interactionNotAllowed = true`, `kSecUseAuthenticationUIFail`, `SecKeychainSetUserInteractionAllowed(false)`로 구형 키체인 허용창까지 차단합니다. 전역 정책의 변경·조회·복원은 잠금으로 직렬화하며 차단 설정에 실패하면 읽지 않습니다. 사용자가 추가 정보 연결/다시 연결을 직접 누르고 확인한 경우에만 UsageBar의 키체인 인증 UI를 허용합니다. UsageBar는 토큰을 저장·수정하거나 갱신 토큰을 교환하지 않습니다.
- Claude 자격 증명은 `api.anthropic.com`의 사용량 조회에만 사용합니다. 요청에는 캐시·쿠키를 사용하지 않으며 HTTP 리다이렉트를 따라가지 않습니다. 제한 초기화나 크레딧 소비 요청은 실행하지 않습니다.
- Gemini는 공식 CLI가 이미 저장한 OAuth 자격 증명을 읽기 전용으로 사용합니다.
- 액세스 토큰, 계정 식별자, 응답 원문을 로그나 UserDefaults, 소스 코드 또는 Git에 기록하지 않습니다.
- 브라우저 쿠키를 읽지 않습니다.
- 잠자기 해제/세션 복귀/네트워크 재연결 후 자동 재시도도 동일한 인증 UI 차단 정책을 사용합니다. 만료된 액세스 토큰은 전송하지 않으며, Claude Code가 소유한 갱신 토큰을 교환하거나 수정하지 않습니다. `--diagnose-claude-usage`도 비대화형 읽기 전용이며 사용률과 상태 외의 인증/계정 정보는 출력하지 않습니다.

## Local code signing

Windows Preview는 CLI 전용이며 macOS 키체인 경로를 사용하지 않습니다. Windows Credential Manager·자격 증명 파일·브라우저 쿠키를 직접 읽지 않고, API 키 입력·토큰 저장도 하지 않습니다. CLI 요청은 한도 조회뿐이며 응답/시간 제한과 해당 자식 프로세스만 종료하는 처리를 적용합니다. 로그인 자동 실행은 사용자가 켤 때만 현재 사용자 Run 키의 UsageBar 항목을 변경합니다. 배포 ZIP은 아직 Windows 코드 서명이 없으며, 보안 경고를 우회하거나 Defender/SmartScreen을 끄도록 요구하지 않습니다. 세부 범위는 `Windows/README.md`를 참조하세요.

- 로컬 설치에는 사용자 키체인의 `UsageBar Local Signing` 자체 서명 인증서와 동일한 앱 식별자 `com.usagebar.app`을 재사용합니다. DR은 유지되지만 Apple Team ID가 없는 자체 서명은 키체인의 별도 partition 검사에서 코드 해시로 분류되므로, 업데이트 후 ‘항상 허용’ 유지까지 보장하지 않습니다. Claude 정상 조회는 CLI를 통해 이 외부 키체인 항목에 대한 직접 의존을 피합니다. 기존 Claude 항목의 ACL/partition 목록을 수정하거나 우회하지 않습니다.
- `scripts/setup-local-signing.sh`는 사용자가 명시적으로 실행할 때만 인증서를 생성하며 기존 인증서가 있으면 재생성하지 않습니다. 생성한 개인 키는 추출 불가로 가져오며 서명 접근은 `/usr/bin/codesign`에만 허용합니다. 시스템/사용자 신뢰 루트나 Claude 자격 증명 ACL은 변경하지 않습니다.
- 생성 중 임시 개인 키/PKCS#12 파일은 소유자만 접근 가능한 임시 폴더에 두고 종료 시 제거합니다. 키와 인증서를 저장소에 넣지 않습니다.
- 로컬 서명 실패 시 임시 서명으로 대체하지 않습니다. CI는 별도의 명시적 설정으로만 임시 서명을 사용하며, 해당 앱은 허용 유지가 필요한 로컬 설치용이 아닙니다.

## Reporting

공개 이슈에 액세스 토큰이나 계정 식별자를 올리지 마세요. 저장소 소유자에게 GitHub Security Advisory로 비공개 제보해 주세요.
