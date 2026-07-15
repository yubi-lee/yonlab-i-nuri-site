# 12. UI/UX 비주얼 시스템과 반응형 검증 기준

문서 ID: UX-VIS-012

기준선: [design-baseline.json](design-baseline.json)

적용 화면: [02. 사용자·기능·화면 설계](02-functional-screen-design.md)의 `PUB-*`, `TCH-*`, `ADM-*` 전체

품질 게이트: `GATE-UX-ACCESSIBILITY`, `GATE-DESIGN-INTEGRITY`

## 1. 목적과 규범 수준

본 문서는 YOnLab 독립 서비스의 구현 가능한 시각 언어, 반응형 규칙, AI 상호작용 상태와 검증 증거를 정의한다. 색상·타이포그래피·간격·breakpoint·상태 이름은 구현 token과 시각 회귀 기준선의 normative source다. 화면별 정보와 행동은 02 문서가, 수용 판정은 09 문서가 우선하며 충돌 시 machine-readable 기준선과 본 문서 순으로 적용한다. [ui-journey-contracts.json](ui-journey-contracts.json)은 12개 핵심 여정의 component hierarchy·action·field·한국어 copy·responsive order·state·acceptance와 36개 screen closure를 구현 가능한 구조로 고정한다.

YOnLab은 공공 교육서비스에 맞는 차분한 navy와 명료한 teal을 사용하되, 다른 포털의 로고·색상 조합·일러스트·문구·레이아웃을 복제하지 않는다. 장식보다 읽기, 신뢰, 근거 확인과 다음 행동의 명확성을 우선한다.

## 2. 디자인 원칙

1. **근거가 먼저 보인다.** AI 답변, 진단, 추천은 결과와 근거·불확실도·정정 행동을 한 묶음으로 제시한다.
2. **한 화면에는 하나의 주 행동이 있다.** primary button은 같은 viewport에 원칙적으로 하나만 둔다.
3. **상태는 색에 의존하지 않는다.** icon, 제목, 본문, 필요 시 상태 code를 함께 제공한다.
4. **밀도는 역할에 맞춘다.** 교사 화면은 편안한 밀도, 운영 표는 사용자가 선택한 compact 밀도를 허용한다.
5. **작은 화면도 축약판이 아니다.** 390 px에서도 핵심 정보와 근거·오류 복구 행동을 제거하지 않고 순서와 표현만 바꾼다.
6. **AI를 사람처럼 위장하지 않는다.** 모든 AI 생성 결과에 `AI 생성` 표지와 정책 version, 생성 시각을 제공한다.
7. **안전한 실패가 완성된 상태다.** 근거 부족, 권한 회수, provider 장애와 정책 차단을 정상적인 설계 상태로 구현한다.

## 3. 디자인 token

구현은 아래 semantic token 이름을 그대로 사용한다. 화면 코드에서 raw hex, 임의 px, 임의 shadow를 직접 추가하지 않는다. 새 token은 디자인 담당자와 접근성 담당자의 검토, Storybook 회귀 검증 후 추가한다.

### 3.1 색상

