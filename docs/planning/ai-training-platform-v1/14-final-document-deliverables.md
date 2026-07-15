# 14. 최종 설계·운영·시험 문서 산출물 계약

문서 ID: DEL-CONTRACT-014

기준선: [design-baseline.json](design-baseline.json)

연계 문서: [10. 구축·전환·산출물 계획](10-delivery-implementation-plan.md), [12. UI/UX 비주얼 시스템](12-ui-ux-visual-system.md), [Machine-readable final inventory](final-document-inventory.json)

적용 게이트: `GATE-DESIGN-INTEGRITY` 및 기준선의 모든 release gate

## 1. 목적과 판정 원칙

본 문서는 구현 종료 시 저장소와 release bundle에 반드시 존재해야 하는 최종 문서, 운영 runbook, 사용자 manual, 시험 증거와 배포 인계물을 정확한 경로로 고정한다. “관련 문서 작성”, “운영 가이드 제공”처럼 검사할 수 없는 표현은 완료로 인정하지 않는다.

계획 원천은 `docs/planning/ai-training-platform-v1/`이며 최종 산출물은 아래 서로 다른 root에 생성한다.

```text
docs/design/ai-training-platform/
docs/operations/ai-training-platform/
docs/qa/ai-training-platform/
docs/manuals/ai-training-platform/
docs/releases/ai-training-platform/
dist/docs/${release_id}/
```

최종 문서는 계획 원천을 임의로 복사한 별도 기준선이 아니다. 모든 내용 변경은 계획 원천과 `design-baseline.json`을 먼저 수정·검증해 immutable `source_commit`을 만든 뒤, 그 입력 commit에서 최종 문서를 생성한다. 생성 문서를 Git에 보존할 경우 후속 문서 snapshot commit에 넣되, 그 commit hash를 commit 내부 문서에 역으로 기록하지 않는다. 경로 누락, 빈 파일, broken link, checksum 불일치, owner 또는 gate 누락은 `MISSING`으로 판정한다.

[final-document-inventory.json](final-document-inventory.json)은 이 문서 표의 machine-readable normative inventory다. `schema_version=final-document-inventory.v1`, baseline ID, root literal, relative path template, owner/gate/media/source kind와 group별 expected count를 고정한다. `canonical_contract`를 제외한 전체 object를 RFC 8785-compatible integer/string subset으로 직렬화한 SHA-256은 `a04cab366c41774b76b7ee3e3060b590f160659d01079ffcb9f7e172e8d1a8a4`이며 verifier source에도 독립 고정한다. 따라서 overlay manifest hash만 다시 계산한 경로 변조는 기준선을 바꾸지 못한다. 동적 placeholder는 exact literal `${release_id}` 하나만 허용한다. release ID는 기준선 `release-id.v1` 정규식을 통과한 단일 segment여야 하며 slash/backslash/colon/percent/NUL/dot segment/trailing dot·space를 거부한다. canonical root와 child에 symlink/junction/mount redirect/Windows reparse point가 없어야 하고 resolve한 child가 root 아래에 남는지 확인한 뒤에만 생성한다.

## 2. 역할과 승인 책임

| Owner ID | 책임 |
|---|---|
| `OWN-ARCH` | 시스템 아키텍트: 기준선, 아키텍처, CDD/CDR, 인터페이스 |
| `OWN-PROD` | 서비스 책임자: 기능 범위, 사용자 여정, release 범위 |
| `OWN-UX` | UX/접근성 책임자: 화면, 비주얼 token, 접근성 증거 |
| `OWN-AI` | AI 책임자: 진단·추천·Gateway·평가·모델 운영 |
| `OWN-DOC` | Document AI 책임자: HWP/HWPX pipeline, 검색·citation |
| `OWN-DATA` | 데이터 책임자: 데이터 모델, migration, 품질, lineage |
| `OWN-SEC` | 보안·개인정보 책임자: 위협, 동의, 반출, 사고 대응 |
| `OWN-OPS` | 운영 책임자: 배포, 관측, 백업·복구, 장애 runbook |
| `OWN-QA` | QA 책임자: 추적성, 시험, 증거 manifest, 최종 판정 |
| `OWN-ACC` | 발주기관 수용 책임자: 시범·전문가·RPO/RTO 최종 승인 |

문서 작성자와 승인자는 원칙적으로 다른 사람이어야 한다. 예외는 위험 승인 기록에 사유와 만료일을 남긴다. `OWN-ACC`의 서명 또는 machine-verifiable 승인 record를 개발자가 대신 생성할 수 없다.

## 3. 최종 설계 문서 inventory

아래 파일은 모두 `docs/design/ai-training-platform/` 아래에 있어야 한다.

