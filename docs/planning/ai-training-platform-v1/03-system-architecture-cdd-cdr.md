# 03. 시스템 아키텍처와 CDD/CDR

문서 ID: ARCH-CDR-003  
아키텍처 스타일: Modular service + asynchronous worker + provider adapter

정책·경계·식별자의 normative contract는 [규범 정책·인터페이스 계약](15-normative-policy-and-interface-contracts.md)이다.

## 1. 논리 구성도

```mermaid
flowchart LR
  U[교사·관리자] --> WAF[DNS / TLS / WAF]
  WAF --> WEB[React Web + Nginx]
  WEB --> API[FastAPI Application API]
  API --> AUTH[Identity & Consent]
  API --> DIA[Diagnosis & Recommendation]
  API --> DOC[Document & Draft]
  API -->|mTLS + workload identity| AIG[Separate AI Gateway Service]
  API --> PG[(PostgreSQL + pgvector)]
  API --> REDIS[(Redis)]
  API --> OBJ[(Object Storage)]
  API --> OUT[Transactional Outbox]
  OUT --> WORKER[Celery/Arq Workers]
  WORKER --> PARSE[HWPX/HWP/OCR Pipeline]
  WORKER --> Q[(Converter Queue)]
  Q -->|mTLS job + object capability| WIN[Separate Windows HWP Converter Nodes]
  WORKER -->|mTLS + workload identity| AIG
  AIG --> OAI[OpenAI]
  AIG --> SLLM[sLLM Serving]
  SPIRE[SPIRE Server / Agents] -. X.509-SVID + trust bundle .-> API
  SPIRE -. X.509-SVID + trust bundle .-> WORKER
  SPIRE -. X.509-SVID + trust bundle .-> AIG
  SPIRE -. X.509-SVID + trust bundle .-> WIN
  API --> ADP[Portal / Email Adapters]
  API --> OBS[OTel Logs Metrics Traces]
  WORKER --> OBS
  AIG --> OBS
```

외부 AI에는 AI Gateway만 연결할 수 있다. AI Gateway는 API·worker와 다른 process/container, workload identity, network policy, provider secret과 egress 권한을 갖는 별도 내부 서비스 경계이며 in-process 배치를 금지한다. 모든 AI 호출은 signed `DataUseContext`를 요구하고 mTLS identity, `consent_epoch`, current `acl_version`을 동기 승인한 뒤에만 provider로 전송한다. 원본 문서와 개인정보 저장소는 public network에 노출하지 않는다. 관리자 콘솔은 동일 API를 사용하되 MFA, 재인증, 세분화 권한을 추가한다.

## 2. 배포 구성

| 환경 | 목적 | 구성 |
|---|---|---|
| local | 개발·단위·E2E | Linux Docker Compose, provider/Gateway stub, HWP converter simulator, synthetic data; external egress 없음 |
| test | CI 통합 | ephemeral PostgreSQL/Redis/Object Storage, mock AI |
| pilot-single-vm | 제한 시범·초기 검증 | 단일 Cloud VM Linux Compose+별도 Windows converter node; 명시적 단일 장애점, 99.9% SLO 비적용, 승인된 유지보수 window |
| stage-ha | 운영 유사 검증 | production HA topology와 동일 boundary의 축소 capacity, 비식별 평가셋, 별도 trust domain |
| production-ha | 실제 서비스 | 다중 failure-domain TLS/LB, Web≥2, API≥3, worker≥2/queue, AI Gateway≥3, SPIRE Server 3+Agent, managed PostgreSQL multi-AZ, Redis HA, multi-AZ Object Storage, Windows converter≥2, off-host backup |

서비스 이미지는 immutable digest로 배포한다. migration은 별도 one-shot job으로 실행하며 성공 전 application rollout을 허용하지 않는다. API와 worker는 독립 확장하고, GPU sLLM serving은 별도 node pool 또는 내부 endpoint로 격리한다. production-ha의 replica 수는 최소값이며 load/DR evidence로 상향한다. `pilot-single-vm`은 기능 시범용이고 HA·월 99.9%·zone failover 수용 증거로 사용할 수 없다.

## 3. CDD: 컴포넌트 상세

