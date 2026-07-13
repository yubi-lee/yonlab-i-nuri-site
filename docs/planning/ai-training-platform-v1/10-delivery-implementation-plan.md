# 10. 구축·전환·산출물 계획

문서 ID: PLAN-180D-010  
기간 기준: 착수일 D부터 180일

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 보육교사 AI 역량진단, 맞춤 학습, HWP Document AI/RAG와 운영체계를 독립 배포 가능한 YOnLab 플랫폼으로 완성한다.

**Architecture:** React 포털과 FastAPI domain API를 중심으로 PostgreSQL+pgvector, Redis worker, Object Storage, AI Gateway와 외부 Adapter를 분리한다. 결정적 진단 scoring, 구조보존 문서처리, evidence-first RAG를 versioned contract와 평가 gate로 통제한다.

**Tech Stack:** React, TypeScript, Vite, FastAPI, Pydantic, SQLAlchemy, Alembic, PostgreSQL, pgvector, Redis, worker, S3-compatible storage, OpenTelemetry, Docker Compose, Playwright.

## Global Constraints

- 제안요청서 60개 요구사항과 SYS-F-001~018, SYS-NF-001~015를 모두 추적한다.
- 타 포털의 코드·문구·이미지·첨부·고유 배치를 복제하지 않는다.
- LLM은 evidence를 구조화하고 점수는 versioned deterministic rule로 계산한다.
- Restricted 데이터는 외부 AI로 전송하지 않는다.
- HWPX는 canonical 생성 형식이고 HWP 변환은 격리 worker에서 수행한다.
- 모든 기능은 provider stub과 synthetic fixture로 CI 검증 가능해야 한다.
- 각 기능은 실패시험→최소 구현→통과→통합시험→문서→작은 커밋 순으로 진행한다.

---

## 1. 단계별 일정과 Gate

| 단계 | 기간 | 구축 내용 | Gate·산출물 |
|---|---|---|---|
| 0. 착수·기준선 | D1~10 | 요구·역할·규정·데이터·위험·WBS 승인 | 요구추적표, CDR-0, 품질·보안·형상 계획 |
| 1. 기반·Golden set | D11~30 | repo/CI, 환경, design system, framework/rubric, 평가셋 | 빈 DB migration, provider stub, baseline 평가 |
| 2. 계정·진단 | D31~60 | auth/consent, 프로필, 대화, evidence, scoring, 결과 UI | T-AI-001~004, auth/security, E2E |
| 3. 페르소나·추천 | D51~80 | 6 persona, 추천정책, 경로, 실천과제 | T-AI-005~008, T-REC-001~007 |
| 4. Document AI | D46~90 | upload, HWPX/HWP/PDF, OCR, DocumentGraph, 검수 | T-DOC-001~007 |
| 5. RAG·초안 | D76~110 | hybrid retrieval, citation, no-answer, HWPX draft | T-DOC-008~012 |
| 6. 리포트·운영콘솔 | D91~120 | 성과, cohort, 모델·품질·비용·감사 console | T-RPT, T-OPS, 관리자 E2E |
| 7. 통합·비기능 | D111~135 | adapter, 성능, 접근성, 보안, backup/DR | system Gate, High/Critical 0 |
| 8. 1차 시범·FGI | D136~150 | 200명 1차, 분석, 전문가 FGI | T-PILOT-001~003, 변경승인 |
| 9. 개선·2차 시범 | D151~168 | 승인 개선, 회귀, 2차 운영 | T-PILOT-004~006 |
| 10. 수용·전환 | D169~180 | 운영 배포, 교육, 기술이전, 하자체계 | 최종 수용, restore/rollback 증적 |

## 2. 구현 Work Package

### WP-01 Repository·Platform Foundation

- [ ] 기존 repository의 유지 가능한 auth/CMS/API/검증 자산을 contract 기준으로 inventory한다.
- [ ] domain별 backend package와 frontend route 경계를 고정하고 OpenAPI client 생성을 구성한다.
- [ ] PostgreSQL+pgvector, Redis, Object Storage, worker, telemetry를 Compose profile로 구성한다.
- [ ] 빈 DB migration, synthetic seed, health/readiness, secret scan을 fail-closed gate로 만든다.
- [ ] CI에서 lint, type, unit, migration, build, Playwright, container scan을 실행한다.

