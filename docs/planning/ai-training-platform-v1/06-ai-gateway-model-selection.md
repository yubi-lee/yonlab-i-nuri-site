# 06. AI Gateway·모델 선정 설계

문서 ID: AI-GW-006  
모델 정책 기준일: 2026-07-13

## 1. 목표

AI Gateway는 업무 코드와 모델 공급자를 분리하고, task·데이터등급·품질·비용·지연·가용성에 따라 OpenAI 또는 내부 sLLM을 선택한다. 모든 호출은 입력 최소화, schema 검증, 감사, 평가, fallback 정책을 거친다.

## 2. Canonical 계약

```json
{
  "task": "diagnosis.evidence.extract",
  "tenant_id": "uuid",
  "data_class": "INTERNAL",
  "messages": [{"role":"user","content":"..."}],
  "response_schema_id": "evidence.v1",
  "policy_version": "route.v1",
  "latency_budget_ms": 5000,
  "idempotency_key": "uuid",
  "trace_id": "uuid"
}
```

응답은 `output`, `provider`, `deployment`, `model_version`, `prompt_version`, `schema_version`, `usage`, `latency`, `safety`, `fallback_count`, `trace_id`를 가진다. 공급자 원본 응답은 boundary 내부에서 canonical form으로 변환한다.

## 3. 데이터 등급별 라우팅

| 등급 | 예시 | 외부 OpenAI | 내부 sLLM |
|---|---|---|---|
| PUBLIC | 공개 교육자료 | 허용 | 허용 |
| INTERNAL | 가명화 진단 evidence, 내부 메타 | 계약·정책과 최소화 후 허용 | 우선 허용 |
| PERSONAL | 식별 가능 프로필·자유서술 | 비식별·승인된 field만 | 격리 endpoint에서 허용 |
| RESTRICTED | 민감 원문, 보안자료, raw 감사 | 금지 | 승인된 내부 model만 |

DataPolicyEngine은 outbound field allowlist를 적용한다. log에는 원문 대신 hash, 길이, class, redaction count를 기록한다.

## 4. Task별 기본 정책

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

### 5.1 OpenAI

OpenAI Responses API를 기본 adapter로 사용하고 Structured Outputs로 schema를 강제한다. 모델 alias를 코드에 직접 쓰지 않고 ModelDeployment registry에서 정확한 model snapshot, region/policy, 허용 data class를 관리한다. 공급자 data retention·training 설정은 계약과 최신 공식 정책을 확인해 운영 승인한다.

### 5.2 sLLM

한국어 대화·구조화 출력 후보군은 Qwen3 계열과 OpenAI gpt-oss 계열을 포함해 동일 평가셋으로 비교한다. vLLM 또는 호환 serving endpoint는 production AI Gateway 뒤에 두며 tokenizer, quantization, context, GPU, serving image digest를 deployment version에 기록한다.

### 5.3 점수표

| 항목 | 가중치 | Hard gate |
|---|---:|---|
| 업무 정확도 | 25 | 진단 일치·RAG 기준 통과 |
| 한국어 맥락 | 15 | 존댓말·교육용어 오류 한도 |
| 구조화 출력 | 15 | 성공률 ≥99.5% |
| groundedness | 15 | 잘못된 citation 한도 0 |
| 안전·편향 | 10 | 금지 판단 위반 0 |
| latency/throughput | 8 | task p95 예산 충족 |
| 비용/TCO | 7 | 승인 월 예산 이내 |
| 운영·license | 5 | 상업 이용·보안·지원 승인 |

Hard gate를 하나라도 실패한 모델은 가중합 점수와 무관하게 배포하지 않는다. 선정 결과는 EvaluationRun과 CDR로 보존한다.

## 6. Prompt·Schema·Model registry

- PromptVersion: system/developer template, variable schema, owner, hash, approval
- SchemaVersion: JSON Schema, backward compatibility, validator package
- ModelDeployment: provider, exact model, endpoint, capability, data class, status
- RoutingPolicy: task, rule priority, primary/fallback, quota, effective time
- EvaluationSuite: dataset version, metrics, thresholds, protected slices

`prompt+schema+model+routing+dataset` 조합을 release manifest로 묶는다. production 변경은 offline regression과 stage shadow/canary를 통과해야 한다.

## 7. 실행 통제

1. 입력 크기·content type·data class 검증
2. 개인정보·secret 탐지와 field allowlist redaction
3. prompt injection·위험 의도 분류
4. tenant quota·rate limit·cost budget 확인
5. route 결정과 circuit 상태 확인
6. provider 호출, timeout, cancellation
7. schema·citation·policy 검증
8. 최대 1회 repair 또는 승인 fallback
9. 결과·version·usage·안전 flag 감사

Retry는 429·일시 5xx·network timeout에 한해 최대 2회 적용한다. 비결정적 생성 요청을 무조건 재시도하지 않고 idempotency와 중복 side effect를 통제한다.

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

## 11. 공식 기술 기준

구현 시 다음 공식 문서의 최신 계약을 확인한다.

- [OpenAI 최신 모델 가이드](https://developers.openai.com/api/docs/guides/latest-model)
- [Responses API 이전 가이드](https://developers.openai.com/api/docs/guides/migrate-to-responses)
- [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- [OpenAI 데이터 제어](https://developers.openai.com/api/docs/guides/your-data)
- [OpenAI gpt-oss](https://openai.com/index/introducing-gpt-oss/)
- [Qwen3 공식 저장소](https://github.com/QwenLM/Qwen3)

