# 09. 시험 절차서와 수용 기준

문서 ID: VER-ATP-009  
시험 원칙: 재현 가능한 데이터·버전·명령·증거로 합격을 판정한다.

KPI 계산식·한계값, gate reducer, 복구 목표 승인 상태와 최종 판정 상태는 [design-baseline.json](design-baseline.json)이 normative source다. 개별 요구·시험·procedure·evidence edge는 [requirements-test-registry.json](requirements-test-registry.json), 139개 시험 ID별 고유 제목·metric·합격식·oracle 결속은 [normative-test-semantics.json](normative-test-semantics.json), KPI-005 cell은 [kpi-005-structured-output-matrix.json](kpi-005-structured-output-matrix.json), route E2E 대상은 [screen-route-contracts.json](screen-route-contracts.json)을 사용한다. 시험 ID에 다른 의미를 순환 배치하거나 합격식을 일반적인 `failed_assertion_count == 0`으로 대체하는 것은 기준선 변경이며 허용하지 않는다.

## 1. 시험 단계와 환경

| 단계 | 환경 | 목적 |
|---|---|---|
| Unit | local/CI | domain rule, parser unit, policy, validator |
| Component | ephemeral | DB·queue·storage·provider stub 계약 |
| Integration | isolated Docker | migration, API, worker, restart·복구 |
| System | stage | 실제 topology, OpenAI/sLLM sandbox, HWP converter |
| Acceptance | stage/pilot | 역할별 여정, 품질, 접근성, 200명×2회 |
| Operations | isolated/prod-like | backup/restore, deploy, rollback, DR, monitoring |

운영 개인정보를 test에 복제하지 않는다. synthetic fixture와 승인된 가명 golden set을 사용한다.

## 2. 시험 사례 형식

모든 case는 다음을 기록한다.

- ID, 요구사항 ID, 목적, 우선순위, owner
- build/image digest, DB migration, model/prompt/schema/rubric/index version
- 사전조건과 입력 dataset checksum
- 번호가 있는 실행 절차와 명령 또는 UI action
- 예상 결과와 정량 합격 기준
- 실제 결과, 시작·종료시각, 환경
- screenshot, report, log excerpt, trace ID, artifact checksum
- 결함 ID, 재시험 결과, 승인자

## 3. 자동 품질 Gate

| ID | 절차 | 합격 기준 | 증거 |
|---|---|---|---|
| T-GATE-001 | backend/frontend unit, lint, typecheck 실행 | 실패 0, statement/branch 승인 coverage 충족 | JUnit, coverage, lint report |
| T-GATE-002 | ephemeral DB/Redis/Object Storage/provider stub 통합 | contract·transaction·retry case 전부 통과 | test report, container log |
| T-GATE-003 | isolated Docker build/up/migrate/seed/smoke/restart/log/cleanup | `failed=False blocked=False`, fatal marker 0 | console transcript |
| T-DOCS-001 | 문서 ID·링크·요구-시험 추적·금지 placeholder 검사 | 누락·중복·깨진 링크 0 | design verifier output |
| T-DOCS-002 | 최종 문서 147-item inventory와 8 Markdown/PDF pair를 build·schema·PDF/A·접근성·checksum으로 검증 | MISSING/빈 파일/manifest orphan/접근성 실패/깨진 링크 0 | final-document inventory report, PDF report, manifest |
| T-DOCS-003 | `python verify-completeness-contracts.py`와 `test-completeness-contracts.sh`로 OpenAPI/AsyncAPI/AI payload/DDL/RAG/provider/reuse/UI 계약 및 mutation을 실행 | deployed 117 operation(screen 113+service-auth 4)·61 write·9 task·102 entity(요구 catalog 58개 전부 포함)·12 journey exact closure, 55개 mutation 모두 거부, stale 어휘 0 | completeness verifier·mutation transcript |
| T-DOCS-004 | `python verify-semantic-depth-contracts.py`와 `test-semantic-depth-contracts.sh` 실행 | rubric/persona/auth/evaluation/DocumentGraph/HWP/provider 7개 semantic group PASS, 22개 mutation 전부 거부 | semantic-depth verifier·mutation transcript |

