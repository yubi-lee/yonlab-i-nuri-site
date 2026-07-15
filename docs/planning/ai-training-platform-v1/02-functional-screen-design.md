# 02. 사용자·기능·화면 설계

문서 ID: UX-IA-002  
설계 기준: WCAG 2.2 AA, 1440·768·390 px, 한국어 우선
시각 규범: [12. UI/UX 비주얼 시스템과 반응형 검증 기준](12-ui-ux-visual-system.md)
실행 route 규범: [36-screen route contract](screen-route-contracts.json)

## 1. 사용자와 권한

| 역할 | 주요 목적 | 허용 범위 |
|---|---|---|
| 교사 | 진단, 추천, 학습, 자료 활용 | 본인 정보와 허용된 공개·기관 콘텐츠 |
| 전문가·검수자 | 루브릭, 진단·추천·문서 품질 검수 | 가명화 사례와 승인 대기 항목 |
| 기관 관리자 | 소속 교사·과정·집계 성과 관리 | 소속 기관의 최소 집계 데이터 |
| 콘텐츠 관리자 | 연수·자료·템플릿 수명주기 관리 | 콘텐츠와 권리 메타데이터 |
| 시스템 관리자 | 사용자, 모델, 운영, 보안 관리 | 승인된 운영 기능; 민감 본문 기본 마스킹 |
| 감사자 | 변경·접근·AI 실행 감사 | 읽기 전용 감사 뷰와 반출 승인 |

역할은 한 사용자가 복수 보유할 수 있다. 화면 노출은 coarse entry guard이고 실제 API 권한은 operation별 정책 ID를 사용하며, 기관·소유자·배정·resource state·요청 action은 ABAC 조건으로 추가 제한한다. 특히 TCH-015는 교사와 검수자가 같은 route를 사용하지만 [tch-015-authorization-contract.json](tch-015-authorization-contract.json)에 따라 읽기·편집·검수·내보내기 권한을 분리한다. 교사는 같은 tenant의 본인 초안을 읽고 편집·검수요청·내보내기할 수 있지만 승인할 수 없고, 검수자는 같은 tenant에서 자신에게 배정된 검수 대상의 읽기·승인/보완요청만 가능하며 편집·내보내기는 거부된다.

## 2. 정보구조

```text
공개 포털
├─ 홈 / 통합검색 / 자료상세 / 이용안내
└─ 로그인 / 가입 / 비밀번호 재설정
교사 워크스페이스
├─ 대시보드
├─ AI 역량진단 ─ 결과·근거 ─ 페르소나 확인
├─ 맞춤 연수 ─ 학습경로 ─ 실천과제
├─ 성과 리포트
├─ 문서지능 ─ 자료검색 ─ 근거기반 대화
├─ HWPX 초안 만들기 ─ 편집·검수·다운로드
└─ 알림 / 활동기록 / 개인정보·동의
운영 콘솔
├─ 역량·루브릭 / 페르소나 / 추천정책
├─ 연수·콘텐츠 / 문서수집·검수 / 템플릿
├─ 프롬프트·모델 / 평가셋·품질·비용
├─ 사용자·기관·권한 / 시범운영·FGI
├─ 성과·통계 / 감사·보안
└─ 작업·스토리지·검색색인·서비스 상태
```

## 3. 화면 목록과 완료 조건

### 3.1 공개·인증

| ID | 화면 | 핵심 요소 | 완료 조건 |
|---|---|---|---|
| PUB-001 | 홈 | 통합검색, 진단 시작, 추천 자료, 이용 흐름 | 비회원도 공개 콘텐츠 탐색 가능 |
| PUB-002 | 통합검색 | 분야·대상·형식 filter, 정렬, 검색근거 | URL에 검색상태 보존, 0건 대안 제공 |
| PUB-003 | 자료 상세 | 요약, 권리, 버전, 첨부, 관련 연수 | 접근권한과 파일 안전상태 확인 후 열기 |
| PUB-004 | 인증 | 로그인·가입·재설정·약관·MFA challenge/recovery | 오류가 계정 존재 여부를 노출하지 않음 |

### 3.2 교사 워크스페이스