| 파일 | 내용 | Owner | 필수 gate |
|---|---|---|---|
| `README.md` | 문서 index, 기준 commit, 읽는 순서, 변경 절차 | `OWN-ARCH` | DESIGN-INTEGRITY |
| `00-system-design-baseline.md` | 범위, 전제, KPI-001~010, 판정 상태 | `OWN-ARCH` | DESIGN-INTEGRITY |
| `01-requirements-traceability.md` | RFP 60개·시스템 요구 33개·시험·증거 양방향 추적 | `OWN-PROD`, `OWN-QA` | DESIGN-INTEGRITY |
| `02-functional-and-screen-design.md` | 역할, IA, `PUB/TCH/ADM` 화면과 상태·여정 | `OWN-PROD`, `OWN-UX` | UX-ACCESSIBILITY |
| `03-system-architecture.md` | context/container/component/deployment 구성도와 trust boundary | `OWN-ARCH` | DESIGN-INTEGRITY |
| `04-component-design.md` | Frontend, API, Auth, AI, Document, Search, Worker, Audit CDD | `OWN-ARCH` | DESIGN-INTEGRITY |
| `05-ai-diagnosis-persona-recommendation.md` | 대화, 결정적 scoring, 6 family/12 profile, 추천·성과 | `OWN-AI` | AI-KPI |
| `06-document-ai-hwp-rag.md` | ingest, OCR, DocumentGraph, retrieval, citation, HWPX draft | `OWN-DOC` | DOCUMENT-KPI |
| `07-ai-gateway-model-selection.md` | OpenAI/sLLM routing, DataUseContext, fallback, 평가·비용 | `OWN-AI`, `OWN-SEC` | AI-KPI, SECURITY-PRIVACY |
| `08-data-model-and-erd.md` | tenant key, entity, relation, index, retention, deletion | `OWN-DATA` | DESIGN-INTEGRITY, SECURITY-PRIVACY |
| `09-api-event-interface.md` | OpenAPI/event/job/provider/adapter 계약과 오류 catalog | `OWN-ARCH` | CODE-QUALITY |
| `10-security-privacy-threat-model.md` | data class, consent/ACL, STRIDE, abuse, safeguard | `OWN-SEC` | SECURITY-PRIVACY |
| `11-ui-ux-visual-system.md` | token, grid, responsive, AI/citation state, 증거 matrix | `OWN-UX` | UX-ACCESSIBILITY |
| `12-deployment-topology.md` | production network, HA, dependency, sizing, data flow | `OWN-ARCH`, `OWN-OPS` | OPERATIONS-RECOVERY |
| `13-cdr-and-adr-index.md` | 결정·조건·owner·기한·대안·영향·해제 증거 | `OWN-ARCH` | DESIGN-INTEGRITY |
| `14-validation-and-acceptance.md` | 시험 전략, 수용식, release-state 계산 | `OWN-QA`, `OWN-ACC` | 모든 gate |
| `design-baseline.json` | 계획 원천과 byte-identical한 machine-readable 기준선 | `OWN-ARCH` | DESIGN-INTEGRITY |
| `openapi.json` | 배포 대상 API에서 export한 OpenAPI 3.1 계약 | `OWN-ARCH` | CODE-QUALITY |
| `asyncapi.yaml` | event·queue·job message 계약 | `OWN-ARCH` | CODE-QUALITY |
| `document-graph.schema.json` | DocumentGraph JSON Schema 2020-12 | `OWN-DOC` | DOCUMENT-KPI |
| `data-use-context.schema.json` | signed DataUseContext wire envelope | `OWN-AI`, `OWN-SEC` | SECURITY-PRIVACY |
| `threat-model.json` | 자산·위협·통제·시험 ID machine-readable 연결 | `OWN-SEC` | SECURITY-PRIVACY |
| `requirements-test-registry.json` | RFP60·SYS33·개별 test/procedure/evidence 양방향 registry | `OWN-PROD`, `OWN-QA` | DESIGN-INTEGRITY |
| `screen-route-contracts.json` | 36 screen의 URL·guard·API·event·state·E2E exact 계약 | `OWN-PROD`, `OWN-UX`, `OWN-ARCH` | DESIGN-INTEGRITY, UX-ACCESSIBILITY |
| `kpi-005-structured-output-matrix.json` | 9 task×3 provider/fallback cell과 분모·repair·threshold | `OWN-AI`, `OWN-QA` | AI-KPI |
| `diagnosis-scoring-golden-vectors.json` | scoring EvidenceSpan·정상·dedup·invalid와 persona·recommendation·tie vector | `OWN-AI`, `OWN-QA` | AI-KPI |
| `artifact-manifest.schema.json` | release artifact manifest JSON Schema 2020-12 | `OWN-QA` | DESIGN-INTEGRITY |
| `evidence-index.schema.json` | release evidence index JSON Schema 2020-12 | `OWN-QA` | DESIGN-INTEGRITY |
| `source-tree-hash-golden-vector.json` | RFC 8785 JCS source tree hash exact bytes/digest | `OWN-ARCH`, `OWN-QA` | DESIGN-INTEGRITY |
| `final-document-inventory.json` | `147`개 최종 artifact exact path·owner·gate·media 계약 | `OWN-QA`, `OWN-ARCH` | DESIGN-INTEGRITY |
| `platform-openapi.json` | 113개 operation별 closed request·response·error·pagination 계약과 의미 digest | `OWN-ARCH`, `OWN-QA` | DESIGN-INTEGRITY |
| `platform-asyncapi.json` | 판별 가능한 SSE delta·completed·job·error와 replay·gap·terminal 계약 | `OWN-ARCH`, `OWN-QA` | DESIGN-INTEGRITY |
| `persistent-domain-catalog.json` | 102개 entity의 PK·FK·unique·check·index·retention·delete 물리 계약 | `OWN-ARCH`, `OWN-SEC` | DESIGN-INTEGRITY, SECURITY-PRIVACY |
| `ai-service-contracts.json` | evidence scoring, grounded claim-citation binding, DataUse allowlist 계약 | `OWN-AI`, `OWN-SEC` | AI-KPI, SECURITY-PRIVACY |
| `data-use-policy-registry.json` | exact category/field allowlist, 113 HTTP·8 privileged operation binding, redaction receipt | `OWN-SEC`, `OWN-AI` | SECURITY-PRIVACY |
| `acceptance-threshold-registry.json` | 승인 임계값의 exact 값·owner·결정·후보·변경 gate | `OWN-QA`, `OWN-ACC` | DESIGN-INTEGRITY, PILOT-ACCEPTANCE |
| `normative-test-semantics.json` | 139개 시험의 고유 metric·수용식·fixture·oracle 의미 | `OWN-QA` | DESIGN-INTEGRITY |
| `rag-policy-golden-vectors.json` | retrieval·citation·문서 품질의 결정적 fixed-point 정책과 vector | `OWN-AI`, `OWN-DOC` | DOCUMENT-KPI |
| `provider-decision-registry.json` | AI·OCR·storage·identity·infra 공급자 결정과 production readiness | `OWN-ARCH`, `OWN-OPS` | OPERATIONS-RECOVERY |
| `legacy-reuse-decision-matrix.json` | 기존 자산 REUSE/ADAPT/REWRITE/RETIRE와 등록 시험 결속 | `OWN-ARCH`, `OWN-QA` | DESIGN-INTEGRITY |
| `ui-journey-contracts.json` | 12개 핵심 여정·36개 화면의 상태·반응형·접근성 계약 | `OWN-UX`, `OWN-QA` | UX-ACCESSIBILITY |
| `rubric-question-contract.json` | 역량·indicator·anchor·question과 raw-dialogue scoring pipeline | `OWN-AI`, `OWN-PROD` | AI-KPI |
| `persona-inference-policy.json` | persona feature·missingness·protected proxy·calibration·leakage 정책 | `OWN-AI`, `OWN-SEC` | AI-KPI, SECURITY-PRIVACY |
| `operation-authorization-contracts.json` | 고권한 작업 tenant ABAC·SoD·dual approval·receipt 계약 | `OWN-SEC` | SECURITY-PRIVACY |
| `evaluation-policy-contract.json` | 추천·공정성·UX 표본·holdout·CI·다중비교·INSUFFICIENT_DATA 정책 | `OWN-QA`, `OWN-AI` | AI-KPI, UX-ACCESSIBILITY |
| `hwp-conversion-boundary-contract.json` | HWP/HWPX 격리 변환·서식 보존·licensed round-trip 계약 | `OWN-DOC`, `OWN-SEC` | DOCUMENT-KPI, SECURITY-PRIVACY |
| `tch-015-authorization-contract.json` | 초안 read/edit/review/export actor·tenant·SoD 권한 matrix | `OWN-SEC`, `OWN-DOC` | SECURITY-PRIVACY |
| `source-traceability-manifest.json` | 공개 배포 가능한 source locator·결정·요구 추적 manifest | `OWN-QA`, `OWN-PROD` | DESIGN-INTEGRITY |