독립 완료: 신규 clone에서 한 명령으로 build·migration·seed·smoke·cleanup이 PASS한다.

### WP-02 Identity·Consent·Administration

- [ ] 가입·로그인·rotation·replay detection·reset·logout-all 실패시험을 작성한다.
- [ ] 역할·기관 ABAC와 고권한 MFA/재인증 policy를 구현한다.
- [ ] 목적별 동의, 철회, export, deletion workflow를 구현한다.
- [ ] production admin bootstrap과 demo account 차단 preflight를 구현한다.
- [ ] 사용자·기관·권한·동의 운영화면과 감사를 구현한다.

독립 완료: cross-tenant/IDOR·token replay·철회 후 처리 차단 시험이 PASS한다.

### WP-03 Diagnosis Engine

- [ ] 역량·rubric·indicator version schema와 관리자 승인 workflow를 구현한다.
- [ ] DiagnosisSession state machine과 SSE turn API를 실패시험부터 구현한다.
- [ ] AI Gateway evidence schema adapter와 정형 fallback을 구현한다.
- [ ] 결정적 scoring·confidence·상충·재산정 snapshot을 구현한다.
- [ ] 진단 안내·대화·결과·근거 수정 화면과 접근성 E2E를 구현한다.

독립 완료: T-AI-001~004와 전문가 일치 baseline이 통과한다.

### WP-04 Persona·Recommendation·Learning

- [ ] 6개 versioned PersonaDefinition과 확률·미확정·사용자 수정 rule을 구현한다.
- [ ] hard filter, ranking, diversity, 설명 feature를 구현한다.
- [ ] LearningPath DAG, 단계·대체·실천과제·완료 event를 구현한다.
- [ ] 추천·경로·학습·실천 UI와 관리자 정책 UI를 구현한다.
- [ ] fairness slice, 적합도, 설명 충실도 평가를 배포 gate에 연결한다.

독립 완료: T-AI-005~008과 T-REC-001~007이 통과한다.

### WP-05 Document Intake·Structure

- [ ] signed upload, 권리·ACL, checksum, quarantine 실패시험을 구현한다.
- [ ] HWPX parser와 DocumentGraph/table topology fixture를 TDD로 구현한다.
- [ ] HWP 격리 converter와 PDF/OCR adapter contract를 구현한다.
- [ ] processing state, retry/dead-letter, quality score와 검수 UI를 구현한다.
- [ ] 파생물 lineage, version publication과 삭제 propagation을 구현한다.

독립 완료: T-DOC-001~007이 golden corpus에서 통과한다.

### WP-06 Retrieval·RAG·Draft

- [ ] 계층 chunk와 BM25/pgvector/index snapshot을 구현한다.
- [ ] ACL-first retrieval, RRF, reranker adapter와 평가 harness를 구현한다.
- [ ] claim-citation schema, locator validator, 상충/no-answer 정책을 구현한다.
- [ ] RAG 대화·근거 뷰어를 구현하고 cross-tenant adversarial test를 추가한다.
- [ ] TemplateVersion, structured field generation, deterministic HWPX builder, 검수·내보내기를 구현한다.

독립 완료: T-DOC-008~012와 KPI-003~004가 통과한다.

### WP-07 AI Gateway·Evaluation

- [ ] canonical request/response, data policy, model/prompt/schema registry를 구현한다.
- [ ] OpenAI Responses/Structured Outputs와 sLLM/vLLM adapter를 contract test로 구현한다.
- [ ] quota, timeout, retry, circuit breaker, fallback, cost ledger를 구현한다.
- [ ] versioned dataset·slice·metric·hard gate와 stage shadow/canary를 구현한다.
- [ ] 모델·프롬프트·평가·비용·fallback 운영화면과 alert를 구현한다.

독립 완료: provider를 교체해도 domain test가 변하지 않고 Restricted egress가 0이다.