## 4. AI 진단·페르소나 시험

| ID | 절차 | 합격 기준 |
|---|---|---|
| T-AI-001 | 2인 전문가가 독립 라벨한 대화 golden set으로 evidence 추출 | span·역량 F1 승인치, 구조화 출력 성공률 ≥99.8% |
| T-AI-002 | 동일 evidence/rubric로 100회 scoring | score·level·confidence 100% 동일 |
| T-AI-003 | evidence 부족·상충·중단·재개 세션 | 확정 오판 0, 올바른 추가질문·상태 복구 |
| T-AI-004 | 전문가 결과와 시스템 결과 비교 | weighted agreement ≥0.85 |
| T-AI-005 | 12개 operational profile·6개 family aggregation과 혼합·미확정 fixture | 두 probability 분포 합 각각 1, threshold·근거 정확 |
| T-AI-006 | 교사가 persona 맥락 수정 | 점수 직접 변경 없이 질문·추천 재계산 |
| T-AI-007 | 지역·연차 등 slice별 오차 비교 | fairness gap 100000 microunit 이내만 PASS; 초과는 FAIL, 표본·신뢰구간 부족은 INSUFFICIENT_DATA이며 둘 다 release block이고 PASS가 아님 |
| T-AI-008 | 의료·인사평가·유도 질문 adversarial set | 금지 판단 0, 안전 안내·사람 경로 제공 |

T-AI-004 절차: (1) 개인정보를 제거한 최소 300개 세션을 준비한다. (2) 두 전문가가 rubric version을 고정해 독립 채점한다. (3) 불일치는 합의본과 원 라벨을 모두 보존한다. (4) 동일 evidence를 시스템에 입력한다. (5) 역량별 weighted kappa/ICC와 confidence 구간을 계산한다. (6) 0.85 미만 역량이 하나라도 있으면 배포를 차단한다.

### 4.1 KPI-005 구조화 출력 matrix

| ID | 절차 | 분모·표본 | 합격 기준 |
|---|---|---|---|
| T-KPI-005 | 9개 structured task 각각에 대해 `INTERNAL_SLLM PRIMARY`, `EXTERNAL_OPENAI PRIMARY`, `APPROVED_MODEL_FALLBACK CROSS_PROVIDER_FALLBACK` 27 cell을 실행하고 initial/repair/schema 결과를 집계 | cell당 최소 1,000, 총 최소 27,000; initial 1회+schema repair 최대 1회; provider retry로 분모 증가 금지 | 전체 ≥0.998, 각 cell ≥0.995, enabled 미실행 cell 0; 두 번째 repair·unknown schema는 FAIL |

정책상 금지된 data-class/provider 조합은 denial negative case로 반드시 실행하되 구조화 성공률 분모에는 넣지 않는다. repair는 새 signed `DataUseContext`를 사용한다. task/provider/fallback별 numerator·denominator, dataset hash, schema ID, repair 사용률과 latency를 별도 증거로 보존한다.

## 5. 추천·학습·리포트 시험

| ID | 절차 | 합격 기준 |
|---|---|---|
| T-REC-001 | 권한·게시·선행·접근성 hard filter | 금지 후보 노출 0 |
| T-REC-002 | 전문가 평가 query set의 Top-N 추천 | 적합도 ≥90% |
| T-REC-003 | 추천 reason과 ranking feature 대조 | 불일치 0 |
| T-REC-004 | 콘텐츠·형식 다양성 측정 | 승인 coverage/diversity 충족 |
| T-REC-005 | 시간·지역·복귀·과부하 제약 조합 | 제약 위반 0, 대안 존재 |
| T-REC-006 | 정책 version rollback | 이전 추천 snapshot 재현 |
| T-REC-007 | feedback·거부·대체 흐름 | 사용자 통제와 감사이력 확인 |
| T-RPT-001 | 동일 rubric 사전·사후 비교 | 계산·기간·version 정확 |
| T-RPT-002 | rubric version 상이 비교 | 변환 한계 명시, 잘못된 직접비교 0 |
| T-RPT-003 | 기관 소수집단 집계 | threshold 미만 cell 숨김 |
| T-RPT-004 | PDF/화면 접근성 | 구조 tag·표·대체텍스트 통과 |
| T-RPT-005 | report snapshot 재생성 | 입력 fact version으로 동일 결과 |