| ID | 화면 | 핵심 요소 | 완료 조건 |
|---|---|---|---|
| TCH-001 | 대시보드 | 다음 행동, 진행률, 추천, 최근 문서 | 빈 상태에서도 시작 행동이 명확함 |
| TCH-002 | 프로필·동의 | 연차, 지역 범주, 복귀 여부, 관심사, 동의 | 선택정보와 필수정보를 분리하고 철회 제공 |
| TCH-003 | 진단 안내 | 목적, 비평가성, 예상 시간, 데이터 사용 | 동의·중단·재개 조건을 이해하고 시작 |
| TCH-004 | 진단 대화 | 메시지, 응답 보조, 진행도, 일시중지 | 스트리밍 중 취소 가능, 턴 유실 없이 재개 |
| TCH-005 | 진단 결과 | 역량별 점수·구간·근거·불확실도 | 점수마다 근거와 이의제기·정정 경로 제공 |
| TCH-006 | 페르소나 확인 | 상위 유형 분포, 해석, 수정 | 낙인 문구 없이 사용자가 맥락을 수정 가능 |
| TCH-007 | 맞춤 추천 | 추천 사유, 기대효과, 대안, 저장 | 보완 역량·제약·근거를 함께 표시 |
| TCH-008 | 학습경로 | 기초-심화-적용 단계, 일정, 선행조건 | 단계 순서를 조정해도 정책 위반을 안내 |
| TCH-009 | 학습·실천과제 | 콘텐츠, 체크포인트, 현장 기록 | 자동저장, 제출 전 개인정보 점검 |
| TCH-010 | 성과 리포트 | 사전·사후 비교, 활동, 성찰, 다음 추천 | 기간·버전이 명시된 PDF/화면 제공 |
| TCH-011 | 문서 검색 | 자연어·filter·결과·구조 미리보기 | 결과마다 문서·버전·위치·권리 표시 |
| TCH-012 | 근거기반 대화 | 질문, 답변, citation, 후속질문 | 근거 부족 시 답변 거절 또는 범위 축소 |
| TCH-013 | 근거 뷰어 | 원문, 페이지, 표·셀 강조, 주변 맥락 | 클릭한 citation과 정확히 같은 위치 표시 |
| TCH-014 | HWPX 초안 마법사 | 문서유형, 대상, 근거, 템플릿, 옵션 | 권리·필수입력·개인정보 검사 후 생성 |
| TCH-015 | 초안 편집·검수 | 교사 소유 초안 편집·제출·내보내기, 배정 검수자의 읽기·결정 | operation별 role+tenant+소유/배정+state guard, 승인 전 워터마크, 내보내기 이력 기록 |
| TCH-016 | 기록·알림 | 진단·추천·문서·동의·알림 이력 | 본인 데이터 내보내기·삭제 요청 가능 |

### 3.3 운영·전문가 콘솔

| ID | 화면 | 핵심 요소 | 완료 조건 |
|---|---|---|---|
| ADM-001 | 운영 대시보드 | 활성 사용자, AI 품질, 작업 실패, 보안 알림 | 집계 기간·지연·데이터 최신시각 명시 |
| ADM-002 | 역량·루브릭 | 차원, level, anchor, 가중치, version | 게시 후 불변; 새 버전으로만 변경 |
| ADM-003 | 페르소나 | 정의, feature, 금칙어, 평가 결과 | 편향 검토와 승인자 기록 후 활성화 |
| ADM-004 | 연수·콘텐츠 | 과정, 태그, 난이도, 선행조건, 권리 | 초안-검수-게시-폐기 상태전이 강제 |
| ADM-005 | 추천정책 | hard filter, ranking weight, 다양성 | offline 평가와 승인을 통과해야 배포 |
| ADM-006 | 문서 수집 | upload, 출처, 권리, ACL, 처리상태 | checksum 중복과 악성파일 검사 표시 |
| ADM-007 | 구조·OCR 검수 | 원본-추출 비교, 표·셀, 품질점수 | 낮은 confidence node 수정·재처리 가능 |
| ADM-008 | 문서 게시 | 버전, chunk, 색인, 공개범위, 폐기 | 게시 snapshot과 rollback point 생성 |
| ADM-009 | 프롬프트·모델 | provider, deployment, prompt, schema | secret 미노출, 승인된 조합만 활성화 |
| ADM-010 | AI 평가 | dataset, run, metric, regression diff | hard gate 실패 시 배포 차단 |
| ADM-011 | AI 관제 | latency, token, GPU, cost, fallback | tenant·task·model별 drill-down 제공 |
| ADM-012 | 사용자·권한 | 사용자, 기관, 역할, 동의, session, MFA 등록·복구코드 회전 | 고권한 변경에 MFA·재인증·감사 기록 |
| ADM-013 | 시범운영 | cohort, 회차, 설문, FGI, 이슈 | 200명×2회 모집·완료·개선 추적 |
| ADM-014 | 성과 분석 | 개인 가명·기관 집계·과정 효과 | 소수집단 재식별 방지 threshold 적용 |
| ADM-015 | 감사·보안 | 접근, 변경, AI egress, 이상행위 | 검색·보존·승인 반출, 수정 불가 |
| ADM-016 | 운영 상태 | health, queue, index, storage, backup | runbook 연결과 안전한 재시도 제공 |

