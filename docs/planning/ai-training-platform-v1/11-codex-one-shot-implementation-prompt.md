# 11. Codex 일괄 구현 프롬프트

문서 ID: CODEX-EXEC-011  
실행 계약: [한 명령 실행·복구 절차](13-one-command-execution.md), [Codex model-facing Structured Outputs schema](codex-output.schema.json), [strict 최종 결과 schema](codex-final-result.schema.json), [147개 최종 문서 inventory](final-document-inventory.json)를 따른다. 사용자가 프롬프트 일부를 복사하지 않고 guarded launcher가 이 문서 전체를 표준입력으로 전달한다. 첫 schema는 모델 출력 구조를 닫고, 두 번째 schema와 PowerShell validator가 상태·KPI·경로·Git handoff 의미를 fail-closed로 검증한다.

## 규범 우선순위

충돌 시 `design-baseline.json` → `15-normative-policy-and-interface-contracts.md` → 00~14 문서 → 현재 코드 순으로 적용한다. 계획 문서는 목표 계약이며 현재 코드가 계획을 축소하지 않는다. 경로·branch·remote·sandbox·승인 정책은 launcher preflight가 먼저 검증하므로 Codex가 자동 변경하거나 추측하지 않는다.

## 복사하여 사용할 단일 프롬프트

