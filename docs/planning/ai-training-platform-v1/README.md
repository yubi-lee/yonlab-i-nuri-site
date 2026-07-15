# YOnLab 보육교사 맞춤형 연수혁신 AI 플랫폼 목표 설계 문서셋

문서 기준일: 2026-07-13  
설계 상태: v1.1 목표 기준선
서비스 형태: YOnLab 독립 실행형 플랫폼 + 누리과정 포털 연계 Adapter  
구현 원칙: 공개 인터페이스와 추상적 사용자 흐름만 참고하는 Clean-room 개발

## 1. 문서 목적

본 문서셋은 제안요청서와 YOnLab 제안서를 기준으로 최종 서비스의 기능, 화면, 데이터, AI, 문서지능, 보안, 운영, 검증 및 구축 절차를 정의한다. 모든 문서는 완성될 목표 시스템을 일관되게 기술하며 구현 상태를 본문에서 구분하지 않는다. 경로, KPI 계산식·한계값, 페르소나 계층, 복구 목표 승인 상태와 판정 상태의 normative source는 [design-baseline.json](design-baseline.json)이다.

## 2. 설계 기준

- React·TypeScript 기반 반응형 사용자 포털과 관리자 콘솔
- FastAPI 기반 모듈형 API 및 AI orchestration
- PostgreSQL+pgvector, Redis, 비동기 worker, Object Storage
- OpenAI와 내부 sLLM을 함께 지원하는 Hybrid AI Gateway
- AI 대화 기반 역량진단과 결정적 rubric scoring
- 6개 대표 family 아래 12개 versioned operational profile의 확률적 분석과 사용자 수정
- 추천 연수, 기초-심화-적용 학습경로, 성과 리포트 연계
- HWP/HWPX 구조 보존형 Document AI와 grounded RAG
- HWPX canonical draft와 격리된 HWP 변환 worker
- 데이터 등급, 동의, 개인정보 최소화, 감사 및 모델 평가
- 200명×2회 시범운영과 전문가 FGI 기반 품질 개선

## 3. 문서 목록

| 번호 | 문서 | 역할 |
|---|---|---|
| 00 | [원천·의사결정 기준선](00-source-decision-baseline.md) | RFP·제안서·승인결정 우선순위와 성과목표 |
| 01 | [목표 범위와 요구사항 추적성](01-requirements-traceability.md) | 60개 RFP 요구사항, 시스템 요구, 검증 추적 |
| 02 | [사용자·기능·화면 설계](02-functional-screen-design.md) | 역할, 사용자 여정, 화면 IA, 상태·행동 설계 |
| 03 | [시스템 아키텍처와 CDD/CDR](03-system-architecture-cdd-cdr.md) | 구성도, 배포, 컴포넌트 책임, 결정사항 |
| 04 | [AI 역량진단·페르소나·추천 설계](04-ai-diagnosis-persona-recommendation.md) | 대화진단, scoring, 페르소나, 추천·성과 연계 |
| 05 | [Document AI·HWP RAG 설계](05-document-ai-hwp-rag.md) | HWP/HWPX 처리, 구조화, 검색, 근거, 초안 생성 |
| 06 | [AI Gateway·모델 선정 설계](06-ai-gateway-model-selection.md) | OpenAI/sLLM, routing, evaluation, fallback |
| 07 | [데이터·API·인터페이스 설계](07-data-api-interface-design.md) | 엔터티, ERD, API 계약, 이벤트·외부 연계 |
| 08 | [보안·개인정보·운영 설계](08-security-privacy-operations.md) | trust boundary, RBAC, consent, 배포·백업·관측 |
| 09 | [시험 절차서와 수용 기준](09-test-procedure-acceptance.md) | 단위·통합·AI·HWP·보안·성능·시범운영 시험 |
| 10 | [구축·전환·산출물 계획](10-delivery-implementation-plan.md) | 180일 단계계획, 산출물, Gate, 운영전환 |
| 11 | [Codex 일괄 구현 프롬프트](11-codex-one-shot-implementation-prompt.md) | 문서 기준 구현·검증·GitHub 반영 지시 |
| 12 | [UI/UX 비주얼 시스템](12-ui-ux-visual-system.md) | token, 한국어 타이포, 반응형, AI·citation 상태, 시각·접근성 증거 |
| 13 | [한 명령 실행·중단·복구 설계](13-one-command-execution.md) | fail-closed preflight, guarded Codex 실행, evidence·resume 계약 |
| 14 | [최종 문서 산출물 계약](14-final-document-deliverables.md) | 최종 설계·운영·runbook·QA·manual·release bundle 경로와 gate |
| 15 | [규범 정책·인터페이스 계약](15-normative-policy-and-interface-contracts.md) | AI 데이터 사용, tenant·권리, 결정적 정책, DocumentGraph/HWP 계약 |