표의 gate 축약은 각각 `GATE-` prefix를 갖는 기준선 gate ID를 뜻한다. 복수 gate가 기재된 문서는 모든 gate가 PASS여야 한다. 최종 설계 inventory는 정확히 `48`개다. JSON/YAML 계약은 schema validation과 예제 positive/negative fixture가 있어야 한다. 특히 artifact/evidence schema는 계획 source의 `fixtures/*.valid.json`이 PASS하고 대응 `*.invalid.json`이 지정 keyword로 FAIL해야 한다.

## 4. 운영 문서 inventory

다음 파일은 `docs/operations/ai-training-platform/`에 생성한다.

| 파일 | 내용 | Owner | 필수 gate |
|---|---|---|---|
| `README.md` | 운영 문서·runbook index, on-call·escalation 연결 | `OWN-OPS` | OPERATIONS-RECOVERY |
| `configuration-and-secrets.md` | 환경별 설정, secret source/rotation, 금지값, validation | `OWN-OPS`, `OWN-SEC` | SECURITY-PRIVACY |
| `deployment.md` | image provenance, Compose/production 배포, health, 승인 boundary | `OWN-OPS` | OPERATIONS-RECOVERY |
| `admin-bootstrap.md` | demo seed와 분리한 최초 관리자 생성·회전·감사 | `OWN-OPS`, `OWN-SEC` | SECURITY-PRIVACY |
| `backup-restore-policy.md` | scope, 암호화, off-host, retention, RPO/RTO와 drill | `OWN-DATA`, `OWN-OPS` | OPERATIONS-RECOVERY |
| `observability-slo-alerts.md` | metric/log/trace, SLI/SLO, alert route, redaction | `OWN-OPS` | OPERATIONS-RECOVERY |
| `capacity-and-cost.md` | 사용량 unit, quota, forecast, scale trigger, budget alert | `OWN-OPS`, `OWN-AI` | OPERATIONS-RECOVERY |
| `security-operations.md` | access, audit, vulnerability, key/cert, evidence export | `OWN-SEC` | SECURITY-PRIVACY |
| `data-retention-and-deletion.md` | class별 보존, legal hold, lineage deletion receipt | `OWN-DATA`, `OWN-SEC` | SECURITY-PRIVACY |
| `dependency-and-degraded-mode.md` | DB/Redis/storage/provider 장애별 영향·fallback | `OWN-ARCH`, `OWN-OPS` | OPERATIONS-RECOVERY |
| `service-catalog.md` | service owner, repository, dashboard, runbook, dependency | `OWN-OPS` | OPERATIONS-RECOVERY |

### 4.1 필수 runbook inventory

모든 runbook은 `docs/operations/ai-training-platform/runbooks/` 아래에 생성한다.

