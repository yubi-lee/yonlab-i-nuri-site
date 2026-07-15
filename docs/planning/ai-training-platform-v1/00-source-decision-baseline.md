# 00. 원천·의사결정 기준선

문서 ID: SRC-CDR-000  
기준일: 2026-07-13

## 1. 기준 문서

| 우선순위 | 원천 | 적용 원칙 |
|---:|---|---|
| 1 | 제안요청서 `보육교사 맞춤형 연수혁신 AI 서비스 고도화-조달의견반영` | 계약 범위·필수 요구·보안·시험·사업관리의 최상위 기준 |
| 2 | 발주기관과 사용자가 승인한 목표 설계 결정 | RFP 목적을 훼손하지 않는 구현·운영 방식 확정 |
| 3 | `와이온랩_보육교사 맞춤형 연수혁신 AI 서비스 고도화 제안서_v0.4_개발설계보강` | 정량목표, 기술구조, 수행·검증 방안 구체화 |
| 4 | 기존 YOnLab repository와 설계·운영 산출물 | 시험으로 적합성이 확인된 자산만 재사용 |
| 5 | UniClaudeProxy pinned source 분석 | 멀티 provider/RAG 개념 참고; production 채택은 별도 보안 gate |

하위 문서가 상위 문서와 충돌하면 상위 문서를 따른다. 충돌이 기능·비용·일정·보안에 영향을 주면 ChangeRequest와 CDR을 생성하고 승인 전 baseline을 바꾸지 않는다.

이 v1.1 문서셋에서 반복되는 경로, KPI 계산식·한계값, 페르소나 계층, 복구 목표 승인 상태와 판정 상태는 [design-baseline.json](design-baseline.json)을 normative source로 삼는다. Narrative 표기는 그 기준선의 사람이 읽을 수 있는 mirror이며 변경은 같은 ChangeRequest에서 함께 반영한다.

## 2. 사업 기준

| 항목 | 기준 |
|---|---|
| 사업명 | 보육교사 맞춤형 연수혁신 AI 서비스 고도화 |
| 기간 | 계약 후 180일 |
| 사업금액 | 422,000천원, 부가세 포함 |
| 시범운영 | 보육교사 200명 대상 2회 |
| 현장검증 | 교사 피드백, 개발 집중 워크숍, 전문가 자문·FGI |
| 핵심 범위 | AI 대화 역량진단, 6개 대표 family·12개 versioned operational profile, 맞춤 추천·경로·성과, Document AI/HWP RAG·초안, UI/UX, 운영·검증 |
| 비용 책임 기준 | 사업기간 중 AI·OCR·embedding·외부 API 등 과업 수행비용을 수행계획에 포함 |

## 3. 목표 시스템 결정

RFP의 기능·품질·연계 목적을 충족하면서 YOnLab이 독립적으로 배포·시험·운영할 수 있는 플랫폼을 구축한다. i-누리 등 외부 포털은 공개·승인 API, SSO, deep link, metadata sync Adapter로 연결한다. 이 결정은 특정 외부 포털의 코드·자산·배포권한에 의존하지 않고도 시범운영과 수용시험을 수행하도록 하며, 실제 연계 계약이 확정되면 동일 canonical contract로 Adapter만 교체하게 한다.

## 4. 제안 성과목표의 설계 반영

| 제안 목표 | 목표값 | 설계·시험 연결 |
|---|---:|---|
| KPI-001 전문가 진단 일치도 | ≥0.85 | SYS-F-001~003, T-AI-001~004 |
| KPI-002 추천 적합도 | ≥90% | SYS-F-004~005, T-REC-001~007 |
| KPI-003 RAG Top-5 hit rate | ≥95% | SYS-F-008~010, T-DOC-008 |
| KPI-004 중요 claim citation coverage | ≥95%, invalid citation 0건 | SYS-F-011, T-DOC-009 |
| KPI-005 구조화 출력 성공률 | ≥99.8% | SYS-F-001, SYS-F-012~013, `T-KPI-005`, [27-cell matrix](kpi-005-structured-output-matrix.json) |
| KPI-006 사용자 만족도 | ≥90/100 | SYS-F-014, T-PILOT-006 |
| KPI-007 시범운영 개선 반영률 | ≥90% | SYS-F-016, T-PILOT-003~006 |
| KPI-008 Restricted 외부 전송 | 0건 | SYS-F-013, T-PRIV-004 |
| KPI-009 접근성 핵심 여정 오류 | 0건 | SYS-F-014, T-A11Y-001~008 |
| KPI-010 백업 복구 | 승인 RPO/RTO 충족률 ≥1.0(100%); 승인 전 `REQUIRES_ACCEPTANCE_DATA` | SYS-NF-012, T-DR-001~005 |