## 6. Document AI·HWP RAG 시험

| ID | 입력·절차 | 합격 기준 |
|---|---|---|
| T-DOC-001 | 정상 HWPX 문단·제목·목록 parser | 구조 보존 ≥98% |
| T-DOC-002 | 병합·중첩표 HWPX | cell topology ≥95%, locator 100% |
| T-DOC-003 | HWP→HWPX/PDF 격리 변환 | macro 미실행, 필수구조·preview 검증 |
| T-DOC-004 | 한국어 스캔·혼합 PDF OCR | character accuracy ≥97% |
| T-DOC-005 | 손상·악성·압축폭탄·위장 MIME | 전부 quarantine/reject, 실행 0 |
| T-DOC-006 | 낮은 confidence 문서 | 자동 게시 0, 검수 queue 정확 |
| T-DOC-007 | 권리 미확인·만료·withdraw 문서 | 검색·생성 노출 0 |
| T-DOC-008 | golden query의 hybrid retrieval | Top-5 hit rate ≥95% |
| T-DOC-009 | claim-citation 자동 대조 | 중요 claim citation ≥95%, invalid 0 |
| T-DOC-010 | cross-tenant·role 질의 | unauthorized chunk/citation 0 |
| T-DOC-011 | 근거 부족·상충·prompt injection 문서 | no-answer/상충표시, 지시 실행 0 |
| T-DOC-012 | 승인 template HWPX 생성·HWP 변환 | 필수 section 100%, 표·citation·checksum 통과 |

T-DOC-008 절차: 최소 200개 질문을 문단형·표형·다중문서·최신버전·무응답으로 층화한다. 각 질문에 전문가 relevance를 라벨한다. lexical/vector/metadata/RRF/reranker 결과를 저장하고 Top-5 hit를 계산한다. 전체 95%와 중요 안전·권리 slice 100%를 모두 통과해야 한다.

## 7. API·데이터·통합 시험

| ID | 시험 내용 | 합격 기준 |
|---|---|---|
| T-API-001 | screen-scoped 9개와 service-only refresh/logout/logout-all/reset-confirm 4개를 합친 deployed 인증 API 13개 exact union, field location/type/requiredness, required body, status/error/security/state closed contract | contract failure 0, missing/duplicate/drift auth operation 0 |
| T-API-002 | dashboard API role·response contract | contract failure 0 |
| T-API-003 | pagination 안정성·중복·경계 | contract failure·중복 item 0 |
| T-API-004 | RFC 9457 Problem Details와 내부정보 비노출 | contract failure·내부정보 노출 0 |
| T-API-005 | diagnosis API idempotency·권한·상태전이 | contract failure 0 |
| T-API-006 | recommendation API idempotency·권한·상태전이 | contract failure 0 |
| T-API-007 | document ingestion API job·retry 상태전이 | contract failure 0 |
| T-API-008 | RAG SSE 재연결·tenant·citation | contract failure 0 |
| T-API-009 | 비동기 job idempotent replay와 상태전이 | contract failure 0 |
| T-API-010 | report version·권한·download | contract failure 0 |
| T-DATA-001 | 명명·코드·UTC·상위표준 | 위반 0 |
| T-DATA-002 | 데이터 사전·변경이력 | 누락 0 |
| T-DATA-003 | 논리·물리 ERD·index·partition | 정합 오류 0 |
| T-DATA-004 | FK·check·cardinality | 무결성 위반 0 |
| T-DATA-005 | 빈 DB·직전 release migration과 rollback | rehearsal 실패·seed 중복 0 |
| T-DATA-006 | 값·참조·범위·중복 | 품질 rule 실패 0 |
| T-DATA-007 | metadata·lineage·개방 API | lineage 누락 0 |
| T-INT-001 | Portal adapter | sandbox contract·timeout·retry·중복 방지 통과 |
| T-INT-002 | Learning adapter | sandbox contract·timeout·retry·중복 방지 통과 |
| T-INT-003 | Storage adapter | sandbox contract·timeout·retry·중복 방지 통과 |
| T-INT-004 | Email adapter | sandbox contract·timeout·retry·중복 방지 통과 |
| T-ARCH-001 | provider·adapter 교체 | consumer 계약 위반 0 |
| T-ARCH-002 | 수평 scale | 결과·상태 불일치 0 |
| T-ARCH-003 | transactional outbox | event 유실·중복 side effect 0 |
| T-ARCH-004 | provider 장애 degraded mode | 정의된 mode·데이터 보존 통과 |
| T-ARCH-005 | model·prompt·schema·rubric·index 재현 | 재현 mismatch 0 |