| ID | 파일 | Trigger·목표 | Owner / Escalation ID | Drill cadence / dependency fingerprint | 핵심 validation·abort | 필수 evidence / gate |
|---|---|---|---|---|---|---|
| RB-001 | `deployment.md` | 승인 image를 production에 무중단 배포 | `OWN-OPS` / `OWN-ARCH`, `OWN-SEC` | 매 RC / candidate image·topology·configuration digest | `/health`·`/ready`·smoke; error budget 소진 시 중단 | deploy log, image digest / `GATE-OPERATIONS-RECOVERY` |
| RB-002 | `rollback.md` | 결함 release를 직전 승인 image/schema로 복귀 | `OWN-OPS` / `OWN-ARCH`, `OWN-DATA` | 매 RC / candidate·rollback target image와 migration-chain digest | backward-compatible 여부; 데이터 손실 예상 시 중단 | before/after health, decision / `GATE-OPERATIONS-RECOVERY` |
| RB-003 | `database-migration.md` | expand/migrate/contract migration 실행 | `OWN-DATA` / `OWN-OPS`, `OWN-ARCH` | migration chain마다 / DB major·전체 migration checksum | backup·lock·row count; destructive DDL은 별도 승인 | migration log, checksum / `GATE-CODE-QUALITY` |
| RB-004 | `backup.md` | DB/object/manifest 암호화 off-host backup | `OWN-DATA` / `OWN-OPS`, `OWN-SEC` | 분기 및 backup 변경 후 / backup tool·config·DB/object manifest version | size·age·encryption·restore catalog; partial은 폐기 | backup manifest / `GATE-OPERATIONS-RECOVERY` |
| RB-005 | `restore.md` | 격리 환경 또는 승인 incident에서 복원 | `OWN-DATA` / `OWN-OPS`, `OWN-SEC` | 분기 및 restore 변경 후 / restore tool·DB/object format·backup manifest version | schema·row/object count·checksum; production overwrite 중단 | restore drill report / `GATE-OPERATIONS-RECOVERY` |
| RB-006 | `disaster-recovery.md` | site/zone 상실 시 core service 복구 | `OWN-OPS` / `OWN-ARCH`, `OWN-DATA`, `OWN-ACC` | 반기, topology 변경 후, 수용 전 / DR topology·failover·restore fingerprint | 승인 RPO/RTO clock; 증거 불완전 시 수용 중단 | timeline, RPO/RTO evidence / `GATE-OPERATIONS-RECOVERY` |
| RB-007 | `index-rebuild.md` | search/vector index 손상·schema 변경 재색인 | `OWN-DOC` / `OWN-DATA`, `OWN-OPS` | index·embedding·ACL 변경마다 및 수용 전 / DocumentGraph·embedding·reranker·ACL·corpus snapshot | ACL snapshot·citation validation; invalid citation >0 중단 | index manifest, KPI-003/004 / `GATE-DOCUMENT-KPI`, `GATE-OPERATIONS-RECOVERY` |
| RB-008 | `service-incident.md` | SLO·보안 외 일반 P1/P2 incident 대응 | `OWN-OPS` / `OWN-ARCH`, `OWN-PROD` | 반기 tabletop 및 incident process 변경 후 / service catalog·alert·escalation fingerprint | severity·mitigation·health; 영향 확대 시 rollback | incident timeline / `GATE-OPERATIONS-RECOVERY` |
| RB-009 | `privacy-incident.md` | 오반출·동의/ACL 위반·개인정보 노출 대응 | `OWN-SEC` / `OWN-ACC`, `OWN-PROD` | 반기 tabletop 및 policy 변경 후 / consent·egress·audit·notification policy digest | egress 차단·범위·보존; 증거 삭제 금지 | case ID, legal decision / `GATE-SECURITY-PRIVACY` |
| RB-010 | `degraded-mode.md` | 일부 dependency 장애에서 안전한 기능 축소 | `OWN-OPS` / `OWN-SEC`, `OWN-ARCH`, `OWN-PROD` | 매 RC 및 safety/feature 변경 후 / candidate image·feature flag·data policy·Gateway digest | 금지 기능이 실제 차단; unknown data 외부 전송 0 | feature-state snapshot / `GATE-SECURITY-PRIVACY`, `GATE-OPERATIONS-RECOVERY` |
| RB-011 | `ai-provider-outage.md` | OpenAI/sLLM 장애·rate limit·품질 회귀 | `OWN-AI` / `OWN-OPS`, `OWN-SEC` | 분기 및 route/provider/model 변경 후 / Gateway·router·provider contract·model policy digest | fallback policy·schema success; unsafe fallback 중단 | route/fallback report / `GATE-AI-KPI`, `GATE-SECURITY-PRIVACY`, `GATE-OPERATIONS-RECOVERY` |
| RB-012 | `database-failover.md` | primary DB 장애·planned switchover | `OWN-DATA` / `OWN-OPS`, `OWN-ARCH` | 반기 및 DB major/topology 변경 후 / DB engine·replication·fencing fingerprint | replication lag·write fencing; split-brain 징후 중단 | failover timeline / `GATE-OPERATIONS-RECOVERY` |
| RB-013 | `queue-backlog.md` | 일반·Windows converter queue lag/age가 threshold 초과 | `OWN-OPS` / `OWN-ARCH`, `OWN-DOC`, `OWN-QA` | 분기 및 worker/queue/converter capacity 변경 후 / worker image·queue topology·converter license/capacity·idempotency digest | oldest age·DLQ·converter health·idempotency; 중복 처리 시 scale 중단 | queue metrics / `GATE-OPERATIONS-RECOVERY` |
| RB-014 | `object-storage-outage.md` | 원문·draft·evidence object 접근 불가 | `OWN-OPS` / `OWN-DOC`, `OWN-SEC` | 분기 및 storage/ACL/cache 변경 후 / adapter·ACL·cache·object-format digest | write freeze·checksum; stale cache 원문 노출 금지 | outage sample / `GATE-DOCUMENT-KPI`, `GATE-SECURITY-PRIVACY`, `GATE-OPERATIONS-RECOVERY` |
| RB-015 | `secret-rotation.md` | 정기·유출 의심 secret/key 회전 | `OWN-SEC` / `OWN-OPS`, `OWN-AI` | 반기 및 secret backend/provider 변경 후 / secret-store·integration·credential-set fingerprint | dual-read window·old-key revoke; audit gap 중단 | key IDs, revocation receipt / `GATE-SECURITY-PRIVACY` |
| RB-016 | `certificate-renewal.md` | TLS와 SPIRE SVID/trust bundle 갱신·entry revoke | `OWN-OPS` / `OWN-SEC` | 반기 및 PKI/SPIRE/trust 변경 후 / CA chain·SPIRE Server/Agent·entry·mTLS·ingress fingerprint | chain·SPIFFE ID×task·rotation·revocation·expiry; stale trust/SVID 시 fail closed | scanner+SPIRE attestation output / `GATE-SECURITY-PRIVACY`, `GATE-OPERATIONS-RECOVERY` |
| RB-017 | `access-review.md` | user/service privileged access 검토 | `OWN-SEC` / `OWN-PROD`, `OWN-ACC` | user 매월·service 분기 및 policy 변경 후 / IAM·RBAC·ABAC·tenant policy digest | orphan·stale·SoD; owner 미확인 권한 회수 | signed review export / `GATE-SECURITY-PRIVACY` |
| RB-018 | `retention-deletion.md` | 보존 만료·정보주체 삭제·계약 종료 | `OWN-DATA` / `OWN-SEC`, `OWN-ACC` | 분기 및 retention/schema/adapter 변경 후 / retention policy·schema·lineage-adapter digest | lineage target·legal hold; hold 존재 시 중단 | deletion receipts / `GATE-SECURITY-PRIVACY` |
| RB-019 | `audit-export.md` | 승인 감사·조사 자료 반출 | `OWN-SEC` / `OWN-ACC`, `OWN-OPS` | 반기 및 audit/export/key 변경 후 / audit schema·export tool·encryption-key policy digest | scope·mask·encryption·recipient; 승인 불일치 중단 | approval, export hash / `GATE-SECURITY-PRIVACY` |
| RB-020 | `observability-alerts.md` | alert 생성·routing·silence·종료 | `OWN-OPS` / `OWN-ARCH`, `OWN-PROD` | 분기 및 alert/route 변경 후 / observability stack·alert rule·on-call route digest | symptom/cause 구분·dashboard; 무기한 silence 금지 | alert event, ticket / `GATE-OPERATIONS-RECOVERY` |
| RB-021 | `capacity-cost.md` | 70/85% capacity·budget threshold 도달 | `OWN-OPS` / `OWN-AI`, `OWN-PROD` | 매월 forecast 및 quota/price/architecture 변경 후 / workload·quota·provider-price·sizing digest | forecast·quota·quality; 품질 gate 우회 금지 | forecast, decision / `GATE-OPERATIONS-RECOVERY` |
| RB-022 | `vulnerability-patching.md` | Critical/High advisory·정기 patch window | `OWN-SEC` / `OWN-OPS`, `OWN-ARCH` | 분기 및 Critical/High 발생마다 / SBOM·build pipeline·base image·scanner digest | SBOM 영향·canary·scan; 새 Critical/High 발생 시 rollback | scan and patch report / `GATE-SECURITY-PRIVACY` |
| RB-023 | `ai-policy-model-rollback.md` | prompt/model/policy regression 또는 safety 결함 | `OWN-AI` / `OWN-SEC`, `OWN-PROD` | 모든 model/prompt/policy release / candidate policy bundle·model deployment·schema·golden-set digest | pinned version·golden set·cache invalidation; 결과 재현 실패 시 차단 | eval diff, active version / `GATE-AI-KPI`, `GATE-SECURITY-PRIVACY` |

### 4.2 runbook 본문 필수 schema

위 23개 파일은 아래 제목을 정확히 한 번씩 포함해야 하며 빈 section을 허용하지 않는다.

1. `## Owner와 escalation` — 위 registry의 `OWN-*` primary/secondary ID, on-call route, severity별 제한시간
2. `## 목적·trigger·영향` — 자동 alert ID, 사용자 영향, 적용/비적용 범위
3. `## 사전조건` — 권한, 승인, backup, maintenance window, 안전 확인
4. `## copy-paste 명령` — Windows PowerShell과 production shell 중 실제 환경 명령, 변수 선언, secret 출력 금지
5. `## 예상 출력` — 성공 exit code, health/state, redacted output 예시
6. `## 단계별 validation` — 명령 직후 metric·query·smoke·checksum과 합격값
7. `## 중단·rollback 기준` — abort threshold, 쓰기 차단, 직전 안전 상태 복귀 명령
8. `## escalation과 통지` — P1/P2 시간, 보안·개인정보·발주기관 통지 owner
9. `## 증거 보존` — artifact URI, trace/ticket ID, SHA-256, 보존기간, 접근등급
10. `## 마지막 drill` — 실행일 UTC, cadence due UTC, dependency fingerprint, candidate-bound 여부, 실제 image/commit, 환경, 참여자, 결과, 실제 RPO/RTO, 후속 issue

