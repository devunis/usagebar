# UsageBar

ChatGPT/Codex, Claude, Gemini 구독 계정의 현재 한도와 리셋 시간을 보여주는 네이티브 macOS 메뉴바 앱입니다. 메뉴바에는 서비스당 한 항목씩 실제 서비스 마크와 컬러 테두리, 5칸 컬러 막대를 사용해 최대 3개 서비스를 동시에 표시합니다. Claude는 5시간, 전체 주간, Fable 등 모델별 한도 중 메뉴바에 표시할 항목을 설정에서 선택할 수 있습니다.

UsageBar 앱 아이콘은 청록·코랄·보라 사용량 막대를 하나의 게이지로 묶은 전용 디자인을 사용합니다.

각 서비스 카드는 실제 OpenAI, Claude, Gemini 벡터 심볼을 사용합니다. 상표는 각 소유자에게 있으며 UsageBar와의 제휴나 보증을 의미하지 않습니다. 아이콘 출처와 라이선스는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 확인해 주세요.

## 지원 범위

| 공급자 | 표시 항목 | 인증 |
| --- | --- | --- |
| ChatGPT / Codex | 5시간·주간 한도, 재설정 크레딧 횟수·만료일 | Codex CLI 로그인 |
| Claude | 5시간·주간·모델별 한도, 제한 초기화 횟수·만료일, 클라우드 크레딧 잔액·만료일 | Claude CLI OAuth 로그인 |
| Gemini | 모델별 잔여 quota와 리셋 시간 | Gemini CLI OAuth 로그인 |

API 키를 입력하거나 저장하지 않습니다. UsageBar는 이 Mac의 공식 CLI 로그인 세션을 재사용하며 토큰 값을 화면이나 로그에 출력하지 않습니다.

## 요구 사항

- macOS 14 Sonoma 이상
- 조회할 서비스의 공식 CLI
- 소스 빌드 시 Swift 6 / Xcode

각 CLI에 로그인합니다.

```bash
codex login
claude auth login
gemini
```

로그인되지 않았거나 CLI가 설치되지 않은 공급자는 메뉴에 연결 안내가 표시됩니다.

> Gemini CLI의 계정 유형과 정책에 따라 소비자 구독 quota 조회가 제공되지 않을 수 있습니다. 이 경우 UsageBar가 해당 오류를 그대로 안내합니다.

## 빌드 및 실행

```bash
swift test
zsh ./scripts/setup-local-signing.sh # 이 Mac에서 처음 한 번만 실행
./scripts/build-app.sh release
open UsageBar.app
```

앱은 15분마다 자동 새로고침하며, 설정에서 수동 또는 5/15/30/60분으로 바꿀 수 있습니다. Gemini는 기본적으로 숨겨져 있습니다. 설정에서 공급자, 단기·주간·모델별 한도, 플랜명, 리셋 시간, 재설정 크레딧과 갱신 시간을 모두 개별적으로 켜고 끌 수 있습니다.

자동 갱신 모드에서는 Mac 잠자기 해제, 로그인 세션 복귀, 네트워크 재연결 후 3초 뒤 오래된 사용량을 다시 조회합니다. 복귀 직후 실패하면 10초 간격으로 최대 2회 빠르게 재시도한 뒤 정규 갱신 주기로 돌아갑니다. `수동` 설정은 재실행 후에도 유지하며 복귀 이벤트가 자동 갱신을 켜지 않습니다. 로그인 토큰 만료는 키체인 허용 거부와 구분하여 안내합니다. UsageBar는 Claude Code의 갱신 토큰을 직접 교환하거나 저장하지 않으므로, 만료 시 Claude Code에서 로그인을 갱신하면 다음 자동 조회가 새 정보를 다시 읽습니다.

Claude는 CLI의 구조화된 `get_usage` 응답을 먼저 읽습니다. `rate_limits.model_scoped`의 모델명과 사용률을 받아 Fable 등 모델별 주간 한도를 표시합니다. CLI가 없거나 조회를 완료하지 못하면 기존 로그인 정보를 인증창 없이 읽어 OAuth 사용량 조회를 시도합니다. OAuth 응답의 `limits[].weekly_scoped` 및 기존 `seven_day_*` 형식도 지원하며 0%와 알 수 없는 값을 구분합니다.