기준선·검토 기록:

- [Machine-readable 설계 기준선](design-baseline.json)
- [RFP60·SYS33·139-test 양방향 registry](requirements-test-registry.json)
- [36-screen route·guard·API·state·E2E 계약](screen-route-contracts.json)
- [KPI-005 27-cell structured output matrix](kpi-005-structured-output-matrix.json)
- [진단·페르소나·추천 golden vectors](diagnosis-scoring-golden-vectors.json)
- [Machine-readable DocumentGraph JSON Schema 2020-12](document-graph.schema.json)
- [HWP converter bridge/child 격리 계약](hwp-conversion-boundary-contract.json)
- [Artifact manifest JSON Schema 2020-12](artifact-manifest.schema.json)
- [Evidence index JSON Schema 2020-12](evidence-index.schema.json)
- [Release trust provisioning non-secret template](release-trust.example.json)
- [Source-tree JCS hash golden vector](source-tree-hash-golden-vector.json)
- [147-item 최종 문서 normative inventory](final-document-inventory.json)
- [Machine contract deep semantic verifier](verify-machine-contracts.py)
- [Implementation completeness verifier](verify-completeness-contracts.py)
- [Public-safe source traceability manifest](source-traceability-manifest.json)
- [Public-safe source traceability mirror](source-traceability.md)
- [Source traceability verifier](verify-source-traceability.py)
- [OpenAPI 3.1 interface contract](platform-openapi.json)
- [AsyncAPI event contract](platform-asyncapi.json)
- [Persistent domain catalog](persistent-domain-catalog.json)
- [AI service and request contracts](ai-service-contracts.json)
- [Provider decision registry](provider-decision-registry.json)
- [RAG policy golden vectors](rag-policy-golden-vectors.json)
- [UI journey closure contract](ui-journey-contracts.json)
- [Normative 139-test semantics](normative-test-semantics.json)
- [TCH-015 authorization contract](tch-015-authorization-contract.json)
- [Codex Structured Outputs용 model-facing schema](codex-output.schema.json)
- [Machine-readable Codex 최종 결과 strict JSON Schema 2020-12](codex-final-result.schema.json)
- [v1.1 검토 변경 기록](REVIEW-CHANGELOG-v1.1.md)

별도 분석 근거:

- [AI Gateway 및 UniClaudeProxy 재사용 설계](../AI-Gateway-UniClaudeProxy-Reuse-Design.md)

## 4. 시스템 범위

### 사용자 서비스

- 회원·교사 프로필과 개인정보 동의
- AI 역량진단 챗봇
- 진단 근거·점수·불확실도 확인 및 정정
- 교사 페르소나 확인 및 수정
- 맞춤형 연수 추천과 학습경로
- 학습 이력·실천 과제·사후 진단
- 개인 성과 리포트
- HWP/HWPX/PDF 자료 검색·질의응답·요약
- 출처·페이지·표·셀 근거 확인
- 승인 템플릿 기반 HWPX 초안 생성
- 문의·피드백·접근성 지원

### 관리자·전문가 서비스

- 콘텐츠·연수·역량체계·루브릭 관리
- 페르소나·추천규칙·학습경로 관리
- 문서 수집·변환·OCR·검수·게시
- 프롬프트·모델·Schema·평가셋 관리
- AI 품질·비용·지연·fallback 관제
- 사용자·기관·권한·동의 관리
- 시범운영·FGI·개선요청 관리
- 개인·기관 성과 대시보드와 보고서
- 감사로그·보안·운영 상태 확인

## 5. 비범위와 통제

- 의료·정신건강 진단
- 교사 인사평가·채용·징계 결정
- AI가 근거 없이 확정하는 역량 점수
- 권리 검토되지 않은 포털 원문·이미지·첨부파일 복제
- 검수 없이 자동 배포되는 HWP/HWPX 문서
- 민감 데이터의 무조건적인 외부 AI 전송
- 모델 공급자 이름과 버전을 업무 코드에 직접 고정하는 구현

## 6. 완료 정의

본 설계는 다음 조건을 모두 충족할 때 구현 완료로 판정한다.

