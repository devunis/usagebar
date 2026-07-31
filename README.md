# UsageBar

ChatGPT/Codex, Claude, Gemini 구독 계정의 현재 한도와 리셋 시간을 보여주는 네이티브 macOS 메뉴바 앱입니다. 메뉴바에는 최대 3개의 사용량을 동시에 표시할 수 있으며 서비스, 한도 종류, 표시 방식과 색상을 설정에서 직접 선택할 수 있습니다.

각 서비스 카드는 실제 OpenAI, Claude, Gemini 벡터 심볼을 사용합니다. 상표는 각 소유자에게 있으며 UsageBar와의 제휴나 보증을 의미하지 않습니다. 아이콘 출처와 라이선스는 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 확인해 주세요.

## 지원 범위

| 공급자 | 표시 항목 | 인증 |
| --- | --- | --- |
| ChatGPT / Codex | 5시간·주간 등 현재 rate-limit 창 | Codex CLI 로그인 |
| Claude | 5시간·주간·Fable 등 모델별 주간 한도 | Claude CLI OAuth 로그인 |
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
./scripts/build-app.sh release
open UsageBar.app
```

앱은 15분마다 자동 새로고침하며, 설정에서 수동 또는 5/15/30/60분으로 바꿀 수 있습니다. Gemini는 기본적으로 숨겨져 있습니다. 설정에서 공급자, 단기·주간·모델별 한도, 플랜명, 리셋 시간과 갱신 시간을 모두 개별적으로 켜고 끌 수 있습니다.

## 구현 방식

- Codex: 공식 `codex app-server` JSON-RPC의 `account/rateLimits/read`
- Claude: Claude CLI가 저장한 OAuth 자격 증명으로 Anthropic usage 응답 조회
- Gemini: Gemini CLI OAuth 자격 증명으로 Code Assist quota 응답 조회

## 알려진 제한

- 공급자가 로그인·한도 응답 형식을 바꾸면 어댑터 업데이트가 필요할 수 있습니다.
- 표시되는 창 종류는 플랜과 계정 상태에 따라 다릅니다.
- 이 초기 버전은 개발자용 ad-hoc 서명입니다. 외부 배포에는 Developer ID 서명과 notarization이 필요합니다.

## 보안

자격 증명 처리 원칙은 [SECURITY.md](SECURITY.md)를 확인해 주세요.

## 라이선스

MIT