## 5. 기능 기준화

### 5.1 AI 진단

- 정형 설문 단독 방식이 아니라 상태기계 기반 대화로 evidence를 수집한다.
- 자유발화는 역량코드·근거구간·신뢰도·상충·보류로 구조화한다.
- 루브릭·점수·추천정책·페르소나·프롬프트·모델을 version으로 고정한다.
- 진단 결과는 추천, 학습경로, 실천과제, 사후진단, 리포트로 연결한다.

### 5.2 Document AI

- HWPX Native, HWP converter, PDF/OCR fallback, 사람 검수의 계층 경로를 사용한다.
- 문단·목록·표·중첩·병합셀·이미지·서식과 원문 locator를 보존한다.
- BM25, vector, metadata, RRF, reranking을 결합한다.
- 답변은 문서명뿐 아니라 version, 페이지 또는 section/block, 표·문단 근거를 제공한다.
- 가정 안내문, 활동계획안, 관찰기록 예시, checklist 등은 승인 template과 근거로 HWPX 초안을 생성한다.

### 5.3 연관 기능

- 자료·연수·상담지식·성과를 교사 한 명의 연속 동선으로 연결한다.
- 영상·음성 자료는 transcript·timestamp evidence Adapter를 확장점으로 포함하며, HWP/HWPX 필수 수용범위를 침해하지 않는 독립 작업으로 구현한다.
- 관리자에게 시범 참여, 진단 완료, 추천 수용, 검색 성공, 만족, 문서 오류, AI 비용·품질을 제공한다.
- 모든 핵심 흐름을 Trace ID와 version manifest로 재현한다.
- 60개 RFP·33개 시스템 요구·개별 시험 edge의 단일 machine source는 [requirements-test-registry.json](requirements-test-registry.json), 36개 화면의 route/guard/API/state/E2E source는 [screen-route-contracts.json](screen-route-contracts.json)이다.
- 구현 입력의 누락을 막는 machine contract는 [OpenAPI 3.1](platform-openapi.json), [AsyncAPI 3.0](platform-asyncapi.json), [AI service payload](ai-service-contracts.json), [영속 도메인 catalog](persistent-domain-catalog.json), [RAG·문서품질 golden vector](rag-policy-golden-vectors.json), [provider 의사결정 registry](provider-decision-registry.json), [기존 자산 재사용 matrix](legacy-reuse-decision-matrix.json), [UI journey contract](ui-journey-contracts.json)다. 이 파일들은 [독립 fail-closed 검증기](verify-completeness-contracts.py)와 mutation test로 함께 검증한다.

## 6. 재사용 기준

다음 조건을 모두 만족하는 기존 자산만 재사용한다.

1. 목표 API·데이터·권한·version 계약과 일치한다.
2. 단위·통합·보안 회귀시험이 존재하거나 먼저 추가할 수 있다.
3. license와 clean-room 근거가 명확하다.
4. secret·개인정보·provider를 직접 결합하지 않는다.
5. 운영 관측·오류·rollback이 목표 설계에 연결된다.

인증 rotation/reset, PostgreSQL migration, 관리자 bootstrap, Docker 격리 검증, backup/restore, CMS·Playwright·synthetic seed 패턴은 우선 검토한다. 목표 계약에 맞지 않는 거대 모듈, 권한 없는 endpoint, provider 직접호출, 근거·version이 없는 AI 결과는 characterization test 후 교체한다.

구현 착수 전 자산별 판정과 보존 시험은 [legacy-reuse-decision-matrix.json](legacy-reuse-decision-matrix.json)을 따른다. `REUSE`와 `ADAPT`도 characterization test가 없으면 허용하지 않으며, notice/article/FAQ와 100개 synthetic content pack은 포털 공개탐색 능력을 보존하되 승인된 운영 콘텐츠로 오인시키지 않는다.

## 7. 해석 규칙

- `AI 진단 정확도`는 모델이 임의 생성한 점수가 아니라 전문가 rubric과 시스템 결과의 합치로 측정한다.
- `출처 제시`는 문서명 표시가 아니라 접근 가능한 특정 version·위치의 locator 검증을 뜻한다.
- `HWP 초안`은 검수 전 완성 문서가 아니며 승인 template과 근거를 가진 편집 가능한 산출물이다.
- `페르소나`는 사람의 고정 유형이나 인사정보가 아니라 학습 지원을 위한 수정 가능한 확률 context다. 추론은 12개 operational profile probability와 그 합으로 만든 6개 family aggregation을 함께 낸다.
- `완료`는 기능 존재가 아니라 요구-설계-코드-시험-증거의 연결과 수용 기준 통과를 뜻한다.