| Token | 값 | 용도 | 허용 foreground / 최소 대비 |
|---|---:|---|---|
| `color.brand.navy.900` | `#0B1F3A` | 상단·좌측 navigation, 강한 제목 | white 16.52:1 |
| `color.brand.navy.700` | `#102A43` | 본문·기본 icon | white 14.64:1 |
| `color.brand.teal.800` | `#0B5D56` | primary action, 진행 완료 | white 7.74:1 |
| `color.brand.teal.700` | `#0F766E` | 선택 강조, 차트 핵심 series | white 5.47:1 |
| `color.brand.teal.050` | `#E6FFFA` | 선택·근거 배경 | navy 900 또는 teal 800 |
| `color.text.primary` | `#102A43` | 본문·제목 | white 14.64:1 |
| `color.text.secondary` | `#475569` | 보조 설명·metadata | white 7.58:1 |
| `color.text.inverse` | `#FFFFFF` | navy/teal 진한 배경 | 해당 조합만 사용 |
| `color.link.default` | `#1D4ED8` | 링크·텍스트 행동 | white 6.70:1, underline 유지 |
| `color.link.hover` | `#1E40AF` | 링크 hover | underline 두께 2 px |
| `color.surface.canvas` | `#F8FAFC` | 앱 배경 | primary/secondary text |
| `color.surface.default` | `#FFFFFF` | card·dialog·form | primary/secondary text |
| `color.border.default` | `#CBD5E1` | field·card 경계 | 비텍스트 경계로만 사용 |
| `color.border.strong` | `#64748B` | 활성 field·구분 | 3:1 비텍스트 확인 |
| `color.focus.ring` | `#0284C7` | 3 px 외곽 focus ring | white 대비 4.10:1 |
| `color.status.success.foreground` | `#166534` | 성공 icon·제목 | white 7.13:1 |
| `color.status.success.background` | `#F0FDF4` | 성공 banner·chip 배경 | success foreground 6.81:1 |
| `color.status.warning.foreground` | `#92400E` | 경고 icon·제목 | white 7.09:1 |
| `color.status.warning.background` | `#FFFBEB` | 경고 banner·chip 배경 | warning foreground 6.84:1 |
| `color.status.danger.foreground` | `#B42318` | 오류·위험 icon·제목 | white 6.57:1 |
| `color.status.danger.background` | `#FFF1F2` | 오류·위험 banner 배경 | danger foreground 5.98:1 |
| `color.status.info.foreground` | `#1D4ED8` | 정보 icon·제목 | white 6.70:1 |
| `color.status.info.background` | `#EFF6FF` | 정보 banner·chip 배경 | info foreground 6.16:1 |
| `color.control.disabled.background` | `#E2E8F0` | disabled control 배경 | disabled text 6.15:1 |
| `color.control.disabled.text` | `#475569` | disabled control label·icon | disabled background 6.15:1 |
| `color.control.disabled.border` | `#CBD5E1` | disabled control 경계 | 텍스트 의미 전달에 사용 금지 |

상태 banner는 같은 이름의 `*.foreground`와 `*.background` token만 조합한다. 상태 foreground를 얇은 본문 글자에 흰 배경 없이 단독 장식으로 쓰지 않는다. disabled는 opacity를 낮추지 않고 세 `color.control.disabled.*` token, `not-allowed` cursor와 native disabled 속성을 함께 적용한다.

focus는 `outline: 3px solid #0284C7; outline-offset: 2px`를 기본으로 하며 진한 배경에서는 2 px white inner ring과 3 px focus outer ring을 함께 사용한다. Windows 고대비 모드에서는 system `Highlight`로 대체한다.

### 3.2 타이포그래피와 한국어 글꼴

웹 기본 font stack은 다음과 같다.

```css
font-family: "Pretendard Variable", Pretendard, "Noto Sans KR",
  "Apple SD Gothic Neo", "Malgun Gothic", system-ui, sans-serif;
```

- self-hosted WOFF2는 승인된 Pretendard subset과 Noto Sans KR fallback만 사용하고 font license와 checksum을 기록한다.
- `font-display: swap`을 사용하며 fallback 전환 시 CLS가 0.05를 넘지 않도록 metric-compatible fallback을 지정한다.
- PDF·운영 문서는 Noto Sans KR을 embed하고 누락 glyph 0건을 확인한다.
- 숫자·기간·비용·score는 `font-variant-numeric: tabular-nums`를 사용한다.
- 한국어 단어 중간 강제 줄바꿈은 금지한다. `word-break: keep-all; overflow-wrap: anywhere`를 함께 적용하되 URL·긴 ID만 문자 단위로 줄바꿈한다.

| Token | 크기/행간 | 굵기 | 용도 |
|---|---|---:|---|
| `type.display` | 40/52 px | 700 | 공개 홈의 한 개 핵심 제목; 390 px에서 32/42 |
| `type.h1` | 32/42 px | 700 | 화면 제목; 390 px에서 28/38 |
| `type.h2` | 24/34 px | 700 | 큰 section |
| `type.h3` | 20/30 px | 600 | card·subsection 제목 |
| `type.body.lg` | 18/30 px | 400 | 안내·AI 답변 |
| `type.body.md` | 16/26 px | 400 | 기본 본문·form |
| `type.body.sm` | 14/22 px | 400 | metadata·표 보조 정보 |
| `type.label` | 14/20 px | 600 | field·button label |
| `type.caption` | 12/18 px | 500 | 제한된 보조 metadata; 핵심 정보 금지 |
| `type.code` | 14/22 px | 400 | trace ID·policy version·명령 |

