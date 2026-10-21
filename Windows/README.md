# UsageBar for Windows — Preview 0.1

Windows 10/11용 네이티브 WPF + 알림 영역(트레이) 앱의 초기 버전입니다. macOS Swift 앱과 별도 구현이며, 같은 저장소의 `Windows/`에서 관리합니다. 현재 개발 브랜치는 `codex/windows-tray`입니다. 이 버전은 정식 배포나 macOS 기능 전체의 이식 완료를 의미하지 않습니다.

## 받기와 실행

1. GitHub Actions의 **Windows Preview**에서 성공한 실행을 엽니다.
2. Artifacts에서 **UsageBar-win-x64-preview**를 받습니다.
3. 안쪽 `UsageBar-win-x64-preview.zip`도 **전부 압축 해제**한 뒤 `UsageBar.exe`를 실행합니다. .NET 런타임은 포함되어 별도로 설치할 필요가 없습니다.
4. 트레이 아이콘(작업표시줄의 숨겨진 아이콘 `∧` 안에 있을 수 있음)을 클릭하면 사용량 창이 열립니다. 우클릭 메뉴에서 새로고침·설정·설치 안내·종료를 선택합니다. 창 닫기는 종료가 아닌 트레이 숨기기입니다.

아직 Windows 배포 서명이 없는 미리보기입니다. Windows가 알 수 없는 게시자 또는 평판 경고를 표시할 수 있습니다. 보안 기능을 끄거나 예외 처리하도록 요구하지 않습니다. 직접 빌드한 코드나 본인이 확인한 저장소의 산출물만 사용하고, 함께 제공되는 SHA256으로 다운로드 무결성을 확인하세요. 현재 CI 배포물은 x64이며 ARM64 네이티브 빌드는 별도 검증 전입니다.

## 지원 기능