명령은 `PS>`·`$` prompt 문자를 복사 영역 안에 넣지 않고, destructive 명령 앞에는 별도의 human approval checkpoint를 둔다. `<password>` 같은 secret placeholder를 명령 인자에 넣지 않고 secret store reference를 사용한다. 예상 출력과 validation이 없는 명령 목록은 runbook으로 인정하지 않는다. owner와 escalation 필드는 2절 registry에 존재하는 exact `OWN-*` ID만 허용하며 `service owner`, `DPO`, `provider owner` 같은 비등록 label은 verifier가 거부한다.

각 drill evidence에는 `runbook_id`, `runbook_version`, `executed_at_utc`, `cadence_due_at_utc`, `candidate_bound`, `dependency_fingerprint_algorithm`, `dependency_fingerprint`, `tested_image_digests[]`, `result`, `artifact_uri`, `artifact_sha256`를 기록한다. 마지막 drill이 없으면 `MISSING`, cadence가 지났거나 현재 dependency fingerprint와 다르면 `STALE`다. `candidate_bound=true`인 행만 exact candidate image 불일치로 stale 처리한다. 문서만 바뀌거나 dependency fingerprint에 포함되지 않은 application 영역이 바뀐 이유로 다른 runbook drill 전체를 일괄 stale 처리하지 않는다.

## 5. QA·시험 산출물 inventory

아래 파일은 `docs/qa/ai-training-platform/`에 생성한다.

| 파일 | 내용 | Owner | 필수 gate |
|---|---|---|---|
| `README.md` | QA index, environment, evidence 위치·보존 | `OWN-QA` | 모든 gate |
| `test-strategy.md` | level, risk, entry/exit, defect severity | `OWN-QA` | CODE-QUALITY |
| `requirements-test-traceability.csv` | requirement→design→test→evidence→result | `OWN-QA` | DESIGN-INTEGRITY |
| `test-environment.md` | OS/browser/font/DPR/service/image/model version | `OWN-QA` | CODE-QUALITY |
| `test-data-and-golden-set.md` | 생성·가명화·분할·version·leakage 방지 | `OWN-QA`, `OWN-AI` | AI-KPI |
| `unit-component-api-report.md` | lint/type/unit/component/API/contract 결과 | `OWN-QA` | CODE-QUALITY |
| `migration-seed-report.md` | empty DB, upgrade, rollback, seed 멱등성 | `OWN-DATA` | CODE-QUALITY |
| `ai-diagnosis-recommendation-report.md` | KPI-001/002/005, fairness, deterministic replay | `OWN-AI`, `OWN-QA` | AI-KPI |
| `document-rag-citation-report.md` | KPI-003/004, HWP table, locator, ACL 회수 | `OWN-DOC`, `OWN-QA` | DOCUMENT-KPI |
| `security-privacy-report.md` | SAST/DAST/dependency/tenant/egress/abuse | `OWN-SEC` | SECURITY-PRIVACY |
| `accessibility-report.md` | KPI-009, axe, keyboard, NVDA, VoiceOver, zoom | `OWN-UX`, `OWN-QA` | UX-ACCESSIBILITY |
| `visual-regression-report.md` | VIS/XBR matrix, screenshot diff, 승인 baseline | `OWN-UX` | UX-ACCESSIBILITY |
| `performance-resilience-report.md` | load, soak, queue, failover, degraded, cost | `OWN-QA`, `OWN-OPS` | OPERATIONS-RECOVERY |
| `backup-restore-dr-report.md` | isolated restore, RPO/RTO, reindex·citation | `OWN-OPS`, `OWN-DATA`, `OWN-ACC` | OPERATIONS-RECOVERY |
| `deployment-rollback-report.md` | fresh install, upgrade, rollback, smoke | `OWN-OPS`, `OWN-QA` | OPERATIONS-RECOVERY |
| `pilot-and-fgi-report.md` | 200명×2회, 만족도, 개선 승인·반영 | `OWN-PROD`, `OWN-ACC` | PILOT-ACCEPTANCE |
| `final-acceptance-report.md` | gate 결과, 예외·위험, 최종 release state | `OWN-QA`, `OWN-ACC` | 모든 gate |
| `evidence-index.json` | 모든 증거의 repository-relative artifact path·hash·commit·status·freshness·expiry | `OWN-QA` | 모든 gate |

`requirements-test-traceability.csv`의 필수 열은 `requirement_id,design_ids,test_id,evidence_id,owner,commit_sha,status,executed_at_utc,expires_at_utc,artifact_sha256`이다. 실패 행 삭제, 빈 status, 쉼표로 여러 상태를 합치는 것을 금지한다.

## 6. 사용자·관리자 manual inventory

아래 Markdown과 동명의 접근 가능한 PDF를 `docs/manuals/ai-training-platform/`에 일대일로 생성한다. PDF 하나라도 없으면 해당 manual은 `MISSING`이다.

| Markdown 원본 | 필수 접근 가능 PDF | 독자·범위 | Owner | 필수 gate |
|---|---|---|---|---|
| `teacher-user-guide.md` | `teacher-user-guide.pdf` | 교사: 동의, 진단, 정정, 추천, 학습, 문서, 삭제 | `OWN-PROD`, `OWN-UX` | UX-ACCESSIBILITY |
| `institution-admin-guide.md` | `institution-admin-guide.pdf` | 기관 관리자: cohort, 권한, 집계, 개인정보 경계 | `OWN-PROD`, `OWN-SEC` | SECURITY-PRIVACY |
| `content-reviewer-guide.md` | `content-reviewer-guide.pdf` | 콘텐츠·전문가: rubric, 문서/OCR, 권리, 승인 | `OWN-DOC`, `OWN-AI` | DOCUMENT-KPI |
| `system-admin-guide.md` | `system-admin-guide.pdf` | 시스템 관리자: tenant, model/policy, job, audit | `OWN-OPS`, `OWN-SEC` | OPERATIONS-RECOVERY |
| `security-auditor-guide.md` | `security-auditor-guide.pdf` | 감사자: 조회, 승인 반출, evidence 해석 | `OWN-SEC` | SECURITY-PRIVACY |
| `operations-operator-guide.md` | `operations-operator-guide.pdf` | 운영자: dashboard, alert, runbook, on-call | `OWN-OPS` | OPERATIONS-RECOVERY |
| `accessibility-and-support-guide.md` | `accessibility-and-support-guide.pdf` | keyboard, screen reader, 지원·이의제기·문의 | `OWN-UX` | UX-ACCESSIBILITY |
| `quick-start.md` | `quick-start.pdf` | 역할별 첫 15분과 금지 행동 | `OWN-PROD` | UX-ACCESSIBILITY |