| ID | 컴포넌트 | 책임 | 입력/출력 | 실패·확장 |
|---|---|---|---|---|
| CDD-001 | Web Portal | 역할별 IA, 접근성, API/SSE client | REST, SSE, signed URL | 오류경계·재연결; stateless CDN 확장 |
| CDD-002 | Application API | 요청 검증, use case, transaction, policy | `/api/v1`, outbox event | timeout·idempotency; horizontal scale |
| CDD-003 | Identity & Consent | OIDC/local auth, session rotation, RBAC/ABAC, 동의 | JWT, session, policy decision | replay 차단, MFA; DB 일관성 우선 |
| CDD-004 | Diagnosis Engine | 세션 상태, 질문정책, evidence, deterministic scoring | turn/evidence/rubric/result | AI fallback·재개; 세션별 lock |
| CDD-005 | Recommendation Engine | hard filter, rank, diversity, path graph | score/persona/catalog → recommendation | 이전 승인정책 fallback; batch 평가 |
| CDD-006 | Document Service | 파일·권리·버전·ACL·게시 수명주기 | file metadata, signed URL | quarantine; object storage scale |
| CDD-007 | Document Worker | 변환, OCR, DocumentGraph, chunk, embedding | job/event → artifact/index | retry/dead-letter; queue별 autoscale |
| CDD-008 | Retrieval & Draft | ACL-first retrieval, citation, HWPX draft | query/evidence/template | no-answer; read replica/index scale |
| CDD-009 | AI Gateway | `services/ai-gateway/` 독립 service; model registry, routing, redaction, schema, fallback | canonical AI request/response | circuit breaker, quota; provider pool; in-process 금지 |
| CDD-010 | Reporting & Pilot | snapshot, 집계, cohort, 설문·FGI | versioned fact → report | 재계산 job; privacy threshold |
| CDD-011 | Audit & Observability | 감사, trace, metric, SLO, cost ledger | event/span/metric | buffer·backpressure; 독립 보관 |
| CDD-012 | Integration Adapters | 포털, 교육과정, email, HWP 변환 | canonical contract ↔ external | contract test·outbox retry |

### 3.1 공통 컴포넌트 계약

- 모든 command는 `request_id`, `actor`, `tenant_id`, `schema_version`, `occurred_at`을 가진다.
- 외부 side effect는 DB transaction과 outbox 기록 후 비동기로 수행한다.
- API에서 provider SDK와 파일 parser를 직접 호출하지 않는다.
- domain object는 provider 명칭이 아닌 canonical type을 사용한다.
- retry는 idempotent operation만 대상으로 exponential backoff+jitter를 적용한다.
- dead-letter는 자동 폐기하지 않고 원인·재처리·승인 이력을 보존한다.
- tenant-scoped entity는 tenant key를 PK·FK·storage namespace에 포함하고 RLS 또는 datastore boundary에서 동등하게 시험 가능한 불변조건을 강제한다.
- 미분류 narrative와 raw/scanned upload는 `RESTRICTED`이며 safeguarding·분류·정책 승인이 불명확하면 fail closed 한다.

### 3.2 공통 규범 계약

구현은 [NORM-CONTRACT-015](15-normative-policy-and-interface-contracts.md)의 `DataUseContext`, `ConsentAuthorizationPolicyVersion`, `TenantIsolationPolicyVersion`, `SourceRightsPolicyVersion`, `SafeguardingRoutingPolicyVersion`, `ScoringPolicyVersion`, `PersonaInferencePolicyVersion`, `RecommendationPolicyVersion`과 `DocumentGraph JSON schema`를 동일한 release manifest에 고정한다. component 간 local shortcut이나 과거 ALLOW cache로 이 계약을 우회할 수 없다.

서비스 경계의 구현 계약은 [platform-openapi.json](platform-openapi.json)의 배포용 117개 exact operation(screen 113개와 service-auth 4개), [platform-asyncapi.json](platform-asyncapi.json)의 diagnosis/RAG/job SSE, [ai-service-contracts.json](ai-service-contracts.json)의 canonical responses/embeddings/rerank와 9개 task payload를 사용한다. 물리 저장 경계는 [persistent-domain-catalog.json](persistent-domain-catalog.json)을 사용한다. 생성 client·migration·event consumer가 이 machine source와 다르면 `GATE-DESIGN-INTEGRITY`를 실패 처리한다.

## 4. 핵심 실행 흐름

### 4.1 진단 턴

`POST turn → 권한·동의 확인 → 입력 최소화/위험검사 → signed DataUseContext 발급 → AI Gateway의 consent_epoch 동기 재승인 → evidence extraction → schema 검증 → evidence 저장 → deterministic score → next-question policy → transaction commit → 응답/SSE`

AI timeout이면 입력과 상태를 보존하고 정형 질문 또는 재시도 선택을 제공한다. schema validation 실패는 최대 1회 repair를 허용하고 이후 안전한 fallback을 사용한다.

### 4.2 문서 수집

`signed upload → checksum/악성검사 → SourceDocumentVersion 생성 → outbox → parser/OCR → DocumentGraph → quality gate → human review → chunk/embed → index snapshot → publish`

게시 전 artifact는 검색 결과에 노출되지 않는다. 재처리는 새 artifact version을 만들며 게시 snapshot은 불변이다.

### 4.3 RAG 답변

`query policy → tenant/ACL filter → lexical+vector retrieval → RRF → rerank → current source rights 재승인 → evidence budget → generation → claim-citation validation과 재승인 → response`

검증되지 않은 claim은 제거하거나 no-answer로 전환한다. index rollback은 ranking·embedding만 되돌리며 현재 ACL·license·publication·deletion state를 되돌릴 수 없다. answer, citation, model/prompt/index version과 latency/cost를 한 실행 레코드로 묶는다.

## 5. Trust boundary