본문 최소 크기는 16 px이며, 14 px 이하는 metadata와 표의 비핵심 정보에만 쓴다. 사용자 browser 글자 크기 200%에서 기능 손실과 양방향 scroll이 없어야 한다.

### 3.3 간격·크기·형태

간격은 4 px base grid만 사용한다.

| Token | 값 | 대표 용도 |
|---|---:|---|
| `space.0` | 0 px | gap 제거 |
| `space.1` | 4 px | icon 내부·미세 간격 |
| `space.2` | 8 px | icon-label·chip 내부 |
| `space.3` | 12 px | mobile grid gutter·작은 control 내부 |
| `space.4` | 16 px | mobile page margin·compact card padding |
| `space.5` | 20 px | form field 간격·tablet gutter |
| `space.6` | 24 px | card padding·desktop gutter |
| `space.8` | 32 px | subsection 간격 |
| `space.10` | 40 px | 큰 panel 간격 |
| `space.12` | 48 px | page section 간격 |
| `space.16` | 64 px | shell·section 간격 |
| `space.20` | 80 px | desktop page margin |
| `space.24` | 96 px | public hero 상하 간격 |
| `size.control.sm` | 36 px | 운영 표의 비핵심 control만 허용 |
| `size.control.md` | 44 px | 기본 button·field·touch target |
| `size.control.lg` | 52 px | 로그인·진단 시작 등 핵심 행동 |
| `size.icon.md` | 20 px | field·table icon |
| `size.icon.lg` | 24 px | navigation·status icon |
| `radius.sm` | 6 px | field·button |
| `radius.md` | 10 px | card·popover |
| `radius.lg` | 16 px | dialog·bottom sheet |
| `radius.pill` | 999 px | status chip; 긴 문장 금지 |
| `shadow.none` | `none` | 기본 card·field |
| `shadow.dialog` | `0 12px 32px rgba(11,31,58,.16)` | dialog·떠 있는 popover |

위 표에 없는 `space.*`, `size.*`, `radius.*`, `shadow.*` 이름은 유효하지 않다. card 기본은 1 px border와 `shadow.none`이다. 떠 있는 dialog·popover만 `shadow.dialog`을 사용한다. 장식 blur, glass effect, 과도한 gradient는 금지한다. icon은 `size.icon.md/lg`의 선형 SVG를 기본으로 하고 `aria-hidden` 또는 접근 가능한 이름을 명시한다. emoji를 기능 icon으로 사용하지 않는다.

## 4. viewport·grid·layout

CSS breakpoint는 mobile-first로 `0–599`, `600–1023`, `1024 이상`이다. 수용 screenshot의 고정 viewport는 `390×844`, `768×1024`, `1440×900`이며 세 너비 모두 수평 overflow 0 px를 요구한다.

| 기준 viewport | page/grid | navigation | 콘텐츠 구성 |
|---|---|---|---|
| 1440 px | 최대 폭 1280 px, 좌우 80 px, 12열, gutter 24 px | 교사 248 px side nav, 운영 264 px side nav, 64 px top bar | main 8열 + context 4열; 대화는 760 px 읽기 폭 |
| 768 px | 좌우 24 px, 8열, gutter 20 px | 64 px top bar + drawer; 현재 위치는 제목과 breadcrumb로 유지 | 2열 card는 중요도 순 1열 전환, context는 inline disclosure |
| 390 px | 좌우 16 px, 4열, gutter 12 px | 56 px top bar + 64 px bottom nav + safe area | 단일 열, primary action sticky 가능, 표는 card/열 선택 전환 |

