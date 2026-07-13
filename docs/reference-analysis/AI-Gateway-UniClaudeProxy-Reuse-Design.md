# YOnLab AI Gateway 및 UniClaudeProxy 재사용 설계

문서 상태: 설계 기준선 후보  
작성일: 2026-07-13  
대상 시스템: 보육교사 맞춤형 연수혁신 AI 서비스  
판정: **CONDITIONAL REUSE — 운영용 AI Gateway는 별도 구현, 검증된 일부 구성요소와 설계 원칙만 재사용**

## 1. 목적

이 문서는 다음 두 요구를 하나의 목표 설계로 통합한다.

1. OpenAI API와 기관 내부 sLLM을 선택·교체·혼합 적용할 수 있는 AI 실행 계층 설계
2. `agent-localclaude-uniclaudeproxy`에서 검증된 프록시·RAG·오프라인 운영 방식을 분석하고 YOnLab 서비스에 재사용할 범위를 결정

본 문서는 구현 현황 보고서가 아니라 최종 서비스가 따라야 하는 목표 기준선이다.

## 2. 분석 범위와 증거

### 2.1 제공 아카이브

- 파일: `agent-localclaude-uniclaudeproxy-main.zip`
- SHA-256: `27aff2bd06b6b85b9069699d2da6a43e59315749f061c74e33370341293a0c86`
- 주요 구성:
  - 오프라인 AI 설치·운영 래퍼
  - UniClaudeProxy 설치 및 패치 로직
  - PDF/Markdown/Text RAG POC
  - 모델 평가 도구와 평가 보고서
  - 설치·검증·릴리스 도구

아카이브에는 UniClaudeProxy 본체 소스가 직접 포함되지 않는다. 설치기가 공개 upstream을 clone한 뒤 특정 커밋으로 고정한다.

### 2.2 고정 upstream

- 저장소: `vibheksoni/UniClaudeProxy`
- 고정 커밋: `2f512a3626a25d24cee4e2387db5007802928d4c`
- 커밋 일시: 2026-05-08
- upstream 라이선스: MIT
- 정적 문법 검사: Python `compileall` 통과
- 고정 커밋에는 자동화 테스트 디렉터리와 CI 구성이 없다.

### 2.3 주요 근거 파일

- `offline-setup/cli-installer-v7.0.0.py`
- `ragpoc-build/src/ragpoc/extract.py`
- `ragpoc-build/src/ragpoc/chunk.py`
- `ragpoc-build/src/ragpoc/store.py`
- `ragpoc-build/src/ragpoc/hybrid.py`
- `ragpoc-build/src/ragpoc/ocr.py`
- `tools/verify-install.sh`
- `eval-compare_v7.0.0/On-Premise-AI-Platform-Evaluation-Report.md`
- upstream `app/main.py`, `app/config.py`, `app/providers/*`, `app/converters/*`

## 3. 분석 결론

### 3.1 최종 판정

| 영역 | 판정 | 목표 시스템 적용 방식 |
|---|---|---|
| Anthropic ↔ OpenAI 형식 변환 | 조건부 재사용 | 개발·평가용 호환 어댑터로 격리 |
| SSE 스트리밍 변환 | 조건부 재사용 | 계약 테스트 통과 후 adapter 내부에서 사용 |
| 모델 alias 라우팅 | 개념 재사용 | DB 기반 Model Registry와 Policy Router로 재구현 |
| Ollama/vLLM 연결 | 재사용 | OpenAI-compatible sLLM adapter로 일반화 |
| 4채널 모델 매핑 | 개념 재사용 | 업무 유형 기반 N채널 라우팅으로 확장 |
| PDF 구조 추출 | 조건부 재사용 | Document AI worker의 PDF fallback으로 편입 |
| 하이브리드 청킹 | 재사용·확장 | HWPX DocumentGraph 기반 청킹과 결합 |
| BM25+vector+RRF | 재사용·확장 | PostgreSQL/pgvector 검색 서비스로 이전 |
| 페이지 원문 read 방식 | 적극 재사용 | Evidence Resolver와 근거 검증 단계로 승격 |
| 출처 문자열 강제 훅 | 개념만 재사용 | 문자열 존재가 아니라 근거 일치 검증기로 대체 |
| 파일 기반 vector store | POC 한정 | 운영은 PostgreSQL+pgvector+Object Storage 사용 |
| 운영용 공개 AI Gateway | 재사용 금지 | 인증·테넌트·감사·정책을 갖춘 별도 서비스 구현 |

