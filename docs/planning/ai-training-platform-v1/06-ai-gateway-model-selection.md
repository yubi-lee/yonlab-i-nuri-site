# 06. AI Gateway·모델 선정 설계

문서 ID: AI-GW-006  
모델 정책 기준일: 2026-07-13

경로, 데이터 기본등급, 정량 gate와 판정 상태의 normative source는 [design-baseline.json](design-baseline.json)이다. Gateway 경계, `DataUseContext`, 동기 승인과 policy ID의 구현 계약은 [규범 정책·인터페이스 계약](15-normative-policy-and-interface-contracts.md)이다. AI뿐 아니라 저장소·메일·OIDC·broker·malware·hosting/DNS/TLS/WAF·DB·Redis·off-host backup·CI/CD까지의 선택 상태는 [provider-decision-registry.json](provider-decision-registry.json), 평가 통계 기준은 [evaluation-policy-contract.json](evaluation-policy-contract.json)을 따른다.

## 1. 목표

AI Gateway는 `services/ai-gateway/`에서 독립 build/test/deploy되는 API·worker와 별도 배포·workload identity·network/secret 경계의 내부 서비스다. backend에는 generated canonical client와 shared schema reference만 두고 provider SDK·routing·credential code를 둘 수 없다. caller는 SPIRE가 발급한 mTLS X.509-SVID와 canonical `/internal/ai/v1/{responses,embeddings,rerank}` API만 사용한다. 모든 호출은 입력 최소화, signed `DataUseContext`, synchronous authorization, safeguarding, schema 검증, 감사, 평가, fallback 정책을 거친다.

[ai-service-contracts.json](ai-service-contracts.json)은 세 canonical endpoint와 diagnosis·persona·recommendation·document·draft의 9개 task input/output JSON Schema를 closed object로 고정한다. unknown field는 거부하고 structured repair는 최대 1회이며 fallback도 새로운 `DataUseContext`와 current authorization 없이는 실행하지 않는다.

## 2. Canonical 계약

`POST /internal/ai/v1/responses`의 유일한 wire source는 [ai-gateway-request.schema.json](ai-gateway-request.schema.json)이다. schema fixture는 HTTP transport를 `{headers, body}` object로 표현한다. 실제 전송에서 `content_type`, `idempotency_key`, `x_request_id`, `traceparent`는 각각 `Content-Type`, `Idempotency-Key`, `X-Request-ID`, `traceparent` header이고 `workload_spiffe_id`는 mTLS peer certificate SAN URI다. 이 값들을 body에 복제하지 않는다.

```json
{
  "headers": {
    "content_type": "application/json",
    "idempotency_key": "00000000-0000-4000-8000-000000000011",
    "x_request_id": "00000000-0000-4000-8000-000000000012",
    "traceparent": "00-11111111111111111111111111111111-2222222222222222-01",
    "workload_spiffe_id": "spiffe://yonlab/test/application-api"
  },
  "body": {
    "task": "diagnosis.evidence.extract",
    "tenant_id": "00000000-0000-4000-8000-000000000001",
    "input": {
      "messages": [
        {
          "role": "user",
          "content": "비식별 합성 발화"
        }
      ]
    },
    "response_schema_id": "diagnosis-evidence.v1",
    "policy_versions": {
      "routing": "routing.v1",
      "prompt": "diagnosis-evidence-prompt.v1",
      "model_registry": "model-registry.v1",
      "schema_registry": "schema-registry.v1",
      "data_use": "data-use.v1",
      "consent_authorization": "consent-authz.v1",
      "tenant_isolation": "tenant-isolation.v1",
      "safeguarding_routing": "safeguarding-routing.v1"
    },
    "latency_budget_ms": 8000,
    "data_use_context": {
      "payload": {
        "schema": "DataUseContext.v1",
        "context_id": "00000000-0000-4000-8000-000000000013",
        "tenant_id": "00000000-0000-4000-8000-000000000001",
        "subject_pseudonym": "teacher-pseudonym-001",
        "purpose": "diagnosis_support",
        "task": "diagnosis.evidence.extract",
        "data_class": "INTERNAL",
        "field_categories": [
          "diagnosis_narrative.redacted"
        ],
        "allowed_destination": "INTERNAL_SLLM",
        "consent_basis": "CONSENT",
        "consent_epoch": 17,
        "acl_version": 42,
        "safeguarding_decision": "STANDARD",
        "policy_versions": {
          "DataUsePolicyVersion": "data-use.v1",
          "ConsentAuthorizationPolicyVersion": "consent-authz.v1",
          "TenantIsolationPolicyVersion": "tenant-isolation.v1",
          "SafeguardingRoutingPolicyVersion": "safeguarding-routing.v1"
        },
        "payload_sha256": "69eed1935aee197595dd0800c986cfa8dd02fb25c9413dbfb76a8de83008ada6",
        "issuer": "spiffe://yonlab/test/identity-consent",
        "audience": "spiffe://yonlab/test/ai-gateway",
        "issued_at": "2026-07-13T00:00:00Z",
        "expires_at": "2026-07-13T00:01:00Z",
        "trace_id": "00000000-0000-4000-8000-000000000014"
      },
      "signature": "YWJj..ZGVm",
      "canonicalization": "JCS"
    }
  }
}
```