- 1280 px보다 넓은 화면에서도 읽기 영역을 늘리지 않고 외곽 여백만 증가시킨다.
- sticky 영역은 viewport의 30%를 넘지 않으며 320 px 높이의 landscape에서도 콘텐츠와 행동을 가리지 않는다.
- mobile bottom navigation은 교사 핵심 4개 `홈`, `진단`, `학습`, `자료`와 `더보기`만 둔다. 숨겨진 메뉴에도 현재 위치와 badge를 동등 제공한다.
- 운영 console은 mobile에서 조회·승인·incident 확인만 보장하고, 복잡한 bulk 편집은 단일 항목 flow로 바꾼다. “PC에서만 가능”으로 막지 않는다.
- dialog는 390 px에서 bottom sheet 또는 full-screen dialog로 전환한다. focus trap, 닫기, browser back 복구를 제공한다.
- safe area는 `env(safe-area-inset-*)`를 반영한다.

## 5. navigation과 정보 위계

### 5.1 공통 shell

- skip link `본문으로 건너뛰기`가 첫 keyboard focus다.
- top bar에는 서비스명, 현재 tenant/기관, 알림, 도움말, 계정만 둔다. 운영환경 badge는 production을 제외한 환경에서 항상 보인다.
- breadcrumb는 홈을 포함해 최대 4단계이며 마지막 항목은 링크가 아니다.
- side nav section은 최대 7개, 한 section의 바로 보이는 항목은 최대 7개다. 확장 상태는 사용자별로 저장한다.
- 현재 항목은 4 px teal bar, 굵은 label, `aria-current="page"`로 표시한다.
- unread badge 숫자는 `99+`로 제한하고 접근 가능한 전체 숫자를 제공한다.

### 5.2 대시보드 구성

교사 `TCH-001`의 1440 px 순서는 다음 행동 8열 + 진단/학습 진행 4열, 추천 연수 8열 + 알림 4열, 최근 문서 12열이다. 768/390 px에서는 `다음 행동 → 진행률 → 추천 → 알림 → 최근 문서` 순으로 단일 열이 된다. 동일 중요도의 card 높이를 억지로 맞추지 않는다.

운영 `ADM-001`은 서비스 상태와 안전 경보를 첫 행, AI 품질·문서 pipeline·queue를 둘째 행, 사용·비용 추세를 셋째 행에 둔다. 숫자 card는 값, 단위, 기간, 이전 기간 변화, 최신시각, 상세 링크를 모두 포함한다. 위험 지표는 색뿐 아니라 `정상/주의/위험` label과 임계값을 표시한다.

### 5.3 form·table·chart 밀도

- 기본 밀도 `comfortable`: 행 52 px, card padding 24 px, form field 간 20 px.
- 운영 사용자가 선택할 수 있는 `compact`: 표 행 40 px, card padding 16 px. touch 환경에서는 자동으로 comfortable로 복귀한다.
- form은 label을 field 위에 둔다. placeholder는 예시일 뿐 label을 대신하지 않는다.
- validation은 blur와 submit 때 제공하고 첫 오류로 focus를 이동하되 입력 중 매 keystroke 경고를 금지한다.
- 표 header는 sticky 허용, 열 정렬·filter·단위·빈 값 의미를 명시한다. 390 px에서는 핵심 2개 값을 card 제목에, 나머지는 definition list에 둔다.
- 차트는 제목, 한 문장 요약, 범례, 단위, 기준 기간과 동등한 데이터 표를 제공한다. 색 series는 shape/line pattern과 함께 구분한다.

## 6. AI 진단·추천 대화 상태

`TCH-004`, `TCH-005`, `TCH-007`, `TCH-012`는 아래 상태 machine을 공통 사용한다.

| 상태 | 화면 표현 | 필수 행동·접근성 |
|---|---|---|
| `idle` | 목적·예시 질문·개인정보 주의 | 입력 focus와 시작 행동 |
| `composing` | local 입력, 글자수·첨부 등급 | 전송 전 RESTRICTED 안내, 임시저장 |
| `queued` | “요청을 안전하게 확인 중” 단계 표시 | 취소, 중복 전송 차단 |
| `streaming` | 문장 단위 progressive rendering | 중지 button; token 단위 live announcement 금지 |
| `complete_grounded` | 답변, AI 표지, 정책 version, citation | 완료 한 번만 polite live announcement |
| `partial_grounded` | 확인된 문장과 미확인 범위를 분리 | 확인된 citation만 열기, 다시 검색 |
| `no_answer` | 근거 부족 원인·검색 범위 | 범위 수정, 전문가 문의; 추측 답변 금지 |
| `policy_blocked` | 전송 불가 이유를 안전한 범주로 표시 | 입력 수정·내부 처리·문의; 정책 상세/데이터 존재 비노출 |
| `provider_degraded` | “제한 모드” badge와 사용 가능한 기능 | 정형 flow/sLLM fallback, 재시도 시각 |
| `timeout_or_error` | 사용자 메시지 + trace ID | idempotent 재시도, 입력 보존 |
| `cancelled` | 생성 중단 지점과 저장 여부 | 새로 요청, 필요한 경우 부분 결과 폐기 |
| `stale_result` | rubric/model/content version 변화 알림 | 최신 기준 재계산 전 의사결정 사용 차단 |