- Codex: `codex app-server`의 `account/rateLimits/read`로 구독 한도 조회. 기본 5시간(있을 때) → 주간 → 예비/이름 있는 기타 한도 순서.
- Claude: 공식 Claude Code CLI의 실험적 `get_usage` 제어 요청. 5시간 → 주간 → Fable 등 모델별 한도. 0%는 표시하고 알 수 없는 값은 0으로 만들지 않습니다.
- 두 서비스를 색상 막대로 동시 표시. 트레이 막대/숫자 스타일과 서비스별 단기·주간·최고 사용률 선택. 정확한 이름과 수치는 툴팁과 사용량 창에 표시.
- 서비스별 켜기/끄기, 수동 또는 5/15/30/60분 자동 갱신, 실패·갱신 중 이전 값 유지.
- 절전 복귀·네트워크 재연결 후 3초 뒤 갱신, 복귀 직후 실패하면 10초 간격으로 최대 2회 재시도. 수동 모드에서는 하지 않음.
- Windows 로그인 자동 실행 **옵트인**. 현재 사용자 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\UsageBar`만 관리하며 관리자 권한을 요구하지 않음. 앱 폴더를 옮겼다면 자동 실행 설정을 다시 확인.
- CLI 설치 여부 확인, 공식 설치 페이지, PowerShell 명령어 복사, 로그인·재확인 안내. 프로그램을 몰래 설치하거나 명령어를 자동 실행하지 않음.

## CLI와 로그인

Windows **네이티브** Codex / Claude Code CLI와 구독 계정 로그인이 필요합니다. Claude/ChatGPT 데스크톱 앱만 설치했거나 WSL 안에만 CLI가 있으면 자동 감지되지 않을 수 있습니다. 권장 설치법은 안내 창에 연결된 공식 Windows 설치 방법입니다.

- `%USERPROFILE%\.local\bin`, WinGet 링크, Windows PATH의 `.exe`를 탐지합니다.
- 기본 npm 설치의 알려진 JS 진입점은 `node.exe`로 직접 실행합니다. `.cmd` 파일을 `cmd.exe`로 감싸 실행하지 않습니다. 사용자 지정 npm prefix·WSL 전용 설치는 현재 지원하지 않습니다.
- 로그인은 `codex login` / `claude auth login`으로 **ChatGPT / Claude 구독 계정**에 직접 진행합니다. API 키·Console 결제 계정과 다릅니다.
- 설치 확인은 파일 탐지만 합니다. `설치·사용량 다시 확인`과 새로고침은 켜진 공급자의 실제 사용량 조회를 요청합니다.

## 보안과 현재 제한

Windows 초기 버전은 **CLI 전용**입니다. macOS의 키체인 대체 경로를 이식하지 않았으며, Windows Credential Manager·브라우저 쿠키·Claude 자격 증명 파일을 직접 읽지 않습니다. 인증과 토큰 갱신은 각 공식 CLI가 담당합니다. Windows나 CLI 자체의 최초 로그인 요구까지 우회하지 않습니다.

CLI는 `%LOCALAPPDATA%\UsageBar\CLIWorkspaces` 전용 폴더에서 실행됩니다. Claude에는 안전 모드·도구/훅/MCP/세션 저장/Remote Control 비활성화와 `skip_behaviors: true`를 사용하고 initialize/get_usage만 보냅니다. 사용자 모델 턴을 시작하거나 프롬프트를 보내지 않습니다. 임의의 도구 요청은 거부합니다. 응답 크기와 40초 제한이 있으며 취소·시간 초과 때 해당 조회용 프로세스 트리만 종료합니다. 원시 stdout/stderr·토큰·계정 식별자는 로그나 설정에 저장하지 않습니다. 설정만 `%LOCALAPPDATA%\UsageBar\settings.json`에 원자적으로 저장하며 사용량 캐시도 디스크에 저장하지 않습니다.

Gemini, Claude 클라우드 크레딧/제한 초기화 추가 정보, Codex 한도 재설정 실행, 맥의 전체 아이콘 스타일은 아직 포함하지 않습니다. Codex 재설정 크레딧은 응답에 있을 때 횟수만 표시합니다. CLI 프로토콜 변경 시 조회가 실패할 수 있으며, 마지막 값과 오류를 구분해서 표시합니다.

## 개발 / 검증

.NET 10 SDK가 필요합니다. 외부 UI·인증·분석 패키지 없이 .NET 데스크톱 구성요소만 사용합니다.

```powershell
dotnet run --project Windows/UsageBar.Core.Specs/UsageBar.Core.Specs.csproj -c Release
dotnet build Windows/UsageBar.Windows/UsageBar.Windows.csproj -c Release
dotnet Windows/UsageBar.Windows/bin/Release/net10.0-windows/UsageBar.dll --smoke-test Windows/artifacts/smoke
./Windows/build.ps1 -Runtime win-x64
```

Core.Specs는 실행 가능한 검증 프로그램이며 실패 시 0이 아닌 코드로 종료합니다. 실제 공급자/계정 대신 자식 fixture 프로세스로 JSONL 초기화·순서·시간 초과·취소·stderr drain·크기 제한을 검사합니다. `--smoke-test`는 Windows에서 고정 fixture로 UI·로고·트레이 렌더링과 창 닫기/숨김을 검사하고 PNG를 만듭니다. 계정 조회·레지스트리 변경·설정 저장·설치·브라우저 실행은 하지 않습니다.

Mac/Linux에서도 Core.Specs 실행과 `EnableWindowsTargeting`을 이용한 UI 교차 빌드는 가능하지만 Windows UI의 실제 실행 검증과 동일하지 않습니다. Windows CI의 성공도 실제 사용자의 CLI 로그인·절전/트레이·자동 실행 동작 전체를 검증한 것으로 간주하지 않습니다.

## 공식 규격 / 자산

- [OpenAI Docs: Codex app-server](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt), [Codex CLI 설치](https://learn.chatgpt.com/docs/codex/cli)
- [Claude Code Windows 설치](https://code.claude.com/docs/en/setup#install-on-native-windows), CLI의 `get_usage` 형식은 현재 맥 구현과 같은 구조화된 제어 프로토콜 기준
- [Microsoft: NotifyIcon](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.notifyicon), [Windows 교차 빌드](https://learn.microsoft.com/en-us/dotnet/core/tools/sdk-errors/netsdk1100)
- 기존 `Resources/AppIcon.png`·SVG 로고를 그대로 사용합니다. 로고 라이선스는 포함된 `THIRD_PARTY_NOTICES.md`를 참조하세요.