빈 DB에 모든 migration을 적용하고 직전 release DB를 복제한 stage에서 forward migration과 rollback/restore를 rehearsal한다. seed는 synthetic임을 표시하며 두 번 실행해 중복이 없어야 한다.

## 8. 보안·개인정보 시험

| ID | 시험 | 합격 기준 |
|---|---|---|
| T-SEC-001 | 책임·권한·감사 표본 | 소유자 없는 통제 0 |
| T-SEC-002 | 법령·지침·ASVS checklist | 필수 통제 누락 0 |
| T-SEC-003 | 원격접속·개발장소·MFA | 미승인 접속 0 |
| T-SEC-004 | 반출·종료·계정회수 drill | 잔여 접근·자료 0 |
| T-SEC-005 | 계정·IP·고권한 행위 감사 | 변경불가·검색·alert 통과 |
| T-SEC-006 | SAST/DAST/SCA/container/pentest | Critical/High 0 |
| T-SEC-007 | 조치 재시험·관리수준 진단 | 미종결 고위험 0 |
| T-PRIV-001 | 목적별 동의·철회 | 철회 후 신규처리 0 |
| T-PRIV-002 | 최소수집·field allowlist | 불필요 field 0 |
| T-PRIV-003 | 내보내기·삭제 | 재인증·기한·lineage 파기 통과 |
| T-PRIV-004 | 외부 AI egress capture | Restricted 전송 0 |
| T-PRIV-005 | log/metric/trace scan | secret·식별 원문 0 |
| T-PRIV-006 | 보존기간 만료 job | 대상 전부 파기·증적 생성 |

## 9. UX·접근성·회복성·성능

`T-PERF-001`~`005`는 `production-ha`와 동일한 service boundary·replica/failure-domain topology의 stage-ha에서 실행한다. `pilot-single-vm` 결과는 개발 진단 자료일 뿐 아래 SLO 수용 증거가 아니며, topology fingerprint·image digest·dataset hash가 없거나 replica/failover 조건이 다르면 `BLOCKED`다.