### 3.2 핵심 판단

UniClaudeProxy는 Claude Code와 여러 모델 백엔드를 연결하는 로컬 개발 도구로는 유용하다. 그러나 다수 교사가 사용하는 웹 서비스의 중앙 AI Gateway로 직접 배포하기에는 인증, 개인정보 보호, 테넌트 격리, 비밀정보 관리, 장애 격리, 감사 및 운영 관측성이 부족하다.

따라서 다음과 같이 역할을 분리한다.

- **YOnLab AI Gateway**: 실제 서비스 요청을 처리하는 운영 구성요소
- **UniClaudeProxy compatibility adapter**: 개발자 도구 또는 오프라인 검증 환경에서만 사용
- **sLLM inference server**: vLLM 또는 검증된 OpenAI-compatible server
- **Document AI worker**: 문서 변환·OCR·구조화·임베딩을 비동기로 처리

## 4. 확인된 강점

### 4.1 공급자 형식 변환

고정 upstream은 Anthropic Messages 요청을 OpenAI Chat Completions, OpenAI Responses, Gemini 또는 Anthropic passthrough로 변환하고, 응답과 SSE 이벤트를 다시 Anthropic 형식으로 변환한다.

재사용 가치:

- 다양한 sLLM 서버에 대한 호환성 실험
- 스트리밍 및 tool call 변환 계약의 참조 구현
- 모델별 system prompt replacement
- 모델 alias와 upstream model ID 분리
- image mode와 reasoning 설정의 모델별 분리

### 4.2 재현 가능한 온프레미스 설치

설치 래퍼는 다음 운영 원칙을 구현한다.

- Claude Code, Ollama, UniClaudeProxy와 Python 의존성 버전 고정
- UniClaudeProxy upstream 커밋 고정
- CPU fallback과 GPU 최적화 분리
- 설치 후 동작 검증
- 모델 메모리 요구량 사전 경고
- 온라인 Claude 설정과 오프라인 설정 격리

이 원칙은 YOnLab의 sLLM 배포 절차에 재사용한다. 단, 실행 스크립트는 Docker image, SBOM, 서명된 artifact와 CI/CD 기반으로 다시 구현한다.

### 4.3 근거 우선 RAG

RAG POC는 검색 결과의 전체 본문을 무조건 프롬프트에 주입하지 않고 문서와 페이지 포인터를 먼저 반환한 뒤 필요한 페이지를 읽게 한다.

재사용 가치:

- 검색과 근거 읽기를 분리
- 페이지 단위 evidence locator
- 검색 결과가 없을 때 모델 지식 사용 여부를 표시
- 문서 커버리지 부족이 품질 저하로 이어진다는 운영 인식

YOnLab에서는 이를 `EvidenceCandidate → EvidencePassage → GroundedAnswer` 단계로 정식 데이터 모델화한다.

### 4.4 문서 처리 POC

RAG POC에는 다음 기능이 있다.

- PDF를 페이지별 Markdown으로 추출
- Markdown 표와 코드 블록 보존
- 반복 머리글·바닥글 제거
- 스캔 페이지 탐지와 RapidOCR fallback
- 한국어 OCR 모델과 기본 OCR 결과 비교
- 구조 청킹과 의미 청킹 결합
- BM25와 vector 결과의 RRF 융합
- 임베딩 모델·차원 불일치 탐지
- 증분 빌드 및 store 병합