### 3.4 Screen→route→API exact 계약

[screen-route-contracts.json](screen-route-contracts.json)은 위 36개 ID를 정확히 한 번씩 열거하고 primary URL, alias route, 허용 역할, tenant guard, API operation, event, 상태와 E2E test를 고정한다. route registry와 React Router/OpenAPI/generated client/E2E route catalog는 양방향 일치해야 한다. 화면만 있고 route/API가 없거나 사용자-facing API가 owner 화면/service 없이 남으면 완료가 아니다.

[ui-journey-contracts.json](ui-journey-contracts.json)은 12개 핵심 여정에 대해 component hierarchy, primary/secondary action, 한국어 field·copy, 390/768/1440 순서, 오류·부분·stale·권한 상태와 접근성 수용기준을 고정한다. 같은 파일의 `screen_closure`는 위 36개 화면을 빠짐없이 여정·route·상태·viewport·시각증거에 연결한다. 화면 구현은 이 두 registry의 교집합이 아니라 **모두**를 만족해야 한다.

`PUB-004`의 `/auth/mfa/challenge`, `/auth/mfa/recovery`와 `ADM-012`의 MFA enrollment/recovery는 별도 alias route지만 각 screen ID에 귀속된다. `ACTIVE_TENANT_*` guard는 token의 단일 active tenant, current membership과 resource tenant/RLS를 함께 확인하며, `*_MFA_REAUTH`는 MFA와 15분 이내 재인증을 추가한다. 공개 route는 immutable public registry만 읽고 tenant table을 우회하지 않는다.

## 4. 핵심 사용자 여정

### 4.1 진단에서 학습까지

1. 교사는 목적·비평가성·정보 이용을 확인하고 동의한다.
2. 최소 프로필을 입력하고 진단 대화를 시작한다.
3. 시스템은 답변에서 근거 후보를 추출하되 점수를 직접 생성하지 않는다.
4. 질문 정책은 미충족 역량과 불확실성이 큰 항목을 우선 탐색한다.
5. 교사는 결과의 근거와 페르소나 분포를 확인하고 잘못된 맥락을 정정한다.
6. 결정적 scoring을 재실행하고 추천·학습경로를 생성한다.
7. 학습·실천과제 후 사후 진단과 비교 리포트를 제공한다.

### 4.2 문서 검색에서 초안까지

1. 교사는 자연어로 질문하거나 자료유형·연령·주제를 선택한다.
2. 시스템은 권한 필터를 먼저 적용한 뒤 hybrid retrieval과 reranking을 수행한다.
3. 답변의 주장마다 문서 버전과 페이지·표·셀 citation을 제시한다.
4. 교사는 근거 뷰어에서 원문 주변 맥락을 확인한다.
5. 승인된 근거와 템플릿을 선택해 HWPX 초안을 만든다.
6. 개인정보·권리·필수섹션 검사를 거쳐 사람이 검수하고 다운로드한다.

### 4.3 문서 운영

`등록 → 격리검사 → 변환/OCR → 구조분석 → 품질평가 → 사람검수 → chunk/index → 게시 → 모니터링 → 폐기`

각 단계는 소유자, 시작·종료시각, 입력·출력 checksum, 도구 버전, 오류코드와 재시도 횟수를 기록한다.

## 5. 공통 화면 상태

모든 데이터 화면은 다음 상태를 명시적으로 구현한다.

- Loading: skeleton과 진행 단계, 무한 spinner 금지
- Empty: 원인과 최초 행동 제공
- Error: 사용자 메시지, 추적 ID, 안전한 재시도
- Partial: 일부 AI/provider 실패와 사용 가능한 결과 구분
- Forbidden: 필요한 권한과 문의 경로, 데이터 존재 여부 비노출
- Stale: 데이터 기준시각과 새로고침 제공
- No-answer: 근거 부족 이유, 검색범위 조정과 전문가 문의 제공
- Offline/reconnect: 미전송 입력 보존, 중복 제출 방지

## 6. 상호작용 규칙

- AI 메시지는 `AI 생성`, model policy version, 생성시각을 표시한다.
- 진단 점수와 추천은 설명·근거·불확실도·이의제기를 함께 제공한다.
- destructive action은 대상·영향을 다시 보여주며, 고위험 작업은 재인증한다.
- 긴 작업은 `202 Accepted + Job`으로 전환하고 알림·작업함에서 추적한다.
- 저장은 낙관적 UI보다 서버 확정을 우선하며 idempotency key로 중복을 방지한다.
- 표는 모바일에서 카드 대체뷰 또는 열 선택을 제공한다.