교사 bubble과 AI panel은 avatar 색만으로 구분하지 않는다. 교사 입력은 오른쪽 정렬을 강제하지 않고 label `나`, AI는 `YOnLab AI`를 텍스트로 표시한다. AI 답변 최대 읽기 폭은 720 px이며 긴 답변은 제목·목록·근거로 구조화한다. 생성 중 cursor animation은 1개만 사용한다.

진단 결과에는 score·level 외에 evidence count, confidence band, 미확인 항목과 `근거 수정`을 같은 viewport에 제공한다. 6개 family 아래 12개 operational profile의 확률은 낙인형 badge가 아니라 분포와 해석으로 제시한다. 상위 3 profile만 먼저 보이고 6-family 집계와 전체 12 profile은 펼쳐본다. 확률 합, 순서와 혼합 판정은 기준선 계약을 따른다.

## 7. citation과 근거 뷰어 상태

중요 claim 바로 뒤에 `[문서 약칭 · p.12 · 표 3 셀 B4]` 형식의 citation chip을 둔다. chip에는 접근 가능한 전체 문서명과 version을 제공하며 키보드 Enter/Space로 `TCH-013`을 연다.

| 상태 | 표현 | 처리 |
|---|---|---|
| `valid_current` | teal outline + `근거 확인됨` | 정확한 문서 version·node·locator 강조 |
| `loading_authorization` | skeleton + `권한 확인 중` | 원문/제목을 먼저 노출하지 않음 |
| `version_superseded` | warning + 이전/현재 version | 현재 version 재검색, 이전 근거 사용 중지 |
| `access_revoked` | lock + `접근할 수 없음` | cache 본문 제거, 답변 해당 claim 무효화 |
| `locator_unavailable` | danger + trace ID | 원문 대신 추측 금지, 신고·재색인 요청 |
| `invalid` | danger + `유효하지 않은 인용` | 최종 사용자 답변에는 제공 금지, QA 결함 기록 |

근거 drawer는 원문 8열 + citation metadata 4열이며, 768 px 이하는 metadata 뒤 원문 순 단일 열, 390 px은 full-screen이다. 강조는 색 배경과 2 px border를 함께 사용한다. 표는 해당 셀, 행·열 header와 caption을 함께 보여준다. 현재 권한 재검증 전에는 cached snippet도 표시하지 않는다.

## 8. Loading·Empty·Error·Degraded 상세 규칙

- **Loading:** 400 ms 미만에는 skeleton을 지연해 깜빡임을 막고, 2초를 넘으면 현재 단계, 10초를 넘으면 취소·백그라운드 전환을 제공한다.
- **Empty-first-use:** 기능 목적, 예시, 하나의 시작 행동을 제공한다.
- **Empty-filtered:** 적용 filter와 `필터 초기화`, 검색어 교정 제안을 제공한다.
- **Error-recoverable:** 사람이 이해할 제목, 영향 범위, 재시도, trace ID를 제공한다.
- **Error-terminal:** 재시도 대신 문의·내보내기·안전 종료를 제공한다.
- **Partial:** 이용 가능한 영역과 누락 영역을 각각 제목으로 구분한다.
- **Forbidden:** 403과 404 표현을 통일해 데이터 존재 여부를 추론하지 못하게 한다.
- **Offline:** 미전송 입력을 암호화된 local draft 정책 범위에서 보존하고 reconnect 뒤 명시적으로 전송한다.
- **Degraded:** 화면 상단 persistent banner, 제한 기능 목록, 최신 상태 확인시각과 status page 링크를 제공한다.