이 기능은 PDF fallback 경로와 검색 평가 POC에 활용할 수 있다. HWP/HWPX 자체 구조는 지원하지 않으므로 HWP Document AI를 대신할 수는 없다.

## 5. 운영 적용을 막는 주요 격차

### 5.1 보안·개인정보

| 등급 | 발견 사항 | 영향 | 목표 조치 |
|---|---|---|---|
| Critical | `/v1/messages`에 사용자 인증이 없음 | 접근 가능한 사용자가 공급자 비용과 모델을 임의 사용 | OAuth2/JWT 또는 mTLS service identity 적용 |
| Critical | 공급자 API key가 `config.json` 평문 필드 | 파일 노출 시 외부 공급자 계정 침해 | Secret Manager·Docker secret·암호화된 reference 사용 |
| Critical | debug log에 요청 본문, 메시지 일부, upstream 본문과 응답 일부 기록 | 교사 대화·개인정보·문서 내용 유출 | 기본 payload logging 금지, 구조화·마스킹 로그 사용 |
| High | localhost 제한만 존재 | reverse proxy 또는 잘못된 bind 설정에서 우회 가능 | 네트워크 정책과 application auth를 함께 적용 |
| High | 사용자·기관·테넌트 격리 없음 | 다른 기관의 정책·비용·감사 분리 불가 | tenant_id, subject_id, service scope 적용 |
| High | request size와 image decoded size 제한 없음 | 메모리·디스크 DoS 가능 | ingress/body/file quota 적용 |
| High | rate limit과 비용 quota 없음 | 과금 폭주·서비스 고갈 가능 | 사용자·기관·업무별 token/cost quota 적용 |
| Medium | provider 예외 문자열을 사용자에게 반환 | 내부 endpoint와 오류 정보 노출 | 표준 오류 카탈로그와 내부 correlation ID 사용 |

`local_only=true`는 개발자 개인 PC의 방어선으로는 유효하지만 운영 서비스의 인증 수단이 아니다.

### 5.2 신뢰성·운영성

| 발견 사항 | 목표 조치 |
|---|---|
| provider timeout이 소스에 고정되어 설치기가 코드를 문자열 치환 | 환경 설정 기반 connect/read/write/pool timeout으로 재구현 |
| retry, backoff, circuit breaker, provider health routing 없음 | 상태 기반 router와 오류 유형별 재시도 정책 적용 |
| fallback 품질 자격을 검증하지 않음 | 같은 task profile 평가를 통과한 모델만 fallback 허용 |
| `/health`가 process 상태만 반환 | `/health/live`, `/health/ready`, provider/model dependency 상태 분리 |
| OpenTelemetry·Prometheus·비용 계량 없음 | trace, metrics, cost ledger, SLA dashboard 적용 |
| config file hot reload에 승인·버전·rollback이 없음 | DB version + staged activation + audit + rollback 적용 |
| 단일 process 공유 client와 단일 설정 | 공급자별 pool, concurrency limit, bulkhead 적용 |

### 5.3 품질·시험

- 고정 UniClaudeProxy 커밋에는 자동화 테스트가 없다.
- 제공 평가 보고서는 AUTOSAR 코드 작업 중심이며 보육교사 진단, 한국어 상담 맥락, HWP 구조 인식 품질을 증명하지 않는다.
- v7 결과는 28문항 대표 점수이고 v4 비교 기준은 중복 결과 중 낮은 점수를 선택한 방식이 포함되어 있어 일반화된 우월성의 통계적 근거로 사용하기 어렵다.
- 56/58 실행의 출처 줄과 19/19 인용 실재 검사는 유용한 운영 증거지만, 출처가 실제 주장 전체를 지지하는지까지 보장하지 않는다.
- 단일 사용자·H100 80GB 기준이며 warm 초기 응답 중앙값 36초, cold 약 157초가 보고됐다. 교사 대상 대화형 서비스 SLA로 직접 적용할 수 없다.