manual screenshot은 exact release candidate, 한국어 UI, 가상 개인정보만 사용한다. 화면 변경 뒤 bounding box가 달라지면 screenshot과 대체텍스트를 다시 검수한다. AI 결과 예시는 `AI 생성 예시`, 근거와 제한을 명시한다. `dist/docs/${release_id}/administrator-guide.pdf`는 정확히 다섯 원본 `institution-admin-guide.pdf`, `content-reviewer-guide.pdf`, `system-admin-guide.pdf`, `security-auditor-guide.pdf`, `operations-operator-guide.pdf`를 결합한 배포 편의본이다. 운영자는 이 combined admin guide에 포함한다. 편의본은 위 8개 일대일 PDF를 대체하지 않으며 8개 PDF 모두 distribution의 `manuals/`에도 포함한다.

## 7. release 인계 문서 inventory

아래 파일은 `docs/releases/ai-training-platform/${release_id}/`에 생성한다.

| 파일 | 내용 | Owner | 필수 gate |
|---|---|---|---|
| `README.md` | release index, source commit/tag, 배포 대상 | `OWN-PROD` | DESIGN-INTEGRITY |
| `release-notes.md` | 기능·수정·migration·호환성·알려진 제한 | `OWN-PROD` | CODE-QUALITY |
| `deployment-checklist.md` | 승인, secret, backup, migration, smoke, rollback | `OWN-OPS` | OPERATIONS-RECOVERY |
| `acceptance-decision.md` | gate별 증거와 `NOT_READY`/pending/`ACCEPTED` 판정 | `OWN-QA`, `OWN-ACC` | 모든 gate |
| `known-risks-and-exceptions.md` | 위험, owner, 만료, mitigation, 승인 | `OWN-SEC`, `OWN-PROD` | SECURITY-PRIVACY |
| `third-party-and-model-inventory.md` | SBOM, license, provider/model, region, DPA | `OWN-SEC`, `OWN-AI` | SECURITY-PRIVACY |
| `artifact-manifest.json` | self/checksum/signature를 제외한 content artifact checksum과 provenance | `OWN-QA` | DESIGN-INTEGRITY |
| `artifact-manifest.json.sig` | manifest detached signature | `OWN-QA` | DESIGN-INTEGRITY |
| `SHA256SUMS.txt` | content+manifest+manifest signature SHA-256; self 제외 | `OWN-QA` | DESIGN-INTEGRITY |
| `SHA256SUMS.txt.sig` | checksum catalog detached signature | `OWN-QA` | DESIGN-INTEGRITY |

release state 문자열은 기준선의 세 값만 사용한다. `REQUIRES_ACCEPTANCE_DATA`가 하나라도 남아도 모든 implementable KPI/prerequisite와 technical/artifact signature가 fresh PASS이고 scoped `OWN-ACC` pending record가 있을 때만 `acceptance-decision.md`의 상한은 `CODE_COMPLETE / ACCEPTANCE DATA PENDING`이다. 이 record는 acceptance signature가 아니며 `MISSING`으로 세지 않는다. `FAIL`, `BLOCKED`, 그 밖의 `MISSING`, `STALE`은 항상 `NOT_READY`다.

## 8. 배포용 문서 bundle

문서 build는 `dist/docs/${release_id}/`에 아래 파일을 정확히 생성한다.

| 파일 | 원천 | 형식·합격 기준 |
|---|---|---|
| `final-system-design.pdf` | 최종 design inventory | bookmark·tagged reading order·embedded Korean fonts·PDF/A-2u 검증 |
| `operations-guide.pdf` | 운영 문서와 23개 runbook | 명령·표·링크 복사 가능, secret 0건 |
| `test-and-acceptance-plan.pdf` | QA 전략·절차·수용식 | test/evidence ID 검색 가능, 판정식 포함 |
| `teacher-user-guide.pdf` | 교사 manual | tagged PDF, 대체텍스트, keyboard/지원 안내 |
| `administrator-guide.pdf` | 기관·콘텐츠·시스템·감사·운영자 5개 manual | 역할별 권한 경계와 runbook link |
| `release-notes.pdf` | 해당 release notes·known risk | source commit/tag와 release state 표시 |
| `traceability.csv` | 요구사항·설계·시험·증거 추적 | UTF-8 BOM, 고정 header, orphan/duplicate 0건 |
| `evidence-index.json` | QA canonical evidence index의 release snapshot | JSON Schema validation, relative path/hash/commit/freshness/expiry 검증 |
| `artifact-manifest.json` | content artifact provenance | schema-valid; content만 `files[]`에 포함, self/checksum/signature 제외 |
| `artifact-manifest.json.sig` | manifest detached signature | 승인 key ID·algorithm, signature verification PASS |
| `SHA256SUMS.txt` | content+manifest+manifest signature checksum | 경로 byte-order 정렬; self와 checksum signature 제외 |
| `SHA256SUMS.txt.sig` | checksum catalog detached signature | 승인 release key로 verification PASS |
| `source-docs.zip` | 다섯 docs root의 release snapshot | `.git`, secret, raw evidence, 원문 권리자산 제외 |
| `manuals/teacher-user-guide.pdf` | 교사 manual pair PDF | 원본 PDF와 byte-identical, hash 일치 |
| `manuals/institution-admin-guide.pdf` | 기관 관리자 manual pair PDF | 원본 PDF와 byte-identical, hash 일치 |
| `manuals/content-reviewer-guide.pdf` | 콘텐츠 검수자 manual pair PDF | 원본 PDF와 byte-identical, hash 일치 |
| `manuals/system-admin-guide.pdf` | 시스템 관리자 manual pair PDF | 원본 PDF와 byte-identical, hash 일치 |
| `manuals/security-auditor-guide.pdf` | 보안 감사자 manual pair PDF | 원본 PDF와 byte-identical, hash 일치 |
| `manuals/operations-operator-guide.pdf` | 운영자 manual pair PDF | 원본 PDF와 byte-identical, hash 일치 |
| `manuals/accessibility-and-support-guide.pdf` | 접근성·지원 manual pair PDF | 원본 PDF와 byte-identical, hash 일치 |
| `manuals/quick-start.pdf` | quick-start manual pair PDF | 원본 PDF와 byte-identical, hash 일치 |

PDF 접근성은 자동 tag 검사만으로 끝내지 않고 제목·언어 `ko-KR`, heading 순서, table header, link, alt text와 reading order를 수동 확인한다. 접근성 또는 PDF/A 검사 `BLOCKED`는 PASS가 아니다.