### WP-08 Reporting·Pilot·Operations

- [ ] versioned fact와 개인·기관 ReportSnapshot을 구현한다.
- [ ] 소수집단 privacy threshold와 accessible PDF export를 구현한다.
- [ ] cohort, 설문, FGI, 개선요청 상태·dashboard를 구현한다.
- [ ] OpenTelemetry, structured log, metric, trace, audit, SLO alert를 구성한다.
- [ ] backup/restore, deploy, rollback, index rebuild, incident runbook을 자동·문서화한다.

독립 완료: T-RPT, T-PILOT, T-OPS, T-DR이 승인 환경에서 통과한다.

## 3. 파일 구조 목표

```text
frontend/src/
  app/ features/{auth,diagnosis,recommendation,learning,documents,rag,drafts,reports,admin}/
  shared/{api,ui,a11y,telemetry}/
backend/app/
  api/ core/ db/ domains/{identity,diagnosis,recommendation,learning,documents,retrieval,drafts,reports}/
  ai_gateway/{contracts,policy,providers,evaluation}/
  integrations/ workers/ observability/
backend/tests/{unit,component,integration,security,ai_eval,document_eval}/
infra/{compose,nginx,monitoring}/
docs/{design,operations,qa,releases}/
scripts/{setup,verify,backup,restore,deploy,rollback}/
```

기존 큰 파일은 동작을 보존하는 characterization test를 먼저 만든 뒤 domain 경계로 이동한다. 단순 미관을 위한 전면 재작성은 하지 않지만, provider 직접호출·권한 누락·version 미보존 코드는 재사용하지 않는다.

## 4. 산출물

- 요구사항·추적표, CDR/CDD, 화면·데이터·API·보안 설계
- source, migration, lockfile, container/IaC, SBOM
- AI prompt/schema/model registry export와 평가셋 manifest
- HWP/HWPX golden corpus와 parser·RAG·draft 평가 결과
- 단위·통합·E2E·접근성·성능·보안·수용 시험 보고서
- 사용자·관리자·운영자 매뉴얼, 교육자료, 기술이전 기록
- 배포·backup·restore·rollback·DR·incident runbook
- 시범운영·FGI·개선 추적과 최종 성과 보고서

## 5. 위험과 대응

| 위험 | 조기지표 | 대응 |
|---|---|---|
| HWP 복잡표 품질 미달 | topology 오류 증가 | HWPX native 우선, 검수 queue, converter 이중 경로 |
| 진단 오분류·낙인 | 수정률·slice 격차 | 확률·불확실도, user correction, deterministic rule |
| 외부 AI 정책·비용 변경 | 비용/지연/egress 경보 | registry·routing·sLLM fallback, task budget |
| 포털 연계 지연 | API/SSO 미확정 | simulator와 adapter, 독립 운영 deep link |
| 시범 표본 이탈 | 완료율 저하 | cohort 모니터링, 중단·재개, 저부담 경로 |
| 개인정보·권리 위반 | 미확인 field/license | ingestion gate, data registry, egress deny |
| 일정 병목 | critical path burn-up | 진단과 Document AI 병렬 WP, 주간 gate |

## 6. GitHub·형상 절차

- 기준 branch에서 `feat/ai-training-platform-v1`을 생성한다.
- WP 단위로 작은 conventional commit과 검증 증거를 남긴다.
- secret·운영 데이터·원문 권리자산·생성 artifact를 commit하지 않는다.
- 매 push 전 design verifier와 영향 범위 test를, PR 전 전체 gate를 실행한다.
- 인증된 원격에는 feature branch를 직접 push하고 draft PR을 생성·갱신한다.
- main merge, production deploy, release tag는 사람 승인 없이 수행하지 않는다.

## 7. 종료 조건

모든 요구사항이 구현·시험·증거에 연결되고 09 문서의 최종 판정이 `ACCEPTED`일 때 개발 완료 후보로 선언한다. Provider·hosting 같은 외부 선택이 남으면 안전하게 비활성화한 상태와 owner·결정기한을 명시하며, 핵심 시험 실패를 환경 차단으로 포장하지 않는다.