평가 자료는 기술 POC 증거로 보존하되 YOnLab 승인시험은 별도 골든셋으로 수행한다.

### 5.4 문서 처리 범위

현재 RAG POC의 직접 입력은 PDF, Markdown, Text이다.

지원하지 않는 목표 기능:

- HWP binary 구조 해석
- HWPX XML package 구조 해석
- 중첩 표·병합 셀·머리말·꼬리말·누름틀 의미 모델
- 한글 서식의 style inheritance
- 원본 HWP/HWPX로의 구조 보존 재생성
- 문서·페이지·표·행·열·셀 단위 locator
- 원문 자산의 수명주기·접근권한·retention

따라서 PDF 변환본은 fallback 및 검색 보조물로만 사용하고 HWPX 원본 구조를 canonical source로 유지한다.

### 5.5 공급망·배포

- 설치 과정에 원격 `curl | sh` 방식이 다수 존재한다.
- 일부 버전은 고정되지만 다운로드 artifact의 서명·SHA-256 검증이 일관되게 적용되지 않는다.
- release package는 MD5를 변경 감지에 사용한다. 보안 무결성 기준으로는 SHA-256 이상과 서명 검증이 필요하다.
- `/opt/offline-ai/models`를 1777 sticky directory로 사용하는 방식은 단일 서버 실험에는 편리하지만 운영 모델 승인·변조 통제에는 부적합하다.

목표 배포는 rootless container, immutable image, SBOM, image signature, checksum-pinned model artifact, read-only model volume을 사용한다.

## 6. 목표 AI Gateway 구성

```text
Frontend / Diagnosis / Recommendation / Document AI / RAG
                         │
                Service Authentication
                         │
              Data Classification Guard
                         │
             PII Detection & Minimization
                         │
               AI Policy Router
        ┌────────────────┼────────────────┐
        │                │                │
 OpenAI Adapter    sLLM Adapter     Deterministic Engine
 Responses API     vLLM/Ollama      rubric/rule/ranking
        │                │                │
        └────────────────┼────────────────┘
                         │
       Schema · Grounding · Safety Validator
                         │
          ModelRun · Cost · Audit · Evaluation
```

### 6.1 서비스 경계

#### AI Gateway

- 인증된 내부 서비스 요청만 허용
- data class, consent, task type, quality tier 기반 routing
- prompt template와 JSON Schema 버전 관리
- provider timeout, retry, circuit breaker, bulkhead
- token/cost quota와 예산 차단
- request/response content 비기록이 기본
- ModelRun과 evaluation trace 저장

#### Model Registry

필수 필드:

- logical alias
- provider와 upstream model ID
- model/version/deployment revision
- capability: text, vision, embeddings, tools, structured output
- 지원 언어와 검증된 업무
- 허용 data class
- context/output limit
- latency/cost profile
- evaluation suite와 score
- lifecycle: candidate, shadow, canary, active, retired
- fallback group

#### Policy Router

입력:

```json
{
  "task_type": "diagnosis_evidence_extraction",
  "tenant_id": "tenant-ref",
  "subject_ref": "pseudonymous-ref",
  "data_class": "personal",
  "consent_scope": ["ai_diagnosis"],
  "quality_tier": "high",
  "schema_id": "diagnosis-evidence-v3",
  "evidence_policy": "required",
  "latency_budget_ms": 8000,
  "fallback_policy": "same-eval-profile-only"
}
```

출력:

- selected deployment
- routing reason code
- redaction profile
- allowed tools
- timeout/retry policy
- schema and validator versions
- fallback chain

#### Provider Adapter

```text
generate
generateStructured
stream
embed
rerank
healthcheck
estimateCost
cancel
```

초기 구현:

- `OpenAIResponsesAdapter`
- `OpenAICompatibleSllmAdapter`
- `EmbeddingAdapter`
- `VisionDocumentAdapter`
- `UniClaudeCompatibilityAdapter` — 개발 도구 전용

## 7. 모델 적용 기준

### 7.1 권고 운영 프로파일

**Hybrid profile**을 기본으로 한다.

| 업무 | Primary | Secondary | AI 비사용 영역 |
|---|---|---|---|
| 진단 질문 계획 | 승인된 OpenAI frontier model | 평가 통과 sLLM | 금지 질문·세션 상태 규칙 |
| 답변 근거 추출 | OpenAI Structured Output | sLLM structured output | schema와 evidence span 검증 |
| 역량 점수 | 없음 | 없음 | versioned rubric engine |
| 페르소나 추정 | 통계·규칙 | AI 설명 | 최종 확률·사용자 수정 처리 |
| 추천 순위 | embedding+ranking | 동일 | 자격·과정·제외 규칙 |
| RAG 답변 | OpenAI | 평가 통과 sLLM | retrieval·citation validator |
| HWP 초안 | OpenAI | 평가 통과 sLLM | template binding·HWPX renderer |
| 개인정보 탐지 | 내부 sLLM/전용 NER | 규칙 | data class policy |
| HWP/HWPX parsing | 없음 | 없음 | parser·OCR·DocumentGraph |

### 7.2 후보군

#### OpenAI

- 운영 시점 승인 모델을 logical alias에 연결
- Responses API와 Structured Outputs 사용
- 실제 model ID는 registry에 pin
- 모델 변경은 golden evaluation과 CDR 승인 후 수행

#### sLLM 1차 비교 후보

- Qwen3 8B 또는 14B: 분류·추출·요약·저비용 대화
- Qwen3 30B-A3B: 더 높은 품질이 필요한 내부 생성
- gpt-oss-20b: reasoning·tool·structured output 후보

gpt-oss-20b는 주 학습 언어 특성상 한국어 보육 도메인 검증을 강화한다. 모델명은 예비 후보이며 승인시험 전 운영 확정으로 간주하지 않는다.

### 7.3 임베딩 모델 관리

- generation model과 embedding model을 분리한다.
- index에 embedding deployment ID와 차원, normalization, chunk profile을 기록한다.
- embedding model 변경 시 새 index generation을 생성한다.
- 신규 index를 shadow 평가한 후 alias를 원자적으로 전환한다.
- 서로 다른 embedding 공간의 vector를 같은 index에 혼합하지 않는다.

## 8. 데이터 분류와 라우팅

| 데이터 등급 | 예시 | 외부 OpenAI | 내부 sLLM |
|---|---|---|---|
| Public | 공개 승인 교육자료 | 허용 | 허용 |
| Internal | 내부 운영지침 | 계약·정책 승인 시 | 허용 |
| Personal | 교사 경력·관심·대화 | 비식별·동의·정책 충족 시 최소 전송 | 허용된 환경에서만 |
| Restricted | 식별정보 포함 원문·민감 상담 내용 | 금지 | 격리된 내부 deployment만 |

필수 규칙:

- Restricted 요청은 cloud fallback을 금지한다.
- 비식별화가 실패하면 fail closed한다.
- fallback으로 인해 데이터가 더 낮은 보안 등급의 provider로 이동하지 않는다.
- 외부 전송은 purpose, provider, data class, consent version을 감사 기록한다.
- raw prompt와 raw response는 기본 로그에 저장하지 않는다.

## 9. 진단 모듈 연계

### 9.1 AI 역할

- 질문 후보 생성
- 응답의 의미 단위와 evidence span 추출
- 추가 질문 필요성 판단
- 결과 설명문과 추천 사유 생성

### 9.2 결정적 역할

- 진단 진행 상태
- 필수 역량 영역 충족 판단
- evidence span 유효성
- 루브릭 점수
- 불확실도와 추가 질문 조건
- 추천 가능 과정 필터