로컬 빌드는 사용자 키체인의 `UsageBar Local Signing` 인증서를 계속 재사용합니다. 이는 앱의 지정 요구사항(DR)을 유지하지만, 자체 서명에는 Apple Team ID가 없어 키체인의 별도 partition 검사에서는 빌드별 코드 지문을 사용합니다. 따라서 고정 인증서만으로 업데이트 후의 ‘항상 허용’ 유지까지 보장하지 않습니다. Claude 정상 조회에서는 CLI가 로그인 정보를 관리하므로 UsageBar의 직접 키체인 허용이 필요하지 않습니다. 다른 서명을 사용하려면 `USAGEBAR_CODESIGN_IDENTITY`를 지정합니다. 인증서가 없거나 서명이 실패하면 임시 서명으로 자동 대체하지 않습니다.

ChatGPT/Codex 계정에 적립된 사용 한도 재설정 크레딧이 있으면 횟수와 가장 가까운 만료일을 표시합니다. `재설정 사용`은 확인창을 거친 뒤 5시간 및 주간 한도를 함께 재설정합니다. 네트워크 응답이 불확실한 경우 같은 idempotency key로만 재시도해 크레딧의 중복 소모를 방지합니다.

`/Applications`에 설치한 앱은 사용자 LaunchAgent를 등록해 macOS 로그인 시 자동 실행됩니다. 설정의 `로그인할 때 UsageBar 자동 실행`에서 언제든 켜거나 끌 수 있습니다.

새로고침 중에는 기존 사용량을 유지하고 카드의 갱신 표시만 회전하며, 새 응답이 도착하면 값만 교체합니다. Claude CLI 조회가 성공하면 UsageBar는 자격 증명을 읽지 않습니다. CLI 실패 후 OAuth 대체 조회는 구형 키체인의 사용자 상호작용까지 차단하며, 실패하면 이전 값과 연결 필요/갱신 지연 및 마지막 성공 시간을 표시합니다. `추가 정보 연결…`이나 `다시 연결…`을 직접 누르고 확인했을 때만 UsageBar의 키체인 허용을 요청합니다. Claude Code 자체의 최초 로그인·잠긴 키체인 등 시스템 인증 요구까지 UsageBar가 우회하지는 않습니다.

Claude 클라우드 크레딧은 정보가 제공될 때 일반 한도와 별도로 잔액·사용 막대·만료일을 표시합니다. CLI가 제공하지 않는 크레딧·초기화 정보는 `조회 불가`로 표시하며 0회/$0으로 추정하거나 다른 계정/이전 응답의 잔액을 섞지 않습니다. `추가 정보 연결…`은 별도 OAuth 조회이며 일반 한도 표시에 필수가 아닙니다. `resets_at`은 크레딧의 만료 시각으로 취급합니다. 제한 초기화 실행은 `Claude에서 확인·초기화`로 Claude 사용량 화면을 열어 진행합니다. 설정에서 초기화와 클라우드 크레딧 표시를 각각 끌 수 있습니다.

## 구현 방식

- Codex: 공식 `codex app-server` JSON-RPC의 `account/rateLimits/read`와 `account/rateLimitResetCredit/consume`
- Claude: 공식 Claude Code의 실험적 `get_usage` 제어 요청 → 인증창 없는 기존 OAuth 정보 순으로 조회합니다. CLI는 전용 작업 폴더에서 안전 모드, 도구/훅/MCP/세션 저장 비활성화 상태로 실행하며, 초기화와 사용량 요청만 보내고 종료합니다. `skip_behaviors`로 대화 내역 분석을 요청하지 않습니다. CLI 제한 시간은 35초이며 취소·시간 초과 시 해당 조회 프로세스만 정리합니다. CLI 로그인은 Claude Code가 관리하고 UsageBar는 토큰을 저장·수정하거나 갱신 토큰을 직접 교환하지 않습니다. Codex 조회 방식은 변경하지 않습니다.
- Gemini: Gemini CLI OAuth 자격 증명으로 Code Assist quota 응답 조회

## 알려진 제한

읽기 전용 문제 진단은 설치한 앱의 `Contents/MacOS/UsageBar --diagnose-claude-usage`로 실행할 수 있습니다. 일반 갱신과 같은 CLI 우선 경로를 사용하며, OAuth 대체 조회는 비대화형입니다. 결과에는 조회 상태와 모델별 사용률만 포함하며 토큰·계정 식별자·응답 원문은 출력하지 않습니다.

- 공급자가 로그인·한도 응답 형식을 바꾸면 어댑터 업데이트가 필요할 수 있습니다.
- 표시되는 창 종류는 플랜과 계정 상태에 따라 다릅니다.
- 로컬 빌드는 Mac별 자체 서명 인증서를 사용합니다. CI의 임시 서명은 패키징 테스트용이며 로컬 설치용이 아닙니다. 외부 배포에는 Developer ID 서명과 notarization이 필요합니다.

## 보안

자격 증명 처리 원칙은 [SECURITY.md](SECURITY.md)를 확인해 주세요.

## 라이선스

MIT