body의 exact required field는 `task`, `tenant_id`, `input`, `response_schema_id`, `policy_versions`, `latency_budget_ms`, `data_use_context` 일곱 개다. `policy_versions`는 `routing`, `prompt`, `model_registry`, `schema_registry`, `data_use`, `consent_authorization`, `tenant_isolation`, `safeguarding_routing` 여덟 key를 정확히 요구한다. singular `policy_version`, body의 `idempotency_key`/`trace_id`, `data_class`, provider/model/credential field와 모든 unknown field는 `additionalProperties=false`로 거부한다.

wire field 이름은 정확히 `data_use_context`이고 값은 `{payload, signature, canonicalization}` object다. `payload`는 `DataUseContext.v1`, `signature`는 compact detached JWS `protected..signature`, `canonicalization`은 literal `JCS`다. body `task`/`tenant_id`는 signed payload와 byte-for-byte 같아야 하고 `payload_sha256`은 exact `input` JCS bytes를 결속한다. repair/fallback도 새 context와 새 authorization을 요구한다.

응답은 `run_id`, `output`, `provider`, `deployment`, `model_version`, `prompt_version`, `schema_version`, `routing_version`, `usage`, `latency`, `safety`, `fallback_count`, `trace_id`를 가진다. 공급자 원본 응답은 boundary 내부에서 canonical form으로 변환한다. 동기 authorization 응답의 current `consent_epoch`와 current `acl_version`이 context 값과 각각 정확히 같고, current rights·purpose·task·destination이 모두 `ALLOW`이며, authorized payload hash가 context와 request에서 다시 계산한 hash에 정확히 같을 때만 route를 결정한다. authorization 장애·stale consent·stale ACL·unknown policy·hash 불일치는 provider 호출 전에 fail closed 하며 과거 ALLOW cache를 사용하지 않는다.

## 3. 데이터 등급별 라우팅

| 등급 | 예시 | 외부 OpenAI | 내부 sLLM |
|---|---|---|---|
| PUBLIC | 공개 교육자료 | 허용 | 허용 |
| INTERNAL | 가명화 진단 evidence, 내부 메타 | 계약·정책과 최소화 후 허용 | 우선 허용 |
| CONFIDENTIAL | 식별 가능 프로필·자유서술 | 비식별·승인된 field만 | 격리 endpoint에서 허용 |
| RESTRICTED | 민감 원문, 보안자료, raw 감사 | 금지 | 승인된 내부 model만 |

DataPolicyEngine은 outbound field allowlist를 적용한다. log에는 원문 대신 hash, 길이, class, redaction count를 기록한다.