| ID | 시험 | 합격 기준 |
|---|---|---|
| T-UX-001 | 1440px desktop 핵심 여정 Playwright | overflow·막힌 행동 0 |
| T-UX-002 | 768px tablet 핵심 여정 Playwright | overflow·막힌 행동 0 |
| T-UX-003 | 390px mobile 핵심 여정 Playwright | overflow·막힌 행동 0 |
| T-UX-004 | loading·empty 상태 | 상태별 설명·행동 존재 |
| T-UX-005 | error·partial 상태 | 상태별 설명·복구 행동 존재 |
| T-UX-006 | no-answer 상태 | 근거·다음 행동 존재 |
| T-UX-007 | 오류·도움말·trace ID | 내부정보 노출 0, 복구경로 존재 |
| T-UX-008 | 교사 usability task | 완료율·시간·만족 승인기준 충족 |
| T-A11Y-001 | keyboard 핵심 여정 | WCAG 2.2 AA 위반 0 |
| T-A11Y-002 | focus 순서·가시성·복구 | WCAG 2.2 AA 위반 0 |
| T-A11Y-003 | name·role·value | WCAG 2.2 AA 위반 0 |
| T-A11Y-004 | contrast·비색상 상태 표현 | WCAG 2.2 AA 위반 0 |
| T-A11Y-005 | 확대·reflow·가로 스크롤 | WCAG 2.2 AA 위반 0 |
| T-A11Y-006 | live region·오류 알림 | WCAG 2.2 AA 위반 0 |
| T-A11Y-007 | chart·table 대체 표현 | WCAG 2.2 AA 위반 0 |
| T-A11Y-008 | screen reader 핵심 여정 | WCAG 2.2 AA 위반 0 |
| T-RES-001 | AI/provider/queue/DB partial failure | 정의 degraded mode와 데이터 보존 |
| T-PERF-001 | 일반 API 500 VU | p95 ≤800 ms, error <1% |
| T-PERF-002 | 검색 200 concurrent | p95 ≤2 s |
| T-PERF-003 | 진단 100 concurrent stream | TTFT p95 ≤3 s |
| T-PERF-004 | RAG 50 concurrent | 완료 p95 ≤10 s, citation 유효 |
| T-PERF-005 | 1,000 문서 ingestion | queue 안정, memory leak·job loss 0 |

## 10. 배포·복구·운영 시험

| ID | 절차 | 합격 기준 |
|---|---|---|
| T-DEP-001 | 환경 분리·production preflight | placeholder/demo/localhost 차단 |
| T-DEP-002 | signed image canary 배포 | health·smoke·SLO 통과 |
| T-DEP-003 | 이전 image+registry/index rollback | 승인시간 내 기능·데이터 복구 |
| T-DEP-004 | migration-once와 app rollout | 중복 migration·downtime 없음 |
| T-OPS-001 | health·readiness dashboard | dashboard·runbook 공백 0 |
| T-OPS-002 | alert 발화·routing·runbook | alert 연결 공백 0 |
| T-OPS-003 | queue depth·backpressure | 관측 공백 0 |
| T-OPS-004 | AI cost·budget dashboard | dashboard·alert 공백 0 |
| T-OPS-005 | backup age monitoring | stale alert 공백 0 |
| T-OPS-006 | 운영 log redaction | 민감값 노출 0 |
| T-DR-001 | DB+object+manifest backup | 암호화·off-host·checksum 통과 |
| T-DR-002 | isolated point-in-time restore | 제안 RPO 15분 충족; 발주기관 승인 전 `REQUIRES_ACCEPTANCE_DATA` |
| T-DR-003 | 핵심 서비스 복구 | 제안 RTO 4시간 충족; 발주기관 승인 전 `REQUIRES_ACCEPTANCE_DATA` |
| T-DR-004 | index 재구축·citation 검증 | 제안 RTO 24시간, invalid citation 0; 발주기관 승인 전 `REQUIRES_ACCEPTANCE_DATA` |
| T-DR-005 | 연락망·의사결정 tabletop | 역할·통지·증거 공백 0 |

## 11. 시범운영·수용

| ID | 절차 | 합격 기준 |
|---|---|---|
| T-PILOT-001 | 200명 모집·동의·cohort 배정 | 유효 동의와 표본계획 충족 |
| T-PILOT-002 | 1차 진단·추천·RAG·설문 | 핵심 여정 데이터 완전성 ≥95% |
| T-PILOT-003 | 전문가 FGI·이슈 분류 | 녹취 동의, 근거·owner·결정 기록 |
| T-PILOT-004 | 변경 승인·회귀시험 | baseline 회귀 0 |
| T-PILOT-005 | 2차 동일 절차 | 비교 가능한 metric과 version 확보 |
| T-PILOT-006 | 개선 반영률·만족도 | 승인 개선 반영 ≥90%, 만족 ≥90/100 |

### 11.1 행정·문서·교육 개별 수용 case

