# AI 피로도 추적 시스템 (AI Fatigue Tracker for macOS)

인간-컴퓨터 상호작용(HCI) 및 사용자 경험(UX) 연구를 위한 macOS 전용 AI 사용 맥락 및 피로도 실시간 측정 시스템입니다.  
사용자의 AI 데스크톱 도구(Claude, ChatGPT, Cursor, Windsurf, Trae, Antigravity 등) 및 웹 AI(claude.ai, chatgpt.com 등) 상호작용을 로컬에서 정밀하게 감지하고, 경험표집법(ESM) 기반 설문 팝업과 자발적 피로 기록(단축키 ⌥⌘S)을 통해 피로도 데이터를 수집합니다.

---

## 목차
1. [아키텍처 및 핵심 기능](#아키텍처-및-핵심-기능)
2. [로컬 빌드 및 실행](#로컬-빌드-및-실행)
3. [연구자 배포 가이드: Developer ID 서명 및 공증 (Notarization)](#연구자-배포-가이드-developer-id-서명-및-공증-notarization)
4. [참여자 설치 및 권한 설정 안내서](#참여자-설치-및-권한-설정-안내서-참여자-전달용)
5. [연구 파일럿 디버그 도구 가이드](#연구-파일럿-디버그-도구-가이드)
6. [데이터베이스 및 Supabase 동기화](#데이터베이스-및-supabase-동기화)

---

## 아키텍처 및 핵심 기능

- **정밀 세션 감지 (`ActivityDetector`, `SessionManager`)**:
  - 데스크톱 AI 앱(Bundle ID), 터미널 CLI 프로세스, 브라우저 도메인(AppleScript AppleEvents) 자동 감지.
  - 대화 스레드/창 단위의 활성(Focus) 및 비활성(Unfocus) 누적 시간 분리 계산.
- **경험표집법(ESM) 설문 팝업 5종 (`SurveyScheduler`, `SurveyWindowManager`)**:
  - `start` (01 장면): AI 세션 시작 직후 목적 및 사전 피로도 측정 (372px).
  - `mid` (02 장면): AI 세션 진행 중 60~120분 무작위 간격 반복 (340px).
  - `end` (03 장면): AI 세션 종료 직후 최종 피로도 및 NASA-TLX 척도 측정 (372px).
  - `diary` (06 장면): 전역 단축키 ⌥⌘S 또는 메뉴 막대 클릭 시 전체 화면 자동 캡처와 함께 피로 순간 기록 (372px).
  - `nudge` (07 장면): 당일 자발적 기록이 0건일 때 18:30에 발송되는 회고 알림 (340px, "없었어요" vs "기록하기").
- **공통 팝업 보호 규칙**:
  - 최소 30분 쿨다운(최근 팝업 발생 후 30분간 억제), 1시간 동안 팝업 끄기(Mute), 사용자 자리 비움(Idle) 및 화면 잠금(Lock) 시 자동 보류(Pending), "10분 뒤에" 스누즈(Snooze), 5분 무응답 자동 닫힘(Timeout).
- **참여자 프라이버시 및 설정 (`SettingsView`, `PersonalExclusionManager`)**:
  - 이름 수정(서버의 `participants.display_name`만 갱신, UUID 식별자는 영구 보존).
  - 권한 재요청(손쉬운 사용, 브라우저별 자동화, 화면 기록, 마이크).
  - 개인 제외 목록(연구팀 기본 보호 앱 외에 참여자가 직접 앱/사이트 등록).
  - 오늘 기록된 활동 보기 및 선택 삭제(로컬 SQLite 및 Supabase 서버 양방향 삭제).
  - 14일 연구 종료일 자동 판정 및 감사 화면 전환.
- **오프라인 큐 및 백엔드 동기화 (`LocalDatabase`, `SupabaseSyncManager`)**:
  - 네트워크 단절 시 로컬 SQLite `sync_queue`에 자동 축적, 온라인 복구 시 1분 주기 자동 배치 전송.
  - CSV 일괄 내보내기 지원.

---

## 로컬 빌드 및 실행

### 요구 사항
- macOS 11.0 (Big Sur) 이상 (macOS 13+ Ventura / Sonoma / Sequoia 권장)
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.9+

### 컴파일 및 번들링
프로젝트 루트에서 포함된 빌드 스크립트를 실행합니다:

```bash
chmod +x build.sh
./build.sh
```

빌드가 완료되면 루트 디렉토리에 `AIFatigueTracker.app`이 생성됩니다.

### 실행 방법
```bash
# 일반 실행
open AIFatigueTracker.app

# 디버그 모니터 팝업 탭을 바로 띄우며 실행
open AIFatigueTracker.app --args --survey-tab
```

---

## 연구자 배포 가이드: Developer ID 서명 및 공증 (Notarization)

참여자의 Mac에서 Gatekeeper 경고("확인되지 않은 개발자", "악성 소프트웨어 검사 불가") 없이 안전하게 실행되려면 Apple Developer ID 인증서로 서명하고 Apple Notary Service 공증을 받아야 합니다.

### 1단계: 필수 준비 사항
1. **Apple Developer Program 계정** (개인 또는 조직)
2. 키체인에 설치된 **Developer ID Application** 인증서:
   ```bash
   security find-identity -p codesigning -v
   # 출력 예시: 1) 1234ABCD... "Developer ID Application: Your Name (TEAMID)"
   ```
3. **App-Specific Password(앱 암호)** 생성:
   - [appleid.apple.com](https://appleid.apple.com) 로그인 -> 로그인 및 보안 -> 앱 암호 생성 (이름: `notary-tool`).

### 2단계: notarytool 키체인 프로필 등록
터미널에서 공증 자격 증명을 키체인에 안전하게 저장합니다:
```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "your-apple-id@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### 3단계: Hardened Runtime 및 권한(Entitlements) 적용 서명
애플리케이션에 Hardened Runtime(`--options runtime`)과 안정적인 서명 식별자를 부여합니다:

```bash
# 1) 기존 임시 서명 제거
codesign --remove-signature AIFatigueTracker.app

# 2) Developer ID로 Hardened Runtime 서명
codesign --force --deep --options runtime \
  --entitlements .build_tools/entitlements.plist \
  --sign "Developer ID Application: Your Name (YOUR_TEAM_ID)" \
  AIFatigueTracker.app

# 3) 서명 검증
codesign --verify --verbose=2 AIFatigueTracker.app
```

> **참고 (`entitlements.plist`)**:
> ```xml
> <?xml version="1.0" encoding="UTF-8"?>
> <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
> <plist version="1.0">
> <dict>
>     <key>com.apple.security.automation.apple-events</key>
>     <true/>
> </dict>
> </plist>
> ```

### 4단계: 배포용 DMG 생성
참여자가 설치하기 쉬운 Drag-and-Drop DMG 이미지를 만듭니다:

```bash
# create-dmg 도구 사용 (brew install create-dmg)
create-dmg \
  --volname "AIFatigueTracker Installer" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "AIFatigueTracker.app" 175 190 \
  --app-drop-link 425 190 \
  --hide-extension "AIFatigueTracker.app" \
  "AIFatigueTracker-Installer.dmg" \
  "AIFatigueTracker.app"

# 또는 hdiutil 기본 내장 명령 사용
hdiutil create -volname "AIFatigueTracker" -srcfolder "AIFatigueTracker.app" -ov -format UDZO "AIFatigueTracker-Installer.dmg"
```

DMG 파일 자체도 코드 서명을 진행합니다:
```bash
codesign --force --sign "Developer ID Application: Your Name (YOUR_TEAM_ID)" AIFatigueTracker-Installer.dmg
```

### 5단계: Apple Notary Service 공증 제출
```bash
xcrun notarytool submit AIFatigueTracker-Installer.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait
```
"Status: Accepted" 메시지가 나오면 공증이 성공한 것입니다.

### 6단계: 공증 티켓 스테이플링 (Stapling)
오프라인 환경에서도 Gatekeeper를 통과할 수 있도록 공증 티켓을 파일에 부착합니다:

```bash
xcrun stapler staple AIFatigueTracker-Installer.dmg
```

### 7단계: 최종 설치성 검증
```bash
spctl -a -v --type open --context context:primary-signature AIFatigueTracker-Installer.dmg
# 출력 결과: AIFatigueTracker-Installer.dmg: accepted, source=Notarized Developer ID
```

---

## 참여자 설치 및 권한 설정 안내서 (참여자 전달용)

참여자분들께 아래 내용을 안내 문서(PDF/메일)로 제공해 주세요.

---

### [참여자 안내서] AI 사용 피로도 연구 시스템 설치 및 설정

안녕하세요! 본 연구에 참여해 주셔서 진심으로 감사드립니다.  
본 앱은 연구 기간(14일) 동안 여러분의 AI 도구 사용 맥락과 피로도를 분석하기 위한 연구용 도구입니다.

#### 1. 앱 설치하기
1. 전달받은 `AIFatigueTracker-Installer.dmg` 파일을 더블 클릭하여 엽니다.
2. 창이 열리면 **AIFatigueTracker** 아이콘을 오른쪽의 **Applications (응용 프로그램)** 폴더로 드래그합니다.
3. 응용 프로그램 폴더로 이동하여 **AIFatigueTracker**를 실행합니다.

#### 2. 첫 실행 및 필수 시스템 권한 설정
앱을 실행하면 메뉴 막대(화면 상단 시계 옆)에 뇌 모양(또는 파형) 아이콘이 생기며 안내 창이 열립니다.  
AI 도구 사용을 감지하고 피로 기록을 남기기 위해 다음 권한 허용이 필요합니다.

1. **손쉬운 사용 (Accessibility)**:
   - *목적*: 활성화된 AI 작업 창 및 사용 시간 감지.
   - *설정 방법*: 시스템 설정 -> 개인정보 보호 및 보안 -> **손쉬운 사용** -> `AIFatigueTracker` 스위치 **켬**.
2. **브라우저 자동화 (AppleEvents Automation)**:
   - *목적*: 웹 기반 AI(claude.ai, ChatGPT 등) 사용 시 도메인 및 탭 제목 확인.
   - *설정 방법*: 앱 실행 후 브라우저를 열 때 macOS 권한 확인 창이 나타납니다.
     > `"AIFatigueTracker"이(가) "Google Chrome"(또는 Safari/Arc)을(를) 제어하려고 합니다.`  
     > 👉 반드시 **[확인]** 또는 **[허용]**을 눌러주세요.
   - 이미 [허용 안 함]을 누른 경우: 시스템 설정 -> 개인정보 보호 및 보안 -> **자동화** -> `AIFatigueTracker` 아래 각 브라우저 항목을 **켬**으로 변경해 주세요.
3. **화면 기록 (Screen Recording)**:
   - *목적*: 단축키(`⌥⌘S`)로 자발적 피로를 남길 때, 당시 작업 화면을 함께 캡처하여 연구팀에 전달.
   - *설정 방법*: 시스템 설정 -> 개인정보 보호 및 보안 -> **화면 기록** -> `AIFatigueTracker` 스위치 **켬** (설정 후 앱 재실행 필요).
4. **마이크 (Microphone)**:
   - 음성 프롬프트 사용 여부 감지를 위한 권한입니다. 시스템 요청 팝업 시 **[허용]**을 눌러주세요.

#### 3. 피로한 순간 기록하기 (언제든 자유롭게!)
- 컴퓨터를 사용하다가 AI 때문에 피로감, 답답함, 혼란을 느끼셨다면 **전역 단축키 `⌥⌘S` (Option + Command + S)**를 누르거나, 메뉴 막대 아이콘을 눌러 **[지금 피로 기록하기]**를 클릭해 주세요.
- 당시 화면이 자동 캡처되며, 1분 이내로 간단하게 피로 점수와 이유를 기록하실 수 있습니다.

#### 4. 내 프라이버시 보호 기능
- **메뉴 막대 아이콘 -> [설정…]**:
  - **개인 제외 목록**: 기록에 남기고 싶지 않은 개인 앱이나 웹사이트 도메인을 직접 추가하실 수 있습니다. (추가된 항목은 일체 기록되지 않습니다.)
  - **오늘 기록된 활동**: 오늘 수집된 앱/사이트 목록을 투명하게 확인하고, 원치 않는 항목은 **직접 선택하여 영구 삭제**할 수 있습니다 (서버에서도 즉시 지워집니다).
  - **1시간 동안 팝업 끄기**: 회의, 발표, 집중 작업 중에는 메뉴 막대에서 1시간 동안 알림을 끌 수 있습니다.
- **연구 종료일 (14일 후)**:
  - 14일이 경과하면 앱은 모든 활동 기록과 팝업을 **완전히 자동으로 중단**하고 감사 화면으로 전환됩니다.

---

## 연구 파일럿 디버그 도구 가이드

개발자 및 연구진은 메뉴 막대 패널에서 **[디버그 모니터…]**를 클릭하여 파일럿 점검용 고급 디버그 패널을 열 수 있습니다.

1. **시간 배속 모드 (1분 = 30분, 30배속)**:
   - 상단 퀵 버튼 **[⏱️ 시간 배속 (1분=30분)]**을 누르면 모든 스케줄러 간격이 30배 가속됩니다:
     - 30분 쿨다운 -> **1분 (60초)**
     - 60~120분 mid 팝업 간격 -> **2분~4분 (120~240초)**
     - 10분 스누즈 -> **20초**
     - 60분 팝업 끄기(Mute) -> **2분**
     - 5분 타임아웃 -> **10초**
   - 짧은 시간 안에 14일 치의 다양한 상태 전이와 스케줄링 로직을 시뮬레이션할 수 있습니다.
2. **각 팝업 강제 표시 (Force Trigger)**:
   - `[start]` (세션 시작), `[mid]` (진행 중), `[end]` (세션 종료), `[diary]` (자발적 다이어리), `[nudge]` (07 장면 회고)
   - 버튼 클릭 시 쿨다운과 음소거를 즉시 무시하고 주 모니터 우상단에 팝업을 슬라이드 인으로 띄웁니다.
3. **로컬 동기화 큐 상태 & 백엔드 연동**:
   - 현재 오프라인 큐에 적재된 이벤트 건수(`syncManager.pendingQueueCount`), Supabase 온라인 상태, 마지막 전송 시각을 실시간 확인.
   - `[지금 동기화 시도]`, `[큐 새로고침]`, `[큐 비우기]` 버튼 제공.
4. **로그 CSV 내보내기**:
   - 로컬 SQLite에 누적된 원본 데이터를 언제든지 CSV 파일로 내보낼 수 있습니다:
     - `activity_events.csv`: 세부 창 활성/비활성, 브라우저 URL/도메인, AI 사용 여부.
     - `sessions.csv`: 식별된 대화 세션 생명주기 및 AI 누적 사용 시간.
     - `survey_responses.csv`: 5종 설문 응답 원본, NASA-TLX 점수, 심층 주관식, 캡처 파일 경로.
     - `[전체 CSV 일괄 내보내기]`: 다운로드 폴더에 타임스탬프 폴더로 3종 CSV를 즉시 자동 생성.

---

## 데이터베이스 및 Supabase 동기화

- 로컬 데이터베이스: `~/Library/Application Support/AIFatigueTracker/local_tracker.sqlite3`
- 화면 캡처 저장소: `~/Library/Application Support/AIFatigueTracker/Captures/`
- SQL 마이그레이션 파일: `supabase/migrations/20261025_init_fatigue_tracker.sql`
  - 테이블: `participants`, `sessions`, `activity_events`, `survey_responses`
  - RLS 정책 및 Storage 버킷(`captures`) 정책 완비
  - 참여자 표시 이름 변경(`participants.display_name`) 및 활동 이벤트 삭제(`activity_events DELETE`) 지원