release root와 distribution root는 각자 독립된 무결성 scope다. `docs/releases/.../artifact-manifest.json`은 `scope=RELEASE`, `source_release_manifest_sha256=null`이고 해당 release root 내부 content만 열거한다. `dist/docs/.../artifact-manifest.json`은 `scope=DISTRIBUTION`이며 검증된 release-root manifest exact bytes의 SHA-256을 `source_release_manifest_sha256`에 기록하고 distribution root 내부 content만 열거한다. 두 root는 이름이 같은 네 무결성 파일을 각각 소유하며 서명·checksum을 공유하거나 다른 root의 파일을 `files[]`에 넣지 않는다.

정확한 expected count는 design 48, operations 11, runbook 23, QA 18, manual Markdown 8, manual PDF 8, release 10, distribution 21, 총 147이다. 표와 [final-document-inventory.json](final-document-inventory.json)이 다르면 verifier는 실패하며 임의로 파일을 추가·생략하지 않는다.

## 9. 재현 가능한 문서 build와 checksum

최종 저장소는 아래 두 명령을 구현해야 한다.

```powershell
$releaseId = "v1.0.0-rc1"
pwsh -NoProfile -File .\scripts\build-final-docs.ps1 -Release $releaseId
pwsh -NoProfile -File .\scripts\verify-final-docs.ps1 -Release $releaseId
```

위 script는 구현 산출물이며 clean CI/build 단계에서만 신뢰 기준선에 따라 실행한다. guarded one-command runner는 Codex가 변경할 수 있는 이 script를 post-run host verifier로 실행하지 않는다. runner는 실행 전에 고정한 `final-document-inventory.json` bytes와 자체 `guarded-runner-internal.v2` 검사를 사용해 147개 path를 확인한다.

build 입력과 commit 의미:

- `source_commit`은 application, 계획 원천, build script와 template를 모두 포함하고 생성 문서는 아직 포함하지 않은 immutable implementation input commit이다.
- `source_tree`는 `source_commit^{tree}`의 Git object ID이며 `source_tree_object_format`에 `sha1` 또는 `sha256`을 기록한다.
- `source_tree_sha256`은 `.git`, 기존 `dist/`, 생성 문서 root를 제외한 tracked regular input file로 `source-tree-hash.v1`을 적용한다. path는 repository-relative POSIX NFC, UTF-8 byte-order; mode는 `100644|100755`; record는 `{content_sha256,mode,path,size_bytes}`; manifest는 exact `{files:[...],schema:"source-tree-manifest.v1"}`이며 `SHA-256(UTF-8(RFC8785-JCS(manifest)))`다. symlink/submodule/reparse/duplicate normalized path는 실패한다. [golden vector](source-tree-hash-golden-vector.json)의 canonical bytes/digest가 독립 구현에서 일치해야 한다.
- 생성 문서를 후속 Git commit에 보존해도 manifest의 `source_commit`은 바꾸지 않는다. 후속 `document_snapshot_commit`은 commit 생성 뒤 annotated release tag 또는 외부 CI attestation에서만 `SHA256SUMS.txt` digest와 결합한다. commit이 자기 hash를 자기 내용에 기록하는 구조를 금지한다.

build 계약과 순환 없는 integrity DAG를 `RELEASE`, `DISTRIBUTION` scope별로 각각 실행한다.

1. clean worktree의 `source_commit`, `source_tree`, `source_tree_sha256`, baseline SHA-256과 builder image digest를 freeze한다.
2. `design-baseline.json`과 모든 source link/ID/schema를 fail-closed 검증한다.
3. builder container image를 immutable digest로 pin하고 Pandoc, PDF engine, font, Mermaid/diagram tool version을 기록한다.
4. `SOURCE_DATE_EPOCH`을 source commit timestamp로, locale을 `ko-KR.UTF-8`, timezone을 `UTC`로 고정한다. PDF의 created/modified timestamp, random ID, absolute local path를 제거하고 approved font checksum으로 embed한다.
5. 현재 scope root 안에서 무결성 파일 4개를 제외한 content set `C`를 먼저 렌더링한다. 제외 파일은 `artifact-manifest.json`, `artifact-manifest.json.sig`, `SHA256SUMS.txt`, `SHA256SUMS.txt.sig`다. 모든 `files[].path`와 `source_paths[]`는 root-relative POSIX NFC path이고 absolute/drive/colon/backslash/빈 segment/dot segment/percent-encoding/reparse escape를 거부한다.
6. `artifact-manifest.json`을 생성한다. `files[]`는 오직 현재 scope의 `C` path·size·SHA-256만 포함하며 manifest 자신과 checksum·signature 파일을 hash하지 않는다. `RELEASE`는 `source_release_manifest_sha256=null`, `DISTRIBUTION`은 이미 schema·hash·signature가 검증된 RELEASE manifest exact bytes의 SHA-256을 요구한다.
7. canonical manifest를 승인 release key로 서명해 `artifact-manifest.json.sig`를 만든다.
8. `SHA256SUMS.txt`는 `C + artifact-manifest.json + artifact-manifest.json.sig`를 UTF-8 path byte-order로 정렬해 hash한다. 자기 자신과 `SHA256SUMS.txt.sig`는 포함하지 않는다.
9. 완성된 `SHA256SUMS.txt`를 승인 release key로 서명해 `SHA256SUMS.txt.sig`를 만든다. 이 signature는 checksum file을 직접 검증하므로 다른 checksum 안에 넣지 않는다.
10. 같은 input tuple로 격리된 두 번째 unsigned build를 실행해 `C`와 canonical `artifact-manifest.json`이 byte-identical인지 비교한다. detached signature와 checksum catalog는 재현성 비교 대상이 아니라 signature/hash verification 대상이다.
11. 네 무결성 파일의 포함·제외 규칙, 두 detached signature, 모든 content hash를 다시 계산하고 secret pattern, local absolute path, 미완료 placeholder marker, broken link, 빈 section, 미등록 owner/gate와 개인식별정보를 scan한다.

`artifact-manifest.json`은 [artifact-manifest.schema.json](artifact-manifest.schema.json), `evidence-index.json`은 [evidence-index.schema.json](evidence-index.schema.json)을 검증한다. artifact manifest의 필수 필드는 `schema_version`, `release`, `release_state`, `scope`, `source_release_manifest_sha256`, `source_commit`, `source_tree_object_format`, `source_tree`, `source_tree_sha256`, `baseline_id`, `baseline_version`, `baseline_sha256`, `builder_image_digest`, `source_date_epoch`, `tool_versions`, `files[]`, `integrity_exclusions[]`, `generated_at_utc`, `signing_policy`다. 각 `files[]` 항목은 `path`, `media_type`, `size_bytes`, `sha256`, `owner_ids`, `gate_ids`, `source_paths`를 갖는다. path는 현재 scope root를 벗어날 수 없고 duplicate path와 missing source path는 semantic verifier가 거부한다. `integrity_exclusions[]`는 현재 root의 위 네 무결성 파일과 제외 이유를 정확히 열거한다. `signing_policy`는 algorithm과 승인 key ID만 기술하고 실제 signature는 detached 파일에 둔다. `generated_at_utc`는 wall clock이 아니라 `SOURCE_DATE_EPOCH`의 UTC 표현으로 고정한다.