1. 모든 필수 요구사항이 구현 항목과 시험 사례에 연결됨
2. 사용자·관리자 핵심 여정이 데스크톱·태블릿·모바일에서 통과
3. 전문가 진단 일치도 0.85 이상
4. 추천 적합도 90% 이상
5. RAG Top-5 hit rate 95% 이상
6. 중요 claim citation coverage 95% 이상, invalid citation 0건
7. 구조화 출력 성공률 99.8% 이상
8. Restricted 데이터의 외부 전송 0건
9. HWP/HWPX 구조·인용·초안 생성 시험 통과
10. 보안·접근성·성능·백업복구·롤백 시험 통과
11. 200명×2회 시범운영 만족도 90/100 이상, 승인 개선 반영률 90% 이상
12. 모든 필수 증거가 fresh `PASS`일 때만 `ACCEPTED`; 수용 데이터만 남으면 `CODE_COMPLETE / ACCEPTANCE DATA PENDING`

## 7. 구현 에이전트의 필수 machine-readable 입력

구현은 Markdown 표를 다시 추측하지 않고 다음 순서로 입력을 로드한다.

1. `design-baseline.json`: 경로, KPI, gate reducer, release ID, signature/state 정책
2. `requirements-test-registry.json`: 요구↔설계↔화면/API↔시험↔증거 양방향 edge와 owner·test가 지정된 service-only API allowlist
3. `screen-route-contracts.json`과 `platform-openapi.json`: 36 screen, 42 primary/alias route, 113 screen API와 4 service-auth operation으로 구성된 총 117 operation, capability requirement와 E2E edge
4. `kpi-005-structured-output-matrix.json`과 두 golden vector: AI·source hash 결정성
5. artifact/evidence JSON Schema와 `fixtures/` positive/negative case
6. `final-document-inventory.json`: design 48개를 포함한 design/operations/runbook/QA/manual/release/distribution 총 147개 exact path와 외부 verifier에 고정된 canonical SHA-256

어느 registry든 ID·count·edge·root가 narrative와 다르면 임의 보정하지 않고 `GATE-DESIGN-INTEGRITY`를 실패시킨다. 요구 API 28개는 화면 API 113개 중 27개와 정확히 교차하고, 나머지 하나 `POST /internal/ai/v1/responses`는 owner·requirement·test·intent가 지정된 service-only operation이다. OpenAPI의 나머지 3개 service-only operation은 TCH-015 service-auth wire protocol을 구성한다. 화면 전용 86개 operation도 각 screen의 exact `requirement_ids`와 `e2e_test_ids`를 상속한다. unknown role, wildcard guard, 존재하지 않는 API, schema 핵심 제약 완화와 canonical inventory digest 변경은 overlay hash를 다시 계산해도 실패한다.

표준 라이브러리만 사용하는 deep semantic gate는 package 상위에서 다음과 같이 실행한다.

```bash
python3 yonlab-ai-training-platform-design/verify-machine-contracts.py --package-root yonlab-ai-training-platform-design
```

Windows에서는 같은 인자를 사용해 승인된 `python.exe`로 실행한다. 성공은 exit `0`과 terminal line `RESULT: PASS`, 모든 계약 위반·입력 오류·내부 예외는 nonzero exit와 terminal line `RESULT: FAIL`이다. Bash와 PowerShell 상위 verifier는 출력을 숨기거나 오류를 성공으로 바꾸지 않고 fail closed 한다.

## 8. 설치 및 한 명령 실행 계약

배포 패키지의 `overlay-manifest.json`은 이 디렉터리의 regular file 전체를 재귀 설치하되 package-only 검증기 `verify-design-package.sh`, `verify-design-package.ps1`, `test-verify-design-package.sh`만 제외한다. completeness/source/machine checker, schema, registry, fixture, golden vector와 회귀 테스트는 구현 저장소의 `docs/planning/ai-training-platform-v1/`에 원래 상대 경로를 보존해 함께 설치된다. 매니페스트 entry는 source, destination, SHA-256, byte length, `100644` mode를 모두 만족해야 한다.

설치 후 사람이 overlay 기준선을 commit하면 실행 명령은 다음 하나다.

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1'
```

설치 전 검증, 설치 dry run, 실제 설치, 중단·resume 및 운영 인수 절차는 [한 명령 실행·중단·복구 설계](13-one-command-execution.md)와 패키지 root `README.md`를 따른다. 실행기는 package verifier와 동일한 baseline·route·API·AI·source trace 계약을 입력으로 사용하며, 누락·오래된 증거·unknown 상태를 성공으로 축약하지 않는다.