## 7. 반응형·접근성·디자인 시스템

- 구현 token, 한국어 font stack, breakpoint, grid, component state와 시각 회귀 기준의 normative source는 12 문서다. 화면에서 임의 색·간격·breakpoint를 추가하지 않는다.
- 고정 수용 viewport는 `1440×900`, `768×1024`, `390×844`이며 세 너비 모두 page-level 수평 overflow 0 px를 요구한다.
- 1440 px: 최대 1280 px 콘텐츠, 12열, 248/264 px 좌측 navigation과 4열 context panel 허용
- 768 px: 좌우 24 px 8열, drawer navigation, 2열을 의미 순서대로 1열 전환
- 390 px: 좌우 16 px 4열, 교사 핵심 하단 navigation, safe area와 sticky primary action, full-screen dialog
- 키보드만으로 모든 행동 수행, focus indicator 대비 3:1 이상
- 본문 대비 4.5:1, 큰 글자 3:1, 색상만으로 상태 전달 금지
- live region은 스트리밍 완료·오류만 알리고 token 단위 낭독을 금지
- 차트는 표·요약문을 동등 제공하고 motion 감소 설정을 따른다.
- 브랜드는 YOnLab 고유 navy·teal 계열과 자체 문구·아이콘을 사용하며 타 포털의 자산·고유 배치를 복제하지 않는다.

## 8. 분석 이벤트

개인정보 원문 대신 pseudonymous user ID와 최소 속성을 기록한다. 필수 이벤트는 `diagnosis_started`, `diagnosis_completed`, `evidence_corrected`, `recommendation_viewed`, `path_started`, `practice_submitted`, `rag_asked`, `citation_opened`, `draft_generated`, `draft_approved`, `consent_changed`이다. 이벤트 schema version과 목적을 등록하며 광고·행동 프로파일링에 사용하지 않는다.

## 9. 화면군별 시각·접근성 검증 profile

| 화면군 | 필수 layout·상태 | 필수 증거 |
|---|---|---|
| `PUB-001~004` | 공개 shell, 검색 0건, auth 오류·재설정, 긴 한국어 | `VIS-001`, `A11Y-001`, 200% zoom |
| `TCH-001~003` | 다음 행동 우선 대시보드, 첫 사용, 동의 철회 | `VIS-002`, keyboard-only, mobile safe area |
| `TCH-004~007` | queued/streaming/근거 완료/부분/거절/정책 차단/provider degraded/stale | `VIS-002`, `VIS-003`, NVDA, VoiceOver, reduced motion |
| `TCH-008~010` | 경로 재정렬, 자동저장·제출, 비교 chart·PDF | `VIS-002`, keyboard-only, Korean font fallback |
| `TCH-011`, `TCH-013~015` | citation 6상태, 표·셀 강조, 복잡 HWPX, long-running job | `VIS-004`, ACL 회수 E2E, Korean font fallback |
| `TCH-012` | AI 상태 machine 전체와 citation 6상태의 조합 | `VIS-003`, `VIS-004`, NVDA, ACL 회수 E2E |
| `TCH-016` | 이력 없음/다수, export/delete pending·complete·failed | `VIS-002`, keyboard, 390 px reflow |
| `ADM-001~016` | comfortable/compact, 0/1k rows, 권한 거부, 장애·부분 데이터 | `VIS-005`, high contrast, cross-browser critical flow |

정상 default screenshot만으로 화면 완료를 선언하지 않는다. 12 문서의 상태 machine, `VIS-*`, `XBR-*`, `A11Y-*` 항목이 exact candidate commit에서 fresh PASS여야 `GATE-UX-ACCESSIBILITY`를 PASS로 판정한다. 6개 대표 family와 12개 operational profile은 `TCH-006`에서 낙인형 label이 아니라 상위 3개 profile 분포, 6-family 집계, 전체 펼침과 사용자 정정 행동으로 제시한다.

## 10. 최종 문서 인계

화면 설계의 최종본, 접근성·시각 회귀 보고서, 사용자·관리자 manual과 PDF bundle의 경로·owner·gate는 [14. 최종 설계·운영·시험 문서 산출물 계약](14-final-document-deliverables.md)을 따른다. 화면·token 변경은 해당 문서, manual screenshot, 시험 증거와 `artifact-manifest.json`을 같은 release candidate에서 함께 갱신한다.