canonical evidence index root는 exact `schema_version,release,source_commit,generated_at_utc,overall_status,evidence`만 가진다. `overall_status`는 `PASS|FAIL|BLOCKED|MISSING|REQUIRES_ACCEPTANCE_DATA`다. 각 evidence row는 exact `evidence_id,requirement_ids,test_ids,gate_ids,status,freshness,artifact_path,artifact_sha256,source_commit,executed_at_utc,expires_at_utc,owner_ids,candidate_bound,dependency_fingerprint`를 가진다. `artifact_path`는 repository-relative safe path이며 실제 nonempty non-reparse file SHA-256과 일치해야 한다. row의 source commit은 candidate commit, freshness는 `FRESH`, expiry는 검증 시각보다 미래여야 한다. index 전체에서 `FAIL|BLOCKED|MISSING`, `STALE|MISSING` freshness 하나라도 release를 실패시킨다. ACCEPTED는 모든 row가 PASS이고 pending은 PASS 또는 `REQUIRES_ACCEPTANCE_DATA`만 허용한다.

verification의 마지막 출력은 다음 형태이며 하나라도 실패하면 exit code가 0이 아니어야 한다.

```text
PASS: source and baseline integrity
PASS: required final document inventory
PASS: links, IDs, schemas, owners and gates
PASS: PDF/A and accessibility checks
PASS: traceability and evidence freshness
PASS: reproducible build and SHA-256 manifest
RESULT: failed=False blocked=False
```

## 10. 증거 freshness·보존·release 판정

- code/build/migration/E2E/visual/accessibility/security/performance 증거는 exact candidate source commit과 image digest에서 생성해야 하며 해당 입력이 바뀌면 stale다.
- runbook drill freshness는 4.1의 각 행 cadence, `candidate_bound`, dependency fingerprint를 함께 평가한다. unrelated 문서 commit 또는 fingerprint 밖의 변경은 기존 drill을 stale로 만들지 않는다.
- `RB-001`, `RB-002`, `RB-010`은 항상 candidate-bound다. `RB-003`, `RB-007`, `RB-011`, `RB-023`은 해당 migration/index/provider·route/model·policy가 release에서 바뀔 때 candidate-bound가 된다.
- KPI-010 수용에 사용하는 `RB-005`, `RB-006`, `RB-007`, `RB-012` 증거는 dependency-equivalent release 구성으로 수용일 전 30일 안에 격리 실행하고 발주기관 승인을 연결한다.
- privileged access review는 수용일 전 30일 안에 완료한다.
- 전문가 golden set, 시범운영·FGI와 발주기관 승인 증거는 exact policy/dataset version을 명시하고 해당 release 범위를 승인해야 한다.
- 증거 본문 원본은 접근통제된 evidence store에 보존할 수 있으나 candidate 검증용 redacted receipt는 repository-relative `artifact_path`에 nonempty file로 materialize하고 SHA-256·source commit·expiry를 index에 기록한다. 외부 URI만 있는 행은 release 증거가 아니다.
- 개인정보·RESTRICTED 원문·secret·provider credential·실사용자 화면 capture는 문서 bundle에 넣지 않는다.

gate는 기준선의 exact reducer로 KPI별 결과를 먼저 계산한다. 필수 산출물과 증거가 모두 존재하고 모든 gate가 fresh `PASS`일 때만 `ACCEPTED`다. 실제 전문가·시범·발주기관 데이터만 남고 구현 가능 KPI/prerequisite·비-KPI 증거·technical/artifact signature가 모두 fresh PASS이며 scoped OWN-ACC pending record가 있으면 `CODE_COMPLETE / ACCEPTANCE DATA PENDING`이다. 그 밖의 상태는 `NOT_READY`이며 문서의 미려함이나 코드 완료 주장으로 대체할 수 없다.

## 11. 문서 변경·검토·서명

각 최종 **Markdown** 문서 front matter에는 `document_id`, `version`, `status`, `owner_ids`, `approver_ids`, `source_commit`, `source_tree_sha256`, `baseline_sha256`, `updated_at_utc`, `classification`, `gate_ids`를 넣는다. JSON/YAML/CSV는 형식을 깨는 front matter를 넣지 않고 schema/header의 provenance 필드 또는 연결된 artifact manifest에 같은 metadata를 기록한다. PDF는 XMP metadata와 artifact manifest, detached signature로 동등 provenance를 제공한다. 여기서 `source_commit`은 9절의 immutable implementation input이며 문서 snapshot commit을 뜻하지 않는다. 변경 PR은 영향 요구사항·시험·screenshot·runbook을 함께 갱신하고 `docs-only`라는 이유로 gate를 생략하지 않는다.

`VerifyCandidate`는 아키텍트, UX/접근성, AI, Document AI, 보안·개인정보, 운영, QA technical owner의 exact 7개 전자 서명과 RELEASE·DISTRIBUTION 각각의 detached artifact/checksum signature를 workspace 밖의 보호된 attestation root에서 읽기 전용으로 검증한다. 두 artifact scope는 각각 `ARTIFACT-INTEGRITY-RELEASE`, `ARTIFACT-INTEGRITY-DISTRIBUTION`의 독립 OWN-QA receipt를 가지며 경로·서명·receipt를 공유하거나 교환하지 않는다. 모든 서명 subject는 implementation commit `S`, 그 직계 release snapshot `R`, semantic approval object의 exact canonical hash에 결속한다. GitHub CI는 tracked URL 자기보고가 아니라 exact PR·workflow ID/path·actor·runner label·head `R`을 live API로 대조하고, PR의 immutable `base.sha`와 `R`에서 각각 가져온 workflow 실제 bytes의 SHA-256이 외부 trust hash와 모두 일치해야 한다. fingerprint와 trusted-tool source는 workspace 밖 `release-trust.v2`이며, 누락·검증 실패는 `NOT_READY`다. 수용 입력이 남은 경우에도 발주기관이 서명한 것처럼 만들지 않고 acceptance ID, owner, due를 가진 `REQUIRES_ACCEPTANCE_DATA` record만 유지하며 local/remote release tag를 생성하지 않는다. `VerifyAccepted`에서만 발주기관 수용 결정·OWN-ACC detached signature와 OWN-QA가 서명한 기존 immutable annotated release tag를 추가로 검증한다.