등급을 확정하지 못한 교사 자유서술·narrative와 raw/scanned upload는 `RESTRICTED`로 처리한다. 명시적 분류와 정책 authorization이 모두 성공하기 전 external AI egress는 `DENY`다. safeguarding vocabulary는 정확히 `STANDARD`, `CHILD_SAFEGUARDING`, `IMMINENT_DANGER`, `SECURITY_EXFILTRATION`, `POLICY_BLOCK` 다섯 상태다. `STANDARD`만 일반 model route 정책 평가로 진행한다. 나머지 상태와 classifier timeout·unknown은 일반 model route를 중단하며 unknown은 `POLICY_BLOCK`으로 fail closed한 뒤 [승인 경로](15-normative-policy-and-interface-contracts.md#33-미분류-데이터와-safeguarding)로 보낸다.

## 4. Task별 기본 정책

구조화 출력 task와 provider/fallback별 시험 분모·repair budget·표본·threshold는 [KPI-005 matrix](kpi-005-structured-output-matrix.json)가 유일한 machine-readable 계약이다. enabled route 한 cell도 생략할 수 없고 deterministic/no-answer fallback은 별도 semantic validator를 통과하되 모델 구조화 성공률 분모를 부풀리지 않는다.

| Task | 기본 route | 출력 | fallback |
|---|---|---|---|
| 진단 evidence 추출 | 내부 sLLM 또는 고정밀 OpenAI | strict JSON schema | 다른 승인 model → 정형질문 |
| 다음 질문 표현 | sLLM | text+policy flags | template 질문 |
| 페르소나 설명 | sLLM | structured explanation | 결정적 template |
| 추천 설명 | sLLM | fact-bound text | feature template |
| 문서 query rewrite | sLLM | query list | 원 질의 |
| RAG rerank | 전용 reranker/sLLM | relevance scores | RRF 결과 |
| grounded answer | OpenAI 고정밀 또는 검증 sLLM | claims+citation schema | 대체 model → no-answer |
| HWPX section draft | OpenAI 고정밀 | template field schema | 검증 sLLM → 사람이 작성 |
| 요약·태깅 | batch sLLM | metadata schema | queue 재시도 |

## 5. 모델 후보와 선정

사업자명·모델명만으로 production route를 확정하지 않는다. [provider-decision-registry.json](provider-decision-registry.json)은 OpenAI, sLLM, 한국어 OCR/표 구조, embedding/reranker, GPU·converter hardware와 HWP binary의 owner, 기한, 필수 입력, gate를 고정한다. `RESTRICTED`는 `INTERNAL_SLLM` 또는 `DETERMINISTIC`만 허용하며 decision input과 fresh gate가 모두 PASS인 immutable deployment revision만 활성화한다.

registry의 16개 decision은 각각 owner, due, required input, gate뿐 아니라 DPA 적용 상태, 승인 region, exit plan, evidence freshness 90일, release state를 요구한다. 승인 region은 evidence 전 빈 배열이고 모든 row와 registry 전체는 `NOT_READY`다. 하나의 provider를 선택해도 object storage, email, OIDC, broker, malware, hosting/DNS/TLS/WAF, managed PostgreSQL, Redis, off-host backup, CI/CD decision이 미결이면 production release는 계속 `NOT_READY`다.

### 5.1 OpenAI

OpenAI Responses API를 기본 adapter로 사용하고 Structured Outputs로 schema를 강제한다. 모델 alias를 코드에 직접 쓰지 않고 ModelDeployment registry에서 정확한 model snapshot, region/policy, 허용 data class를 관리한다. 공급자 data retention·training 설정은 계약과 최신 공식 정책을 확인해 운영 승인한다.

### 5.2 sLLM

한국어 대화·구조화 출력 후보군은 Qwen3 계열과 OpenAI gpt-oss 계열을 포함해 동일 평가셋으로 비교한다. vLLM 또는 호환 serving endpoint는 production AI Gateway 뒤에 두며 tokenizer, quantization, context, GPU, serving image digest를 deployment version에 기록한다.

### 5.3 점수표

| 항목 | 가중치 | Hard gate |
|---|---:|---|
| 업무 정확도 | 25 | 진단 일치·RAG 기준 통과 |
| 한국어 맥락 | 15 | 존댓말·교육용어 오류 한도 |
| 구조화 출력 | 15 | 성공률 ≥99.8% |
| groundedness | 15 | 잘못된 citation 한도 0 |
| 안전·편향 | 10 | 금지 판단 위반 0 |
| latency/throughput | 8 | task p95 예산 충족 |
| 비용/TCO | 7 | 승인 월 예산 이내 |
| 운영·license | 5 | 상업 이용·보안·지원 승인 |

Hard gate를 하나라도 실패한 모델은 가중합 점수와 무관하게 배포하지 않는다. 선정 결과는 EvaluationRun과 CDR로 보존한다. Gate 결과는 `PASS`, `FAIL`, `BLOCKED`, `REQUIRES_ACCEPTANCE_DATA` 중 하나이며 `FAIL`, `BLOCKED`, 누락 또는 stale 증거는 release를 차단한다.

## 6. Prompt·Schema·Model registry

- PromptVersion: system/developer template, variable schema, owner, hash, approval
- SchemaVersion: JSON Schema, backward compatibility, validator package
- ModelDeployment: provider, exact model, endpoint, capability, data class, status
- RoutingPolicy: task, rule priority, primary/fallback, quota, effective time
- EvaluationSuite: dataset version, metrics, thresholds, protected slices

`prompt+schema+model+routing+dataset` 조합을 release manifest로 묶는다. production 변경은 offline regression과 stage shadow/canary를 통과해야 한다.

API 결과는 정확한 `ScoringPolicyVersion=diagnosis-scoring.v1`, `PersonaInferencePolicyVersion=persona-inference.v1`, `RecommendationPolicyVersion=recommendation-ranking.v1`, `DocumentGraphSchemaVersion=document-graph.v1`을 해당 artifact hash와 함께 기록한다. alias 내용 덮어쓰기나 unknown version 수용은 금지한다.

## 7. 실행 통제

Gateway는 body를 처리하기 전에 mTLS workload identity와 caller/task 허용관계를 확인한다. 그 뒤 다음 순서를 고정한다.

1. strict JSON parse, duplicate key/unknown envelope property 거부와 exact `data_use_context` shape 확인
2. protected header와 compact detached JWS 두 점 형식 확인
3. payload의 UTF-8 JCS bytes 재생성과 detached JWS signature 검증
4. payload schema, issuer/audience/TTL과 policy version 검증
5. request tenant/task/trace binding과 recomputed input payload hash equality 검증
6. single-use context replay 원자적 거부
7. current `consent_epoch`·current `acl_version` equality, current rights·purpose·task·destination `ALLOW`, authorized payload hash equality 동기 승인
8. 입력 크기·content type·data class와 tenant 검증
9. 개인정보·secret·field allowlist와 safeguarding 검사; input을 변형해야 하면 새 context를 발급
10. prompt injection·위험 의도와 tool allowlist 검사
11. tenant quota·rate limit·cost budget 확인
12. 동기 승인된 `allowed_destination` 안에서 route와 circuit 상태 결정
13. provider 호출, timeout, cancellation
14. schema·citation·current source rights·policy 검증
15. 새 DataUseContext로 최대 1회 repair 또는 승인 fallback
16. 결과·version·usage·안전 flag 감사

Retry는 429·일시 5xx·network timeout에 한해 최대 2회 적용한다. 비결정적 생성 요청을 무조건 재시도하지 않고 idempotency와 중복 side effect를 통제한다.

Gateway process는 SPIRE Agent workload API에서 private key가 export되지 않는 최대 60분 X.509-SVID를 받고 TTL 절반 전에 rotate한다. trust bundle version/hash와 caller SPIFFE ID×task allowlist를 registry에 고정한다. production은 3개 failure-domain의 SPIRE Server와 HA datastore를 사용하며 entry revoke·host 격리·provider key rotation은 certificate/secret runbook으로 검증한다. local/test는 별도 ephemeral trust domain의 deterministic Gateway stub만 사용하고 production CA/provider credential/external egress를 가질 수 없다.

## 8. Fallback·degraded mode

| 장애 | 동작 |
|---|---|
| OpenAI unavailable | 허용 data는 평가 통과 sLLM, 아니면 정형/기존 결과 |
| sLLM GPU queue 포화 | OpenAI 허용 data만 외부 route, Restricted는 queue/정형 |
| schema 반복 실패 | 결과 폐기, template fallback, 품질 event |
| citation 검증 실패 | claim 제거, 재검색 1회, no-answer |
| 전체 AI 장애 | 로그인·콘텐츠·기존 리포트 제공, 새 진단은 안전 중단·재개 |
| 비용 budget 초과 | 비필수 batch 중지, task별 cheaper approved route |

사용자에게는 공급자 내부 오류 대신 기능 상태, 보존된 입력, 재개 방법, 추적 ID를 제공한다.

## 9. UniClaude 호환 adapter 적용 범위

검토한 UniClaudeProxy의 멀티 provider 변환·RAG 분리 개념은 adapter 설계에 참고한다. 해당 proxy 자체는 inbound 인증, tenant quota, secret 관리, 감사·관측, test gate가 production 기준에 미달하므로 서비스 data plane으로 배치하지 않는다. 개발자가 로컬 Claude-compatible client를 검증할 때만 network 제한·dummy data·별도 key로 사용할 수 있다. 재사용 코드는 license notice, 보안 검토, 단위시험을 거쳐 신규 AI Gateway 경계 안으로 이식한다.

## 10. 운영지표

- task/provider/model별 request, success, fallback, timeout, schema failure
- TTFT와 total latency p50/p95/p99
- input/output token, GPU seconds, request cost, tenant budget
- queue depth, batch age, circuit state
- redaction count, Restricted egress denial, safety category
- evaluation regression, citation validity, human override rate

경보는 원문을 포함하지 않으며 trace ID로 승인된 시스템에서만 상세 조사한다.

### 10.1 공급자 평가 통계

모든 공급자 비교는 locked subject/query-disjoint holdout, 사전 고정된 최소 표본과 slice, 독립 adjudication, 95% confidence interval을 가진다. 같은 suite 안의 다중 metric·slice 유의성 주장은 Holm-Bonferroni family-wise alpha `0.05`를 적용한다. training/prompt example/near-duplicate/subject overlap 또는 retrieval index의 holdout label 유입은 허용량 0이며 발견 즉시 `FAIL`이다. 표본·slice·CI·adjudication 누락은 낮은 점수와 구분해 `INSUFFICIENT_DATA`로 판정하고 `PASS` override를 금지한다.

## 11. 공식 기술 기준

구현 시 다음 공식 문서의 최신 계약을 확인한다.

- [OpenAI 최신 모델 가이드](https://developers.openai.com/api/docs/guides/latest-model)
- [Responses API 이전 가이드](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [OpenAI 데이터 제어](https://developers.openai.com/api/docs/guides/your-data)
- [OpenAI gpt-oss](https://openai.com/index/introducing-gpt-oss/)
- [Qwen3 공식 저장소](https://github.com/QwenLM/Qwen3)