| 경계 | 통제 |
|---|---|
| Browser ↔ Edge | TLS, CSP, CSRF, rate limit, bot/abuse control |
| Edge ↔ API | private network, proxy header allowlist, request size 제한 |
| API ↔ Data | service identity, least privilege, encryption, query policy |
| Worker ↔ Uploaded file | quarantine, no network parser sandbox, CPU/memory/time 제한 |
| API/Worker ↔ AI Gateway | private endpoint, mTLS/workload identity, signed DataUseContext, synchronous authorization |
| AI Gateway ↔ External AI | data classification, safeguarding, redaction, egress allowlist, audit |
| Admin ↔ Control plane | MFA, reauthentication, dual approval, immutable audit |
| HWP conversion worker | 별도 Windows node, SPIFFE mTLS queue/object capability, DB credential·public ingress·일반 egress 없음, macro 금지, one-way artifact exchange |
| Workload PKI | SPIRE node/workload attestation, 최대 60분 X.509-SVID, 자동 rotation, trust bundle hash, entry revoke·격리 runbook |

## 6. CDR: 주요 설계 결정

| CDR | 결정 | 근거 | 결과·제약 |
|---|---|---|---|
| CDR-001 | YOnLab 독립 플랫폼과 포털 adapter | 외부 포털 변경·권리·운영 의존 축소 | 공개 계약 외 직접 결합 금지 |
| CDR-002 | React+TypeScript, FastAPI | 접근성 UI와 typed API, AI 생태계 | OpenAPI client 자동생성 |
| CDR-003 | PostgreSQL+pgvector | transaction metadata와 초기 vector 운영 단순화 | 규모 임계치 초과 시 vector adapter 전환 |
| CDR-004 | Redis+비동기 worker | OCR·embedding·report 장기작업 분리 | 202+Job, idempotency 필수 |
| CDR-005 | OpenAI+sLLM Hybrid Gateway | 품질·비용·데이터 통제 균형 | task/data별 routing, provider lock-in 금지 |
| CDR-006 | LLM은 evidence 추출, 점수는 결정적 계산 | 재현성·설명가능성·감사 | rubric version과 evidence 필요 |
| CDR-007 | 페르소나는 확률분포와 사용자 수정 | 낙인·오분류 위험 완화 | 인사평가에 사용 금지 |
| CDR-008 | HWPX를 canonical 생성 형식 | XML 구조·검증·자동화 용이 | HWP는 격리 변환으로만 제공 |
| CDR-009 | DocumentGraph와 계층형 chunk | 표·서식·citation 위치 보존 | parser별 canonical mapping 필요 |
| CDR-010 | ACL-first hybrid RAG | 정보유출 방지와 검색 품질 | post-filter만 사용하는 구현 금지 |
| CDR-011 | Transactional outbox | DB 상태와 외부 side effect 일관성 | consumer idempotency 필요 |
| CDR-012 | Evidence-first AI 평가 gate | 회귀를 배포 전에 차단 | versioned golden set 유지 |
| CDR-013 | Observability와 audit 분리 | 운영 telemetry와 법적 감사 목적 차이 | 감사 로그 별도 보존·권한 |
| CDR-014 | 개발용 호환 proxy는 production data plane에서 제외 | inbound auth·quota·감사 부족 위험 | 제한된 offline adapter만 허용 |
| CDR-015 | AI Gateway를 별도 내부 서비스 경계로 고정 | provider credential·egress·실패영역의 독립 통제 | mTLS/workload identity와 canonical API 외 호출 금지 |
| CDR-016 | 현재 권리와 동의를 실행 시점에 재승인 | 철회 직후 stale token/index 노출 차단 | ALLOW cache 금지, 장애 시 fail closed |

## 7. 검색·AI 확장 임계치

- pgvector p95가 승인 목표를 3회 연속 위반하거나 active vector가 3천만 건을 넘으면 전용 vector store를 비교 평가한다.
- sLLM은 평가 hard gate를 통과한 task에서만 활성화하고 GPU queue p95·실패율·비용을 routing에 반영한다.
- Object Storage와 Email은 adapter contract를 고정하고 사업자 결정은 환경 구성으로 제한한다.
- production topology 변경은 성능, 복구, 보안, 비용 증거를 첨부한 CDR 승인 대상이다.

## 8. 아키텍처 수용 기준

1. provider·storage·email·portal을 contract test로 대체할 수 있다.
2. 외부 AI egress가 AI Gateway를 우회하지 않는다.
3. API 중단 없이 worker와 AI serving을 독립 확장할 수 있다.
4. 문서·진단 실행을 version 정보로 재현할 수 있다.
5. 장애 시 핵심 포털·기존 보고서·검색은 정의된 degraded mode로 제공된다.
6. 변조·stale `DataUseContext`, cross-tenant 접근과 stale citation은 provider 호출 또는 데이터 노출 전에 거부된다.
7. `pilot-single-vm`과 `production-ha` evidence를 섞지 않고, availability SLO는 production-ha replica·failover·load·restore 증거가 fresh PASS인 기간에만 적용한다.
8. Linux application topology와 Windows converter topology는 queue/object/mTLS 계약으로만 결합되고 converter는 DB credential이나 raw HWP 우회 경로를 갖지 않는다.