모든 비정상 상태는 primary journey별 Storybook story와 E2E fixture가 있어야 한다. 정상 화면 screenshot만으로 시각 완료를 판정하지 않는다.

## 9. 동작과 motion

| Token | 값 | 사용 |
|---|---:|---|
| `motion.fast` | 120 ms | hover·focus 색 전환 |
| `motion.normal` | 180 ms | disclosure·popover |
| `motion.slow` | 240 ms | drawer·dialog |
| `motion.easing.standard` | `cubic-bezier(.2,0,0,1)` | 진입·상태 변화 |

- opacity와 transform만 animate하며 layout 크기·scroll 위치를 지속 animate하지 않는다.
- loading indicator는 2초 이상 필요할 때만 반복하고, 5초 이상이면 단계형 progress로 전환한다.
- `prefers-reduced-motion: reduce`에서 duration을 0 ms로 바꾸고 parallax, 자동 carousel, shimmer, typing animation을 제거한다.
- 새 콘텐츠로 focus를 강제 이동하지 않는다. route 전환 후 `h1` 또는 main container로 programmatic focus를 이동한다.
- toast는 성공 5초, 경고·오류는 사용자가 닫을 때까지 유지하고 동일 이벤트를 중복 표시하지 않는다.

## 10. 접근성 구현 계약

- WCAG 2.2 AA를 최소로 하며 critical journey의 미해결 오류는 `KPI-009 = 0`이어야 한다.
- 모든 기능은 keyboard만으로 가능하고 focus 순서는 DOM 순서와 일치한다. drag 기능은 button 기반 대안을 제공한다.
- landmark는 `header`, `nav`, `main`, `aside`, `footer`를 한 페이지에서 의미에 맞게 사용하며 `main`은 하나다.
- field의 label, hint, error는 `aria-describedby`로 연결한다. required를 색·별표만으로 전달하지 않는다.
- streaming 답변은 완성된 단락이나 완료 event만 알리고, 사용자가 읽는 위치를 침범하지 않는다.
- dialog는 accessible name, focus trap, Escape 닫기, 원래 trigger focus 복귀를 구현한다. 파괴적 확인 dialog는 기본 focus를 취소에 둔다.
- 한국어 screen-reader 발음 검수를 위해 영문 약어 `AI`, `HWPX`, `RAG`에 확장 설명 또는 accessible label을 제공한다.
- 인증·진단·제출 session timeout은 만료 5분 전에 경고하고 최소 20분 연장을 제공한다.
- 오류 요약은 form 상단에 두고 field 오류로 이동하는 link를 제공한다.

## 11. 시각 회귀·접근성 증거 matrix

### 11.1 필수 viewport·상태 조합

| Evidence ID | 범위 | Viewport | 필수 상태 | 합격 기준 |
|---|---|---|---|---|
| VIS-001 | `PUB-001~004` | 1440, 768, 390 | default, loading, empty, error | 기준선 diff ≤0.10%; 승인 mask만 제외 |
| VIS-002 | `TCH-001~010`, `TCH-016` | 1440, 768, 390 | default, first-use, long Korean text, 200% zoom | overflow·clip·겹침 0건 |
| VIS-003 | `TCH-004~007`, `TCH-012` | 1440, 768, 390 | AI 상태 machine 전체 | 상태 누락·색상 단독 표현 0건 |
| VIS-004 | `TCH-011~015` | 1440, 768, 390 | citation 6상태, 복잡 표, degraded | claim-locator 불일치·원문 조기노출 0건 |
| VIS-005 | `ADM-001~016` | 1440, 768, 390 | comfortable/compact, 0/1k rows, permission denied | 핵심 행동 손실·수평 page overflow 0건 |
| VIS-006 | 공통 shell | 390 portrait/landscape, DPR 1/2 | keyboard, drawer/dialog, safe area | focus 가림·sticky 가림 0건 |

