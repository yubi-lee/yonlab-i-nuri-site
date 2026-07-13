# 11. Codex 일괄 구현 프롬프트

문서 ID: CODEX-EXEC-011  
사용 방법: 아래 프롬프트와 본 설계 문서셋 전체를 Codex 작업 세션에 함께 제공한다.

## 복사하여 사용할 단일 프롬프트

```text
당신은 YOnLab 보육교사 맞춤형 연수혁신 AI 플랫폼의 수석 아키텍트이자 구현 책임자다. 다음 목표 설계 문서셋을 단일 source of truth로 사용하여 기존 저장소를 분석하고, 재사용 가치가 높은 부분은 보존하며, 목표 계약에 맞지 않는 부분은 테스트를 먼저 만든 뒤 교체하라. 단순 시제품이 아니라 Docker로 실행·검증할 수 있는 운영 전 개발 완료 후보를 만들어라.

[작업 위치와 원격]
- Windows 작업 경로: D:\Views\yonlab-i-nuri-site
- GitHub: https://github.com/yubi-lee/yonlab-i-nuri-site.git
- 기준 branch: 원격의 최신 main과 feat/production-readiness를 비교하고 더 완전한 검증·운영 자산을 가진 커밋을 기반으로 삼는다.
- 작업 branch: feat/ai-training-platform-v1
- 목표 설계 문서: docs/design/ai-training-platform/README.md 및 00~11 문서
- UniClaudeProxy 상세 평가는 docs/design/AI-Gateway-UniClaudeProxy-Reuse-Design.md를 참고한다.

[절대 원칙]
1. 목표 문서는 최종 시스템을 뜻한다. As-Is/To-Be로 범위를 축소하거나 현재 구현 여부를 완료 기준으로 삼지 마라.
2. i-누리 등 타 사이트의 코드, 문구, 이미지, 첨부, 고유 화면 배치를 복제하지 마라. 공개 인터페이스와 추상 사용자 흐름만 clean-room 방식으로 참고하라.
3. 실제 개인정보·저작물·API secret을 seed, test, log, commit, screenshot에 넣지 마라.
4. LLM은 대화 evidence를 구조화할 뿐 역량 점수를 임의 생성하지 않는다. 점수·level·confidence는 RubricVersion과 ScoringPolicyVersion으로 결정적으로 계산하라.
5. 페르소나는 6종 확률분포이며 사용자 수정이 가능해야 한다. 의료·심리 진단, 인사평가, 낙인에 사용하지 마라.
6. 검색은 tenant/ACL/license filter를 retrieval 전에 적용한다. 중요한 claim은 검증 가능한 문서 version+page+node/table/cell citation이 없으면 제공하지 마라.
7. HWPX를 canonical 생성 형식으로 사용한다. HWP 변환은 network와 credential이 없는 격리 worker profile로만 제공하라.
8. Restricted 데이터는 외부 AI로 전송하지 마라. 모든 AI 호출은 신규 YOnLab AI Gateway를 통과해야 한다.
9. UniClaudeProxy 자체를 production data plane으로 배치하지 마라. 필요한 변환/RAG 개념만 license notice·보안검토·시험 후 adapter 내부에서 재구현하라.
10. test 실패, 명령 부재, 환경 부재를 PASS로 처리하지 말고 PASS/FAIL/BLOCKED를 fail-closed로 구분하라.
11. 사용자에게 매 단계 승인을 반복 요청하지 말고 안전한 기본값으로 진행하라. destructive action, 실제 비용 결제, production 배포, main merge, 기존 tag 이동만 중단 조건이다.

[기본 기술 결정]
- Frontend: React, TypeScript, Vite, React Router, TanStack Query, React Hook Form+Zod, 접근성 우선 UI.
- Backend: FastAPI, Pydantic v2, SQLAlchemy 2, Alembic, PostgreSQL 17+pgvector.
- Async: Redis와 현재 코드에 가장 잘 맞는 Celery 또는 ARQ worker. 선택 이유를 CDR에 기록한다.
- Storage: 개발·CI는 MinIO 또는 local S3-compatible adapter, 운영은 S3-compatible StorageAdapter.
- Email: 개발은 console/Mailpit adapter, 운영은 provider-neutral EmailAdapter.
- Observability: OpenTelemetry trace, Prometheus-compatible metric, structured JSON log, 별도 audit event.
- AI: OpenAI Responses API+Structured Outputs adapter와 OpenAI-compatible sLLM/vLLM adapter. 실제 key가 없을 때도 deterministic provider stub로 전체 gate가 통과해야 한다.
- sLLM model은 코드에 고정하지 말고 ModelDeployment registry로 Qwen3/gpt-oss 후보를 평가·선택할 수 있게 한다. 대형 모델을 자동 다운로드하지 마라.
- 문서: HWPX native XML parser는 필수. HWP converter/OCR provider는 contract와 simulator를 필수로 하고 실제 상용 binary가 없으면 안전하게 BLOCKED가 아닌 선택 profile 비활성으로 표시한다. 핵심 HWPX/RAG 시험은 반드시 PASS해야 한다.

[작업 시작]
1. AGENTS.md, README, git status/log/branch/remote/tag, 기존 docs/design, backend/frontend/infra/scripts/tests를 읽는다.
2. dirty worktree가 있으면 사용자의 변경을 보존하고 겹치지 않는 새 worktree 또는 branch에서 진행한다. clean이면 최신 remote를 fetch하고 작업 branch를 생성·전환한다.
3. 기존 기능을 요구사항·화면·CDD·API·시험 ID에 매핑한 reuse matrix를 작성한다. 다음은 우선 재사용 후보: 인증 rotation/reset, 관리자 bootstrap, PostgreSQL migration, Docker 검증, backup/restore, 기존 CMS·Playwright·seed 구조. provider 직접결합, 거대 단일 모듈, 근거 없는 AI, 권한·version 누락은 재작성 후보로 분류한다.
4. 목표 문서가 repository에 없으면 제공된 00~11 문서를 docs/design/ai-training-platform에 먼저 넣고 design verifier에 연결한다.
5. 구현 plan을 docs/superpowers/plans/YYYY-MM-DD-ai-training-platform-v1.md에 체크박스와 정확한 파일·시험·명령으로 작성한다. 계획 작성 후 멈추지 말고 실행한다.

[구현 순서: 각 항목은 RED→GREEN→REFACTOR→DOCS→COMMIT]

A. Foundation
- backend/app을 core, api, db, domains, ai_gateway, integrations, workers, observability 경계로 정리한다.
- frontend/src를 app, feature, shared 경계로 정리하되 기존 화면 회귀시험을 보존한다.
- PostgreSQL+pgvector, Redis, worker, S3-compatible storage, Nginx를 Docker Compose profile로 구성한다.
- health/live, health/ready, migration one-shot, synthetic seed, secret scan, cleanup을 구현한다.

B. Identity·Consent
- access token, DB refresh rotation/replay detection, reset token, logout/logout-all을 유지·강화한다.
- Organization, Membership, Role/Permission, ConsentRecord, TeacherContext migration과 policy를 구현한다.
- 관리자 MFA/재인증 interface, production admin bootstrap, demo account production 차단을 구현한다.
- 내 데이터 export와 deletion/retention workflow를 구현한다.

C. Diagnosis
- 7개 역량, versioned indicator/rubric/anchor와 게시 승인 관리자 UI를 구현한다.
- DiagnosisSession 상태기계, DialogueTurn, EvidenceSpan, DiagnosisResult/CompetencyScore를 구현한다.
- evidence.v1 strict schema와 provider stub fixture를 만든다.
- 동일 evidence/rubric 결과가 항상 같은 scoring 함수와 low-confidence/상충 처리를 구현한다.
- TCH-003~006과 ADM-002 화면, SSE 중단·재개, evidence 정정·재산정을 구현한다.

D. Persona·Recommendation·Learning
- P-01~P-06 definition, probability, 혼합/미확정, supporting/contradicting factors와 사용자 수정 기능을 구현한다.
- content hard filter, versioned ranking, diversity, 결정적 추천 이유를 구현한다.
- 기초-심화-적용 DAG, Enrollment, Activity, PracticeTask와 사후진단 연결을 구현한다.
- TCH-007~010, ADM-003~005와 개인·기관 ReportSnapshot을 구현한다.

E. Document AI
- SourceDocument, DocumentVersion, FileObject, ProcessingJob/Artifact, DocumentNode, TableCell migration을 구현한다.
- signed upload, magic MIME, size, traversal, decompression ratio, malware adapter, quarantine를 구현한다.
- HWPX ZIP/XML parser로 문단·style·목록·병합/중첩표·이미지·각주와 source locator를 DocumentGraph v1에 보존한다.
- HWP 격리 converter, PDF text/OCR/layout adapter contract와 synthetic simulator를 구현한다.
- quality score, QA_PENDING, 원본-추출 검수 화면, version publish/withdraw와 lineage 삭제를 구현한다.

F. Retrieval·RAG·Draft
- hierarchy chunk, 한국어 lexical search, pgvector embedding, metadata/ACL filter, RRF와 reranker adapter를 구현한다.
- versioned IndexSnapshot과 atomic alias 전환을 구현한다.
- RAG response를 answer/claims/citations/answerability/limitations schema로 구현한다.
- citation locator 재검증, 상충 근거, no-answer, indirect prompt injection 방어를 구현한다.
- TCH-011~013 화면과 ADM-006~008을 구현한다.
- TemplateVersion, structured section/field generation, deterministic HWPX package builder, preview diff, 사람 검수, signed export와 TCH-014~015를 구현한다.

G. AI Gateway·Evaluation
- canonical request/response, DataPolicyEngine, ModelProvider/Deployment, RoutingPolicy, Prompt/SchemaVersion, ModelRun을 구현한다.
- OpenAI Responses API adapter는 공식 최신 SDK 계약과 Structured Outputs를 사용한다. secret과 원문은 log하지 않는다.
- sLLM adapter는 OpenAI-compatible endpoint를 사용하고 tokenizer/model/quantization/serving image version을 기록한다.
- timeout, cancellation, rate/quota, budget, exponential backoff+jitter, circuit breaker, fallback을 구현한다.
- versioned EvaluationSuite/Run, protected slice, hard gate와 ADM-009~011을 구현한다.

H. Pilot·Operations
- PilotCohort, 2회차, survey, FGI, improvement request workflow와 ADM-013~014를 구현한다.
- AuditEvent append-only/hash-chain, OutboxEvent, Notification, FeatureFlag와 ADM-015~016을 구현한다.
- OTel trace·metric·structured log, SLO dashboard configuration과 cost ledger를 구현한다.
- backup/restore, migration, deploy, rollback, index rebuild, incident/DR scripts와 runbook을 보강한다.

[화면 품질]
- 02 문서의 PUB-001~004, TCH-001~016, ADM-001~016을 모두 route와 권한에 연결한다.
- 1440/768/390 px에서 수평 overflow 없이 핵심 여정을 통과시킨다.
- loading/empty/error/partial/forbidden/stale/no-answer/reconnect 상태를 구현한다.
- keyboard, focus, contrast, reflow, screen reader, streaming live region, chart 대체표를 WCAG 2.2 AA로 검증한다.
- 기존 YOnLab navy·teal 디자인을 일관되게 확장하되 타 포털의 문구·자산·배치를 사용하지 않는다.

[데이터·API]
- 07 문서의 엔터티와 `/api/v1` 계약을 Alembic migration, Pydantic schema, OpenAPI와 일치시킨다.
- 모든 mutation에 policy와 audit를 적용하고 필요한 곳에 Idempotency-Key/If-Match를 지원한다.
- 장기 작업은 202+Job, 스트리밍은 SSE+Last-Event-ID, 오류는 application/problem+json을 사용한다.
- DB side effect와 외부 호출은 transactional outbox로 연결하고 consumer 중복을 제거한다.

[필수 시험]
- 09 문서의 모든 필수 시험 ID를 자동시험, 실행 script 또는 승인용 수동 절차에 연결한다.
- backend: lint, type if configured, unit/component/integration/security, 빈 DB migration, seed idempotency.
- frontend: ESLint, TypeScript, Vitest, production build, Playwright desktop/tablet/mobile와 접근성.
- AI: deterministic scoring, evidence schema, 6 persona, fairness slice, 추천 적합·설명, 외부 egress.
- Document: HWPX 문단/병합·중첩표 golden fixture, 악성·손상 파일, ACL, RAG Top-5, citation, no-answer, HWPX draft.
- Infra: isolated Docker build/up/readiness/migration/seed/API/worker/storage/restart/persistence/log scan/cleanup.
- Ops: production preflight, secret scan fallback, backup→변조→isolated restore, rollback simulation.
- 실제 전문가/200명 시범 데이터가 필요한 KPI는 synthetic harness와 실행 절차를 완성하고 `REQUIRES_ACCEPTANCE_DATA`로 분리하되, 구현 미완료를 그 상태로 숨기지 마라.

[검증 명령]
- 기존 scripts/verify-design-docs.ps1을 목표 문서까지 확장한다.
- scripts/verify.ps1 하나가 lint/test/build/migration/seed/Playwright/secret/Docker 핵심 gate를 실행해야 한다.
- scripts/verify-docker.ps1은 임의 project name과 격리 port를 사용하고 자신이 만든 resource만 정리한다.
- scripts/verify-production-readiness.ps1은 production env placeholder, demo secret/account, CORS/domain, backup age, health를 fail-closed 검사한다.
- 필요한 별도 명령: AI evaluation, Document golden evaluation, backup/restore drill. 전체 verify에서 결과를 집계한다.

[문서화]
- architecture/CDD/CDR, ERD/data dictionary, OpenAPI, model/prompt/schema registry, AI model card, evaluation report를 현행화한다.
- 사용자·관리자·운영자 매뉴얼과 배포·backup·restore·rollback·incident·DR runbook을 실제 명령으로 작성한다.
- 요구사항→설계→코드→시험→증거 traceability matrix를 생성한다.
- 선택된 OpenAI/sLLM deployment와 평가결과, 데이터 라우팅, license를 기록한다.
- 실제 시범운영 전 필요한 기관 승인·전문가 라벨·provider 계약은 명확한 acceptance input으로 분리한다.

[Git·GitHub]
- 사용자의 기존 변경을 보존한다.
- WP 단위로 의미 있는 conventional commit을 생성한다.
- 매 commit 전 영향 범위 시험, 최종 push 전 전체 gate와 git diff --check를 실행한다.
- feature branch를 origin에 직접 push한다.
- GitHub 인증이 가능하면 feat/ai-training-platform-v1 → main draft PR을 생성하거나 기존 PR을 갱신하고, 본문에 범위·설계·시험·위험·수동 수용항목을 작성한다.
- main merge, production 배포, release tag 생성/이동은 하지 않는다.

[완료 판정]
다음이 모두 충족될 때만 CODE COMPLETE / ACCEPTANCE DATA PENDING 또는 ACCEPTED로 선언하라.
1. 필수 기능·화면·migration·API·worker·운영 script가 구현됨.
2. 목표 문서 요구사항과 시험 ID의 미추적 항목이 0개.
3. 로컬 전체 gate와 isolated Docker gate가 PASS하며 false-positive가 없음.
4. Critical/High 보안 결함, cross-tenant leak, Restricted external egress가 0개.
5. HWPX golden parser, RAG citation, deterministic diagnosis, 6 persona, 추천·경로 E2E가 PASS.
6. 신규 clone에서 setup→verify→run 절차가 재현됨.
7. git status가 clean하고 branch가 origin과 동기화됨.

[최종 보고 형식]
1. 판정 등급과 근거
2. 구현 기능·화면·아키텍처
3. 기존 코드 재사용/재작성 내역
4. AI model·routing·privacy 결정
5. Document AI/HWP 처리 결과
6. migration·seed·운영 절차
7. 시험 명령과 실제 PASS/FAIL/BLOCKED 수치
8. 전문가/시범/외부 provider가 필요한 수용 항목
9. 보안·접근성·성능·복구 결과
10. commit 목록, push 결과, PR URL, clean status

진행 중에는 60초 이상 무응답하지 말고 간결한 진척·검증 결과를 공유하라. 단순 계획 보고로 끝내지 말고 위 중단 조건이 아닌 한 구현, 시험, 문서, commit, push, PR까지 계속 진행하라.
```

## 실행 전 준비

1. 이 폴더의 12개 번호 문서, README와 별도 AI Gateway 재사용 설계를 저장소 `docs/design/ai-training-platform/`에 복사한다.
2. 저장소에서 실제 secret이 아닌 `.env.example`과 provider stub을 유지한다.
3. Docker Desktop, Git, Node.js, Python과 GitHub 인증 상태를 확인한다.
4. 실제 OpenAI key, HWP 상용 변환기, GPU model은 핵심 코드·stub 시험 이후 승인된 stage에서만 연결한다.

## 기대 결과

프롬프트는 Codex가 기존 운영 준비 자산을 버리지 않고 목표 설계의 domain 경계로 확장하며, 구현·시험·문서·GitHub 반영을 하나의 작업으로 끝까지 수행하도록 구성되어 있다. 사람의 최종 승인이 필요한 production 배포, 실제 개인정보, 유료 provider, main merge는 자동 범위에 포함하지 않는다.