```text
당신은 YOnLab 보육교사 맞춤형 연수혁신 AI 플랫폼의 수석 아키텍트이자 구현 책임자다. `docs/planning/ai-training-platform-v1/`의 계획 원천 문서셋을 단일 source of truth로 사용하여 현재 checkout을 분석하고, 재사용 가치가 높은 부분은 보존하며, 목표 계약에 맞지 않는 부분은 테스트를 먼저 만든 뒤 교체하라. 단순 시제품이 아니라 Docker로 실행·검증할 수 있는 운영 전 개발 완료 후보를 만들어라.

[작업 위치와 원격]
- Windows 작업 경로: D:\Views\yonlab-inuri-site
- GitHub: https://github.com/yubi-lee/yonlab-i-nuri-site.git
- 현재 checkout/작업 branch: feat/ai-training-platform-v1
- 실행 기준 commit: launcher preflight를 통과한 위 branch의 현재 HEAD. 다른 base branch를 비교·선택하거나 fetch/rebase/reset으로 바꾸지 않는다. 구현 종료 시 이 기준점의 후손인 구현 commit `S`와 그 직계 first-parent 자식인 release snapshot commit `R`을 별도로 만든다.
- 계획 원천 문서: docs/planning/ai-training-platform-v1/README.md, design-baseline.json 및 00~15 문서
- 최종 설계 출력 경로: docs/design/ai-training-platform/. 이 경로를 계획 원천으로 사용하지 않는다.
- UniClaudeProxy 상세 평가는 계획 원천에 연결된 AI Gateway 재사용 설계를 참고한다.

[절대 원칙]
1. 목표 문서는 최종 시스템을 뜻한다. As-Is/To-Be로 범위를 축소하거나 현재 구현 여부를 완료 기준으로 삼지 마라.
2. i-누리 등 타 사이트의 코드, 문구, 이미지, 첨부, 고유 화면 배치를 복제하지 마라. 공개 인터페이스와 추상 사용자 흐름만 clean-room 방식으로 참고하라.
3. 실제 개인정보·저작물·API secret을 seed, test, log, commit, screenshot에 넣지 마라.
4. LLM은 대화 evidence를 구조화할 뿐 역량 점수를 임의 생성하지 않는다. 점수·level·confidence는 RubricVersion과 ScoringPolicyVersion으로 결정적으로 계산하라.
5. 페르소나는 6개 대표 family 아래 12개 operational profile probability와 6-family aggregation을 출력하며 사용자 수정이 가능해야 한다. 의료·심리 진단, 인사평가, 낙인에 사용하지 마라.
6. 검색은 tenant/ACL/license filter를 retrieval 전에 적용한다. 중요한 claim은 검증 가능한 문서 version+page+node/table/cell citation이 없으면 제공하지 마라.
7. HWPX를 canonical 생성 형식으로 사용한다. HWP 변환은 network·credential이 없는 untrusted converter child sandbox와 broker/object/telemetry allowlist 및 short-lived capability만 가진 별도 bridge host로 분리하라. production converter 또는 HWP golden evidence가 없으면 해당 gate를 `BLOCKED`, 전체 `release_state`를 `NOT_READY`로 판정하라.
8. Restricted 데이터는 외부 AI로 전송하지 마라. 모든 AI 호출은 신규 YOnLab AI Gateway를 통과해야 한다.
9. UniClaudeProxy 자체를 production data plane으로 배치하지 마라. 필요한 변환/RAG 개념만 license notice·보안검토·시험 후 adapter 내부에서 재구현하라.
10. test 실패, 명령 부재, 환경 부재를 PASS로 처리하지 말고 PASS/FAIL/BLOCKED를 fail-closed로 구분하라.
11. 사용자에게 매 단계 승인을 반복 요청하지 말고 안전한 기본값으로 진행하라. destructive action, 실제 비용 결제, production 배포, main merge, 기존 tag 이동만 중단 조건이다.

[guarded release 불변식]
- 이 프롬프트는 launcher의 `Implement` mode에서만 실행된다. Codex의 `release_state`는 항상 `NOT_READY`다. 별도 `candidate_phase`만 `IMPLEMENTATION_BLOCKED` 또는 `UNSIGNED_CANDIDATE / REVIEW PENDING` 중 하나로 출력한다. `CODE_COMPLETE / ACCEPTANCE DATA PENDING`과 `ACCEPTED`를 출력하거나 서명·승인·tag를 생성하지 마라.
- `UNSIGNED_CANDIDATE / REVIEW PENDING`에서만 구현과 구현 시험을 모두 포함한 full 40-hex commit을 `S`로 만든다. `S`의 tree OID와 tracked source bytes에서 계산한 `source-tree-hash.v1` SHA-256을 기록한다.
- `UNSIGNED_CANDIDATE / REVIEW PENDING`에서만 마지막에 문서·운영·QA·매뉴얼·릴리스·배포 문서만 정리한 full 40-hex commit `R`을 만든다. `R`은 부모가 정확히 하나이고 그 유일한 부모이자 direct first parent가 `S`여야 하며 `R != S`여야 한다.
- `IMPLEMENTATION_BLOCKED`이고 최종 후보 `S`·`R`을 만들지 못했다면 네 repository final identity 필드(`implementation_commit`, `implementation_tree`, `implementation_tree_sha256`, `release_snapshot_commit`)는 정확히 빈 문자열로 출력한다. baseline HEAD 또는 임의 hash를 `S`·`R`로 재사용하지 말고, `pull_request_url`은 null, blockers와 RESUME/REMEDIATE recovery action은 non-empty로 기록한다.
- `S..R` 변경 경로는 `docs/design/ai-training-platform/`, `docs/operations/ai-training-platform/`, `docs/qa/ai-training-platform/`, `docs/manuals/ai-training-platform/`, `docs/releases/ai-training-platform/`, `dist/docs/` 아래 regular file로만 제한한다. 이외 경로 변경, merge commit, submodule, symlink 또는 reparse point가 있으면 `NOT_READY`다.
- tracked evidence index, artifact manifest, checksum, source provenance와 최종 문서의 source identity는 모두 `S`와 `S`의 tree/hash에 결속한다. 아직 생성 중인 `R`의 OID·tag·PR·CI run URL을 tracked file에 넣어 자기참조를 만들지 마라. `R`은 최종 JSON의 `repository.release_snapshot_commit`과 외부 검증 입력으로만 보고한다.
- `S`와 `R`을 push하고 head가 `R`인 exact one non-fork feature→main PR을 준비한다. CI의 신뢰 workflow는 이 candidate가 생성·수정하는 파일이 아니라 사전에 `main`에 설치되고 외부 trust store에 workflow ID·path·SHA-256이 고정된 전제조건이다. `.github/workflows/`를 candidate에서 변경하지 마라.
- 기술 owner 7명, OWN-ACC, artifact 서명과 signed annotated tag는 보호된 외부 절차의 입력이다. workspace·Git history·tracked evidence에 receipt, detached signature 또는 GitHub run URL을 생성하지 마라.
- runner가 `release-trust.v2`로 exact 7개 direct executable(`powershell`, `python`, `git`, `gh`, `docker`, `codex`, `gpg`)의 path·SHA-256·ACL과 명시적으로 요구된 경우에만 Authenticode signer를 검증한다. ambient PATH, repository-local binary, `.cmd`/`.bat` shim으로 도구를 대체하거나 trust·attestation bytes를 생성·수정하지 마라.
- production runner 자체는 `[Environment]::SystemDirectory\WindowsPowerShell\v1.0\powershell.exe`와 exact argv prefix `-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1`로만 시작한다. wrapper, PowerShell 7/user 경로, `-Command`/`-EncodedCommand`, 축약·중복·unknown pre-File option을 허용하지 않는다. runner가 만드는 세 종류의 child process는 repository CWD를 상속하지 않고 각 pinned executable의 보호된 parent directory를 `WorkingDirectory`로 고정한다.
- `release-trust.json`, empty hooks, public-only GPG home, attestation root와 그 모든 intermediate/leaf는 runner 밖에서 미리 provision된 외부 root of trust다. 소유자는 `SYSTEM`·`Administrators`·`TrustedInstaller` 중 하나여야 하며, 보호 root 내부의 untrusted write/modify/delete/control과 volume root까지 상위 경로의 untrusted `DELETE_CHILD`/delete/ACL-control을 모두 금지한다. GPG home에는 exact UTF-8 no-BOM `gpg.conf` 한 줄 `no-auto-check-trustdb\n`과 non-empty preprovisioned `trustdb.gpg`가 있어야 하고 direct GPG에는 같은 `--no-auto-check-trustdb`를 강제한다. 모든 GPG call과 Git `verify-tag` 전후 snapshot이 달라지거나 symlink/junction/reparse, self-owned leaf, broad Allow ACE, 실행 중 ACL·tree·file SHA-256 snapshot 변경이 하나라도 있으면 진행하거나 우회하지 말고 `NOT_READY`로 중단하라.

[기본 기술 결정]
- Frontend: React, TypeScript, Vite, React Router, TanStack Query, React Hook Form+Zod, 접근성 우선 UI.
- Backend: FastAPI, Pydantic v2, SQLAlchemy 2, Alembic, PostgreSQL 17+pgvector.
- Async: Redis와 현재 코드에 가장 잘 맞는 Celery 또는 ARQ worker. 선택 이유를 CDR에 기록한다.
- Storage: 개발·CI는 MinIO 또는 local S3-compatible adapter, 운영은 S3-compatible StorageAdapter.
- Email: 개발은 console/Mailpit adapter, 운영은 provider-neutral EmailAdapter.
- Observability: OpenTelemetry trace, Prometheus-compatible metric, structured JSON log, 별도 audit event.
- AI: OpenAI Responses API+Structured Outputs adapter와 OpenAI-compatible sLLM/vLLM adapter. 실제 key가 없을 때도 deterministic provider stub로 전체 gate가 통과해야 한다.
- sLLM model은 코드에 고정하지 말고 ModelDeployment registry로 Qwen3/gpt-oss 후보를 평가·선택할 수 있게 한다. 대형 모델을 자동 다운로드하지 마라.
- 문서: HWPX native XML parser는 필수다. HWP converter/OCR provider contract와 simulator도 필수지만 simulator는 HWP 수용 증거가 아니다. 실제 승인 binary/license·sandbox·golden corpus가 없으면 production HWP gate는 `BLOCKED`이고 전체 상태는 `NOT_READY`이며, 선택 profile 비활성으로 숨길 수 없다. 핵심 HWPX/RAG 시험도 반드시 PASS해야 한다.

[작업 시작]
1. AGENTS.md, README, git status/log/branch/remote/tag, `docs/planning/ai-training-platform-v1/`, backend/frontend/infra/scripts/tests를 읽는다.
2. 현재 checkout이 `feat/ai-training-platform-v1`이 아니거나 worktree가 dirty이면 변경하지 말고 `NOT_READY`로 보고한다. preflight를 통과하면 현재 HEAD를 그대로 실행 기준으로 사용하며 base 비교, fetch, rebase, reset, 새 worktree/branch 생성 또는 branch 전환을 하지 않는다.
3. 기존 기능을 요구사항·화면·CDD·API·시험 ID에 매핑한 reuse matrix를 작성한다. 다음은 우선 재사용 후보: 인증 rotation/reset, 관리자 bootstrap, PostgreSQL migration, Docker 검증, backup/restore, 기존 CMS·Playwright·seed 구조. provider 직접결합, 거대 단일 모듈, 근거 없는 AI, 권한·version 누락은 재작성 후보로 분류한다.
4. 계획 원천이 누락되면 해당 gate를 `BLOCKED`, 전체 상태를 `NOT_READY`로 보고한다. 계획 원천을 읽어 `docs/design/ai-training-platform/`의 최종 설계 산출물을 생성·갱신하고 design verifier에 연결한다.
5. 구현 plan을 docs/superpowers/plans/YYYY-MM-DD-ai-training-platform-v1.md에 체크박스와 정확한 파일·시험·명령으로 작성한다. 계획 작성 후 멈추지 말고 실행한다.

[구현 순서: 각 항목은 RED→GREEN→REFACTOR→DOCS→COMMIT]

A. Foundation
- backend/app을 core, api, db, domains, integrations, workers, observability, `generated_clients/ai_gateway` 경계로 정리한다. AI Gateway service·provider SDK·routing·credential 구현을 backend package에 두지 마라.
- frontend/src를 app, feature, shared 경계로 정리하되 기존 화면 회귀시험을 보존한다.
- PostgreSQL+pgvector, Redis, worker, S3-compatible storage, Nginx를 Docker Compose profile로 구성한다.
- health/live, health/ready, migration one-shot, synthetic seed, secret scan, cleanup을 구현한다.

B. Identity·Consent
- access token, DB refresh rotation/replay detection, reset token, logout/logout-all을 유지·강화한다.
- `platform-openapi.json`은 screen-scoped 113개와 service-auth 4개를 병합한 deployed 117-operation/61-write/56-GET 계약으로 구현한다. 인증 set은 `legacy-reuse-decision-matrix.json.authentication_api_union_contract`의 screen 9개와 refresh/logout/logout-all/password-reset-confirm 4개 합집합 13개와 exact 일치시키고, service-auth의 field code·wire name·BODY/HEADER/COOKIE 위치·requiredness·schema·status·error·security·state transition을 그대로 생성한다. 모든 write body는 `required=true`다. `T-API-001`, `T-SEC-005`로 누락·중복·replay·family revoke·DataUse binding을 검증한다.
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
- `12-ui-ux-visual-system.md`의 token, component state, viewport, 한국어 font, reduced-motion/high-contrast, visual regression·수동 접근성 evidence 계약을 그대로 구현한다.
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
- AI: deterministic scoring, evidence schema, 12 operational profile probability와 6-family aggregation, fairness slice, 추천 적합·설명, 외부 egress.
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
- `14-final-document-deliverables.md`의 파일별 owner·gate·출력 경로를 누락 없이 생성하고 manifest/checksum 재현성을 검증한다.
- architecture/CDD/CDR, ERD/data dictionary, OpenAPI, model/prompt/schema registry, AI model card, evaluation report를 현행화한다.
- 사용자·관리자·운영자 매뉴얼과 배포·backup·restore·rollback·incident·DR runbook을 실제 명령으로 작성한다.
- 요구사항→설계→코드→시험→증거 traceability matrix를 생성한다.
- 선택된 OpenAI/sLLM deployment와 평가결과, 데이터 라우팅, license를 기록한다.
- 실제 시범운영 전 필요한 기관 승인·전문가 라벨·provider 계약은 명확한 acceptance input으로 분리한다.

[Git·GitHub]
- 사용자의 기존 변경을 보존한다.
- WP 단위 conventional commit을 생성하되, 모든 구현·시험·configuration을 포함한 마지막 implementation commit을 `S`로 고정한 후 final snapshot 전용 commit `R`을 한 번만 더 생성한다.
- `R` 생성 전 `S`에서 전체 gate와 `git diff --check`를 실행하고, `R` 생성 후에는 `R^1 == S`, parent 수 1, `S..R` allowlist, tracked inventory·manifest·checksum·evidence의 `S` binding을 다시 검증한다.
- feature branch의 `S`와 `R`을 origin에 push하고, feat/ai-training-platform-v1 → main의 exact one open non-fork draft PR을 생성하거나 갱신한다. PR head는 정확히 `R`이어야 한다.
- `main`에 사전 설치된 신뢰 workflow만 사용한다. runner가 외부 trust store의 exact workflow ID·path·content SHA-256·actor allowlist·required runner label과 live GitHub API 사실을 대조하므로 Codex는 workflow를 생성·수정하거나 check 성공을 자기 보고로 대체하지 마라.
- `design-package-linux`, `design-package-windows`, `security-and-schema`, `release-signatures`를 포함한 신뢰 check set은 runner가 exact PR, workflow ID/path/hash, event, head `R`, allowed actor, job name, conclusion, exact runner label을 live API로 독립 검증한다. tracked file에 check/run URL을 저장하지 마라.
- main merge, production 배포, release tag 생성/이동, 서명·승인 생성은 하지 않는다.

[완료 판정]
다음 공통 조건이 모두 충족되어야 완료 후보 상태를 판정할 수 있다.
1. 필수 기능·화면·migration·API·worker·운영 script가 구현됨.
2. 목표 문서 요구사항과 시험 ID의 미추적 항목이 0개.
3. 로컬 전체 gate와 isolated Docker gate가 PASS하며 false-positive가 없음.
4. Critical/High 보안 결함, cross-tenant leak, Restricted external egress가 0개.
5. HWPX golden parser, RAG citation, deterministic diagnosis, 12 operational profile probability와 6-family aggregation, 추천·경로 E2E가 PASS.
6. 신규 clone에서 setup→verify→run 절차가 재현됨.
7. git status가 clean하고 branch가 origin과 동기화됨.

- 위 7개 공통 조건을 만족하고 `S`·`R` 불변식과 tracked artifact/evidence의 `S` binding을 만족하면 Codex는 `release_state=NOT_READY`, `candidate_phase=UNSIGNED_CANDIDATE / REVIEW PENDING`을 출력한다. 외부 수용 입력이 남아 있어도 구현 미완료, `FAIL`, `BLOCKED`, 누락, stale 증거를 이 phase로 숨길 수 없다.
- 위 조건을 하나라도 만족하지 못하면 `release_state=NOT_READY`, `candidate_phase=IMPLEMENTATION_BLOCKED`다. `CODE_COMPLETE / ACCEPTANCE DATA PENDING`과 `ACCEPTED`는 Codex 출력이 아니라 각각 외부 보호 입력을 읽기 전용으로 검증하는 runner의 `VerifyCandidate`·`VerifyAccepted` mode만 판정한다.

[최종 보고 형식]
마지막 응답은 설명용 Markdown이 아니라 launcher가 `--output-schema codex-output.schema.json`으로 요구하는 JSON 객체 하나만 출력한다. 이 객체는 이어지는 `codex-final-result.schema.json`과 `validate-codex-final-result.ps1` 검증도 모두 통과해야 한다. 다음을 반드시 지킨다.

- `release_state`는 반드시 `NOT_READY`다. `candidate_phase`는 `IMPLEMENTATION_BLOCKED` 또는 `UNSIGNED_CANDIDATE / REVIEW PENDING` 중 하나다. Codex가 `CODE_COMPLETE / ACCEPTANCE DATA PENDING` 또는 `ACCEPTED`를 `release_state`로 출력하면 schema 형태와 관계없이 launcher가 거부한다.
- 기준선의 8개 gate를 모두 키로 출력하고, 각 gate에 `status`, `freshness`, `summary`, 실제 `evidence_paths`를 기록한다.
- `kpi_results`는 `KPI-001`~`KPI-010`을 정확히 한 번씩 포함하고 baseline comparison·threshold를 바꾸지 않는다. 구현 가능한 `KPI-003/004/005/008/009`는 외부 수용 대기로 숨길 수 없다.
- `verification_commands[*].acceptance_id`는 PASS/FAIL/BLOCKED일 때 null이다. `REQUIRES_ACCEPTANCE_DATA`일 때만 실제 `acceptance_data[*].id`와 1:1로 연결한다.
- 실행하지 않은 시험, 누락 명령, 오래된 결과, 환경 부재는 PASS가 아니다.
- `candidate_phase=UNSIGNED_CANDIDATE / REVIEW PENDING`은 모든 구현 가능 gate가 fresh PASS이고, 허용된 외부 수용 gate만 fresh `REQUIRES_ACCEPTANCE_DATA`이며, `blockers=[]`, clean worktree, origin push, head `R` PR, nonempty 생성 문서·commit 목록을 모두 요구한다.
- `generated_documents`는 `final-document-inventory.json`의 `${release_id}` literal expansion으로 계산한 147개 exact path와 같아야 한다. 하나라도 없으면 `NOT_READY`와 blocker로 기록한다.
- `UNSIGNED_CANDIDATE / REVIEW PENDING` 후보는 실제 40자 `S`·`R`, `S` tree/hash, push 상태, PR URL, 최종 clean 여부를 거짓 없이 기록한다. `IMPLEMENTATION_BLOCKED`는 아직 존재하지 않는 S/R을 보고하지 않으며 네 final identity 필드를 빈 문자열, PR URL을 null로 기록한다. PR URL은 model result에만 보고하고 tracked evidence에 복사하지 마라.
- `release_attestation`의 technical approval, artifact signature, acceptance approval, tag/verification 필드는 비어 있거나 null이어야 한다. 서명·receipt·tag를 자기 생성하지 마라.
- gate/KPI/verification command가 가리키는 모든 증거는 `docs/qa/ai-training-platform/evidence-index.json`의 고유 row에 exact `artifact_path`, actual SHA-256, source commit `S`, `FRESH`, 미래 expiry로 등록한다. index 전체의 FAIL/BLOCKED/MISSING/STALE을 숨기지 않는다.
- PASS 또는 `REQUIRES_ACCEPTANCE_DATA` gate는 fresh·nonempty evidence를 가져야 하며, PASS verification command의 exit code는 0이어야 한다.
- `candidate_phase=IMPLEMENTATION_BLOCKED`에는 모든 FAIL/BLOCKED/MISSING/STALE 원인과 복구 방법을 `blockers`에 기록한다. final S/R/tree/hash 필드는 빈 문자열이어야 하고 `pull_request_url`은 null이어야 한다. `next_action.kind`는 `RESUME` 또는 `REMEDIATE`이고 command는 non-empty여야 하며, worktree_clean·push_status·commits는 실제 Git 상태와 일치하게 보고한다.
- 구현 기능·화면·아키텍처, 재사용/재작성, AI routing/privacy, HWP, migration/seed/운영 결과는 `summary`, `generated_documents`, `verification_commands`와 evidence에 추적 가능하게 남긴다.
- phase별 계약에 맞는 identity(`UNSIGNED_CANDIDATE / REVIEW PENDING`의 실제 S/R 또는 `IMPLEMENTATION_BLOCKED`의 빈 문자열), push 상태, PR URL 또는 null, 최종 clean 여부를 거짓 없이 기록한다. PR URL은 model result에만 보고하고 tracked evidence에 복사하지 마라.
- 중단 후 재개가 필요하면 `next_action.kind=RESUME`과 guarded launcher가 출력한 resume command를 기록한다.

진행 중에는 60초 이상 무응답하지 말고 간결한 진척·검증 결과를 공유하라. 단순 계획 보고로 끝내지 말고 위 중단 조건이 아닌 한 구현, 시험, 문서, commit, push, PR까지 계속 진행하라.
```

## 실행 전 준비

1. 계획 문서, 기준선과 연결된 AI Gateway 재사용 설계를 저장소 `docs/planning/ai-training-platform-v1/`에 준비한다. `docs/design/ai-training-platform/`은 구현 과정에서 생성·갱신할 최종 설계 출력 경로로 사용하며 계획 원천으로 취급하지 않는다.
2. 저장소에서 실제 secret이 아닌 `.env.example`과 provider stub을 유지한다.
3. Docker Desktop, Git, Node.js, Python과 GitHub 인증 상태를 확인한다.
4. 실제 OpenAI key, HWP 상용 변환기, GPU model은 핵심 코드·stub 시험 이후 승인된 stage에서만 연결한다.

## 기대 결과

프롬프트는 Codex가 기존 운영 준비 자산을 버리지 않고 목표 설계의 domain 경계로 확장하며, 구현·시험·최종 설계·운영 가이드·GitHub 반영을 하나의 작업으로 끝까지 수행하도록 구성되어 있다. 사람의 최종 승인이 필요한 production 배포, 실제 개인정보, 유료 provider, main merge는 자동 범위에 포함하지 않는다. 실제 호출은 `workspace-write`와 `on-request` 승인 정책을 고정한 launcher만 사용한다.