pixel diff는 font·OS·browser가 고정된 primary Chromium container에서 계산한다. 움직이는 시각·현재시각·ID는 접근 가능한 값은 유지한 채 승인된 mask manifest에만 등록한다. screenshot을 무조건 갱신해 결함을 숨기는 것을 금지하며 변경 사유, reviewer, issue/commit을 기록한다.

### 11.2 browser·OS·한국어 font matrix

| Evidence ID | 환경 | 범위 | 필수 확인 |
|---|---|---|---|
| XBR-001 | Windows 11 + 현재/직전 Chrome, Pretendard | 전체 E2E·시각 기준선 | 한글 조합, 줄바꿈, 100/200% zoom |
| XBR-002 | Windows 11 + 현재/직전 Edge, Malgun Gothic fallback | critical journey | font 차이, Windows 고대비, PDF 다운로드 |
| XBR-003 | Windows 11 + 현재 Firefox ESR/current | critical journey | form, sticky, grid, focus, HWPX flow |
| XBR-004 | macOS current-1 + Safari current | critical journey | Apple SD Gothic Neo fallback, VoiceOver |
| XBR-005 | Android current-2 + Chrome, 390 px class | 교사 journey | touch target, IME, virtual keyboard, rotate |
| XBR-006 | iOS current-1 + Safari, 390 px class | 교사 journey | safe area, zoom, bottom nav, VoiceOver |

브라우저 “현재”는 release candidate의 증거 manifest 생성일에 vendor stable channel로 고정하고 정확한 version, OS build, font checksum과 DPR을 함께 기록한다. 지원 matrix의 한 환경이라도 `BLOCKED`면 `GATE-UX-ACCESSIBILITY`는 PASS가 아니다.

### 11.3 자동·수동 접근성 증거

| Evidence ID | 도구/방법 | 대상 | 합격 기준·증거 |
|---|---|---|---|
| A11Y-001 | axe-core CI | [screen-route-contracts.json](screen-route-contracts.json)의 36 primary route·모든 alias와 공통 상태 | serious/critical 0; HTML/JSON report; 미실행 route 0 |
| A11Y-002 | keyboard-only 수동 | 진단→추천→학습, RAG→citation→초안, admin publish | trap·skip·focus loss 0; video+checklist |
| A11Y-003 | NVDA + Edge | 교사·운영 critical journey | 이름/역할/상태·live region 오류 0; 녹화+transcript |
| A11Y-004 | VoiceOver + Safari | 교사 critical journey | rotor/heading/form/dialog 오류 0; 녹화+checklist |
| A11Y-005 | Windows Contrast Themes | auth, AI, citation, error | invisible control/focus 0; screenshot |
| A11Y-006 | reduced motion | AI streaming, drawer, chart | 반복/typing/parallax 0; computed-style report |
| A11Y-007 | 200%/400% zoom·reflow | 전체 critical route | 320 CSS px에서 양방향 scroll 0, 데이터 표 예외 문서화 |
| A11Y-008 | 한국어 content review | 긴 제목·조사·숫자·영문 혼용 | 잘림·부자연스러운 자간·glyph 누락 0 |

## 12. 증거 보존과 판정

모든 시각·접근성 증거는 최종 문서 계약의 `docs/qa/ai-training-platform/` 및 release별 외부 evidence 저장소에 manifest로 연결한다. 증거 record는 `evidence_id`, screen/state, commit SHA, baseline SHA, browser/OS/font/DPR, viewport, 실행시각 UTC, runner, result, artifact URI, SHA-256, reviewer와 만료일을 포함한다.

시각 baseline은 기능 변경 또는 승인 token 변경 때만 갱신한다. critical journey 증거는 release candidate commit 이후 생성된 것만 fresh다. `FAIL`, `BLOCKED`, 누락 또는 stale 증거가 하나라도 있으면 release state는 `NOT_READY`다. 모든 구현 가능 증거가 PASS여도 발주기관·전문가·시범 데이터가 남으면 상한은 `CODE_COMPLETE / ACCEPTANCE DATA PENDING`이며, 모든 필수 증거가 fresh PASS일 때만 `ACCEPTED`다.

최종 설계서·운영 가이드·시험 보고서에 포함할 화면과 증거의 정확한 파일 경로·owner·gate는 [14. 최종 문서 산출물 계약](14-final-document-deliverables.md)을 따른다.
