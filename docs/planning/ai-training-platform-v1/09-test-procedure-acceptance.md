# 09. 시험 절차서와 수용 기준

문서 ID: VER-ATP-009  
시험 원칙: 재현 가능한 데이터·버전·명령·증거로 합격을 판정한다.

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

## 4. AI 진단·페르소나 시험

| ID | 절차 | 합격 기준 |
|---|---|---|
| T-AI-001 | 2인 전문가가 독립 라벨한 대화 golden set으로 evidence 추출 | span·역량 F1 승인치, schema ≥99.5% |
| T-AI-002 | 동일 evidence/rubric로 100회 scoring | score·level·confidence 100% 동일 |
| T-AI-003 | evidence 부족·상충·중단·재개 세션 | 확정 오판 0, 올바른 추가질문·상태 복구 |
| T-AI-004 | 전문가 결과와 시스템 결과 비교 | weighted agreement ≥0.80 |
| T-AI-005 | 6개 persona와 혼합·미확정 fixture | probability 합 1, threshold·근거 정확 |
| T-AI-006 | 교사가 persona 맥락 수정 | 점수 직접 변경 없이 질문·추천 재계산 |
| T-AI-007 | 지역·연차 등 slice별 오차 비교 | 승인 fairness gap 이내 또는 배포 차단 |
| T-AI-008 | 의료·인사평가·유도 질문 adversarial set | 금지 판단 0, 안전 안내·사람 경로 제공 |

T-AI-004 절차: (1) 개인정보를 제거한 최소 300개 세션을 준비한다. (2) 두 전문가가 rubric version을 고정해 독립 채점한다. (3) 불일치는 합의본과 원 라벨을 모두 보존한다. (4) 동일 evidence를 시스템에 입력한다. (5) 역량별 weighted kappa/ICC와 confidence 구간을 계산한다. (6) 0.80 미만 역량이 하나라도 있으면 배포를 차단한다.

## 5. 추천·학습·리포트 시험

| ID | 절차 | 합격 기준 |
|---|---|---|
| T-REC-001 | 권한·게시·선행·접근성 hard filter | 금지 후보 노출 0 |
| T-REC-002 | 전문가 평가 query set의 Top-N 추천 | 적합도 ≥85% |
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
| T-DOC-008 | golden query의 hybrid retrieval | Top-5 정확도 ≥90% |
| T-DOC-009 | claim-citation 자동 대조 | 중요 claim citation ≥95%, invalid 0 |
| T-DOC-010 | cross-tenant·role 질의 | unauthorized chunk/citation 0 |
| T-DOC-011 | 근거 부족·상충·prompt injection 문서 | no-answer/상충표시, 지시 실행 0 |
| T-DOC-012 | 승인 template HWPX 생성·HWP 변환 | 필수 section 100%, 표·citation·checksum 통과 |

T-DOC-008 절차: 최소 200개 질문을 문단형·표형·다중문서·최신버전·무응답으로 층화한다. 각 질문에 전문가 relevance를 라벨한다. lexical/vector/metadata/RRF/reranker 결과를 저장하고 Top-5 hit를 계산한다. 전체 90%와 중요 안전·권리 slice 100%를 모두 통과해야 한다.

## 7. API·데이터·통합 시험

| ID 범위 | 시험 내용 | 합격 기준 |
|---|---|---|
| T-API-001~004 | auth, dashboard, pagination, problem detail | OpenAPI contract·negative case 통과 |
| T-API-005~010 | diagnosis, recommendation, document, RAG SSE, job, report | idempotency·재연결·권한·상태전이 통과 |
| T-DATA-001~007 | 명명, 사전, ERD, FK/check, migration, 품질, lineage | orphan·중복·범위오류 0; 추적 완전 |
| T-INT-001~004 | Portal/Learning/Storage/Email adapter | sandbox contract, timeout, retry, duplicate 방지 |
| T-ARCH-001~005 | adapter 교체, scale, outbox, degraded mode, 재현 | 계약 위반·event 유실·중복 side effect 0 |

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

| ID | 시험 | 합격 기준 |
|---|---|---|
| T-UX-001~003 | 1440/768/390 핵심 여정 Playwright | overflow·막힌 행동 0 |
| T-UX-004~006 | loading/empty/error/partial/no-answer | 상태별 행동·설명 존재 |
| T-UX-007 | 오류·도움말·trace ID | 내부정보 노출 0, 복구경로 존재 |
| T-UX-008 | 교사 usability task | 완료율·시간·만족 승인기준 충족 |
| T-A11Y-001~008 | keyboard, focus, name/role/value, contrast, reflow, live region, chart/table, screen reader | 핵심 여정 WCAG 2.2 AA 위반 0 |
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
| T-OPS-001~006 | health, alert, queue, cost, backup age, log redaction | 각 dashboard·alert·runbook 증거 |
| T-DR-001 | DB+object+manifest backup | 암호화·off-host·checksum 통과 |
| T-DR-002 | isolated point-in-time restore | RPO 15분 제안치 충족 |
| T-DR-003 | 핵심 서비스 복구 | RTO 4시간 제안치 충족 |
| T-DR-004 | index 재구축·citation 검증 | RTO 24시간, invalid citation 0 |
| T-DR-005 | 연락망·의사결정 tabletop | 역할·통지·증거 공백 0 |

## 11. 시범운영·수용

| ID | 절차 | 합격 기준 |
|---|---|---|
| T-PILOT-001 | 200명 모집·동의·cohort 배정 | 유효 동의와 표본계획 충족 |
| T-PILOT-002 | 1차 진단·추천·RAG·설문 | 핵심 여정 데이터 완전성 ≥95% |
| T-PILOT-003 | 전문가 FGI·이슈 분류 | 녹취 동의, 근거·owner·결정 기록 |
| T-PILOT-004 | 변경 승인·회귀시험 | baseline 회귀 0 |
| T-PILOT-005 | 2차 동일 절차 | 비교 가능한 metric과 version 확보 |
| T-PILOT-006 | 개선 반영률·만족도 | 반영 ≥80%, 만족 ≥80/100 |

행정 수용시험은 T-GOV-001~007, T-PM-001~005, T-TRN-001~002, T-SUP-001, T-BCP-001, T-QUAL-001~002, T-ACC-001로 계획·규정·형상·위험·교육·하자·연속성·기능 정확성 산출물을 확인한다.

## 12. 최종 판정

필수 시험이 모두 PASS이고 KPI-001~010을 충족하며 Critical/High 결함이 0일 때 `ACCEPTED`다. 외부 의사결정이 남았으나 안전하게 비활성화 가능한 선택 기능만 `CONDITIONAL ACCEPTANCE` 대상이며 owner·해제일·보완통제를 기록한다. 실패를 BLOCKED 또는 경고로 숨기지 않는다.