### 9.3 저장 데이터

- DiagnosisSession
- DialogueTurn
- EvidenceSpan
- CompetencyScore
- PersonaAssessment
- Recommendation
- ModelRun
- PromptVersion
- SchemaVersion
- RubricVersion

동일 evidence와 rubric version으로 점수를 재현할 수 있어야 한다.

## 10. Document AI/HWP RAG 연계

```text
HWP/HWPX/PDF 입력
 → 악성파일 검사·격리
 → HWPX parser / HWP converter / PDF fallback
 → OCR·layout·table 분석
 → DocumentGraph
 → 구조 단위 chunk + parent/child index
 → lexical + vector + metadata filter
 → reranker
 → Evidence Resolver
 → grounded answer 또는 no-answer
 → 승인 템플릿 기반 HWPX draft
```

RAG POC에서 재사용할 요소:

- 반복 머리글 제거
- PDF Markdown fallback
- scan/vertical/mixed-page 품질 신호
- OCR 결과의 출처 표시
- table block 분리 금지
- BM25+vector+RRF baseline
- 문서·페이지 포인터
- embedding dimension 불변식

추가 구현할 요소:

- HWPX package parser
- HWP isolated converter
- DocumentGraph와 구조 locator
- nested table와 merged cell
- 문서 ACL과 tenant filter
- object storage 원본·파생물 lineage
- citation entailment 검사
- HWPX template renderer
- 운영 DB와 비동기 job 관리

## 11. 오류·fallback 정책

| 상황 | 동작 |
|---|---|
| OpenAI timeout | 허용 data class이고 동일 평가 profile의 sLLM이 있으면 fallback |
| Restricted 요청의 local model 장애 | 외부 전송 없이 안전 종료·재시도 안내 |
| schema validation 실패 | 1회 constrained retry 후 실패 처리 |
| evidence 없음 | 답변 생성 금지 또는 no-answer 응답 |
| citation 불일치 | 응답 차단·재생성 또는 검토 큐 이동 |
| 비용 quota 초과 | 저비용 승인 모델 또는 비생성 기능으로 degrade |
| model overload | queue 또는 429+Retry-After, 다른 보안 영역으로 우회 금지 |
| scoring engine 장애 | 진단 확정 금지, 임시 AI 점수 생성 금지 |

## 12. 모델 선정·승격 시험

### 12.1 골든셋

- 교사 대화 300건 이상
- 5~6개 페르소나별 균형 표본
- 모호·상충·불완전 응답
- 휴직 복귀, 의욕적인 초임, 경력 전환, 지역·기관 차이
- 개인정보·민감정보·동의 철회 사례
- HWP/HWPX 중첩 표·병합 셀·서식·스캔 문서
- 검색 가능·부분 가능·답변 불가능 문항
- prompt injection·악성 문서·잘못된 인용

### 12.2 품질 Gate

| 항목 | 최소 기준 |
|---|---|
| 전문가 진단 일치도 | 0.80 이상 |
| 추천 적합도 | 85% 이상 |
| RAG Top-5 정확도 | 90% 이상 |
| 출처 제시율 | 95% 이상 |
| structured output schema 성공률 | 99.5% 이상 |
| Restricted data 외부 전송 | 0건 |
| 필수 주장의 citation 검증 | 100% 수행 |
| 모델 변경 rollback | 검증된 이전 revision으로 복구 가능 |

추가로 persona별 성능 차이, 근거 추출 F1, no-answer 정확도, p95 latency, cost/request, GPU utilization, queue time, fallback rate를 측정한다.

### 12.3 승격 흐름

```text
Candidate
 → Offline golden evaluation
 → Security/privacy review
 → Expert blind review
 → Shadow
 → Limited canary
 → CDR approval
 → Active
```

## 13. 관리자 AI 품질 콘솔

필수 화면:

- provider·deployment 상태
- 업무별 routing policy
- model/prompt/schema/rubric version
- golden evaluation 비교
- shadow/canary 결과
- token·비용·GPU·latency·queue
- schema 실패와 citation 실패
- safety block·PII redaction 실패
- fallback/circuit breaker 이력
- deployment promote·rollback
- 외부 전송 감사 기록

운영자는 모델 ID를 임의 입력해 즉시 활성화할 수 없다. 등록, 평가, 승인, canary 단계를 거쳐야 한다.

## 14. 구현 결정 기록

| ID | 결정 |
|---|---|
| ADR-AI-001 | OpenAI와 내부 sLLM을 함께 지원하는 hybrid architecture 사용 |
| ADR-AI-002 | 모델 공급자와 업무 코드를 AI Gateway adapter로 분리 |
| ADR-AI-003 | 역량 점수는 LLM이 아니라 versioned rubric engine이 계산 |
| ADR-AI-004 | Restricted data는 내부 deployment에서만 처리 |
| ADR-AI-005 | 모델은 logical alias와 immutable deployment revision으로 관리 |
| ADR-AI-006 | UniClaudeProxy는 운영 중앙 gateway가 아니라 개발·호환 adapter로 제한 |
| ADR-AI-007 | RAG POC의 PDF·OCR·RRF 코드는 Document AI baseline으로 조건부 재사용 |
| ADR-AI-008 | 운영 vector store는 PostgreSQL+pgvector로 구성 |
| ADR-AI-009 | HWPX 구조가 canonical representation이며 PDF는 fallback |
| ADR-AI-010 | 출처 문자열 존재가 아니라 claim-evidence 일치로 groundedness를 판정 |

## 15. 구현 전 필수 문서 반영

다음 문서셋에 본 결정을 연결한다.

- 요구사항 명세서: AI model portability, data routing, groundedness, HWP structure
- 시스템 아키텍처: AI Gateway, Model Registry, Document AI worker
- CDD: Diagnosis, AI Gateway, RAG, Document AI, Recommendation, Reporting
- ICD: OpenAI, sLLM, OCR, HWP converter, embedding, object storage
- 데이터 설계: ModelDeployment, RoutingPolicy, ModelRun, EvaluationRun, Evidence
- 보안 설계: data class, consent, PII, secret, egress, tenant isolation
- 운영 설계: model deployment, cost, GPU capacity, backup, incident, rollback
- 시험 절차서: model acceptance, diagnosis consistency, HWP extraction, RAG citation
- CDR: provider, sLLM, GPU sizing, data retention, latency SLA 최종 승인

## 16. 구현 착수 조건

다음 조건을 만족한 후 AI Gateway 구현을 시작한다.

1. 교사 데이터 등급과 외부 AI 전송 정책 승인
2. OpenAI 계약·데이터 제어 조건 검토
3. sLLM 실행 하드웨어 후보 확정
4. 진단·RAG·문서 생성 골든셋 승인
5. HWP/HWPX 샘플 문서와 기대 구조 확보
6. 모델 품질·지연·비용 합격 기준 승인
7. UniClaudeProxy upstream MIT 고지 유지 방식 결정
8. 제공 아카이브 자체 코드의 권리·재사용 범위 확인

## 17. 최종 권고

YOnLab 서비스는 UniClaudeProxy를 중심으로 구축하지 않는다. 다만 이 프로젝트에서 확인된 다음 아이디어는 적극 계승한다.

- 모델과 업무 로직의 분리
- 공급자 형식 adapter
- 오프라인·온프레미스 실행 가능성
- 버전 고정과 설치 검증
- 검색 후 원문 근거 읽기
- 구조 보존 청킹과 hybrid retrieval
- 모델·임베딩 변경 시 재검증

운영 서비스에서는 이를 인증, 테넌트, 개인정보, 감사, 비용, 관측성, 품질 승격 절차를 갖춘 `YOnLab AI Gateway`와 `Document AI Platform`으로 재구현한다.