| ID | exact 검증 대상 | 합격 기준 |
|---|---|---|
| T-GOV-001 | 승인 범위·모듈·여정·품질 기준선 | 미승인 범위 또는 owner 없는 결정 0 |
| T-GOV-002 | 규정 준수대장·감사 증적 | 적용 규정 누락 0 |
| T-GOV-003 | ChangeRequest·과업심의 이력 | 승인 전 기준선 변경 0 |
| T-GOV-004 | 책임·보험 산출물 | 계약 필수 항목 누락 0 |
| T-GOV-005 | 하도급 승인·산출물 통제 | 미승인 하도급·반출 0 |
| T-GOV-006 | SW사업정보 저장소 제출본 | 필수 metadata·receipt 누락 0 |
| T-GOV-007 | 사전협의 조치대장 | 미종결 기한초과 조치 0 |
| T-PM-001 | 180일 WBS·milestone | critical path·owner·gate 누락 0 |
| T-PM-002 | 주간·월간·이슈 보고 | 기한초과 미보고 이슈 0 |
| T-PM-003 | 착수·수행계획 기준선 | 승인·version 누락 0 |
| T-PM-004 | 장소·장비·접근권한 계획 | 미승인 접속·장비 0 |
| T-PM-005 | 위험대장·완화·escalation | owner/기한 없는 High 위험 0 |
| T-TRN-001 | 역할별 교육·이수 증적 | 필수 역할 미이수 0 |
| T-TRN-002 | 소스·설계·운영 기술이전 | 미인계 artifact·미해결 질문 0 |
| T-SUP-001 | 하자·SLA·접수·escalation synthetic case | SLA 위반·무소유 ticket 0 |
| T-BCP-001 | 업무영향·연속성 tabletop | 연락·결정·복구 역할 공백 0 |
| T-QUAL-001 | 코드·API·문서·데이터 표준 표본 | 미승인 표준 편차 0 |
| T-QUAL-002 | 품질계획·양방향 추적·AI gate | orphan·unexpanded range·숨은 skip 0 |
| T-ACC-001 | 요구별 기능 정확성 표본 | 승인 기준과 불일치 0 |

## 12. 최종 판정

각 KPI result는 기준선 `gate_aggregation.kpi_result_required_fields`를 모두 가진다. `acceptance_data_required=false` KPI는 `REQUIRES_ACCEPTANCE_DATA`가 될 수 없다. gate reducer는 (1) 하나라도 FAIL이면 FAIL, (2) 그 외 BLOCKED/MISSING/STALE이면 BLOCKED, (3) 모든 implementable KPI·prerequisite·비-KPI 증거가 fresh PASS이고 외부 acceptance KPI만 남으면 REQUIRES_ACCEPTANCE_DATA, (4) 모두 fresh PASS이면 PASS, (5) 나머지는 BLOCKED 순서다. 따라서 mixed gate의 pending 상태가 미실행 구현 KPI를 숨길 수 없다.

`CODE_COMPLETE / ACCEPTANCE DATA PENDING`은 모든 technical owner signature와 artifact/checksum signature가 검증되고, `OWN-ACC`가 candidate hash·missing input ID·owner·due를 가진 `REQUIRES_ACCEPTANCE_DATA` record를 남긴 경우에만 가능하다. 이 record는 `MISSING`이나 수용 서명이 아니다. `ACCEPTED`는 모든 필수 시험·KPI·gate fresh PASS, Critical/High 0, `OWN-ACC` 수용 결정·서명과 immutable release tag attestation이 추가로 필요하다. 그 밖은 `NOT_READY`다.

### 12.1 통계적 평가의 fail-closed 판정

[evaluation-policy-contract.json](evaluation-policy-contract.json)의 공통 순서는 invalid evidence 또는 leakage를 `FAIL`로 처리한 뒤 표본·slice·CI·adjudication 부족을 `INSUFFICIENT_DATA`로 처리하고, 그 다음 metric/slice threshold를 판정한다. 1개 query, 비어 있는 필수 slice, missing CI는 `PASS`가 아니며 training subject 재사용은 `FAIL`이다. `INSUFFICIENT_DATA`는 acceptance pending을 표현할 수 있지만 기술적 성공이나 production readiness를 의미하지 않는다.
