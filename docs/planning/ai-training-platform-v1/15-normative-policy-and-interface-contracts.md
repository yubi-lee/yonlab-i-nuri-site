# 15. 규범 정책·인터페이스 계약

문서 ID: NORM-CONTRACT-015
계약 버전: 1.0.0
기준일: 2026-07-13

경로, KPI 계산식·한계값, 페르소나 계층, 복구 목표 승인 상태와 판정 상태의 최상위 normative source는 [design-baseline.json](design-baseline.json)이다. 이 문서는 [시스템 아키텍처](03-system-architecture-cdd-cdr.md), [AI Gateway](06-ai-gateway-model-selection.md), [데이터·API](07-data-api-interface-design.md), [보안·개인정보](08-security-privacy-operations.md)의 구현 계약을 구체화한다. 충돌 시 기준선의 값과 상태 어휘를 우선하고, 이 문서의 더 강한 보안·격리 조건을 완화해서 해석하지 않는다. 검증은 [시험 절차서](09-test-procedure-acceptance.md)의 보안·AI·문서·API 시험에 이 계약의 식별자와 부정 시험을 입력으로 사용한다.

RFC 2119 의미로 `MUST`, `MUST NOT`, `SHOULD`를 사용한다. 명시하지 않은 값, 분류, 권리 또는 정책 판정은 허용이 아니라 거부다.

## 1. 고정 정책 식별자와 버전 규칙

| 인터페이스 필드 | v1 고정값 | 적용 대상 |
|---|---|---|
| `DataUsePolicyVersion` | `data-use.v1` | 모든 AI 입력·출력·embedding 호출 |
| `ConsentAuthorizationPolicyVersion` | `consent-authz.v1` | 목적별 동의와 `consent_epoch` 판정 |
| `TenantIsolationPolicyVersion` | `tenant-isolation.v1` | tenant-scoped DB/object/cache/index/event |
| `SourceRightsPolicyVersion` | `current-source-rights.v1` | 검색 결과, citation, draft evidence |
| `SafeguardingRoutingPolicyVersion` | `safeguarding-routing.v1` | 자유서술·업로드·도구 호출의 안전 경로 |
| `ScoringPolicyVersion` | `diagnosis-scoring.v1` | 역량 점수와 다음 질문 입력 |
| `DiagnosisDecisionPolicyVersion` | `diagnosis-decision.v1` | level·confidence·conflict·coverage 판정 |
| `PersonaInferencePolicyVersion` | `persona-inference.v1` | 12개 profile 확률과 6개 family 집계 |
| `RecommendationPolicyVersion` | `recommendation-ranking.v1` | hard filter, 순위, 다양성 선택 |
| `DocumentGraphSchemaVersion` | `document-graph.v1` | 구조화 문서·chunk·citation locator |
| `LocatorPolicyVersion` | `source-locator.v1` | 문자·페이지·표·셀 위치 |
| `HwpConversionPolicyVersion` | `hwp-conversion.v1` | HWP→HWPX 변환과 검수 gate |

API와 event는 해당 결과를 만든 정책 식별자를 정확히 저장·반환해야 한다. 구현은 alias가 가리키는 immutable semantic version과 artifact SHA-256을 release manifest에 함께 고정한다. 같은 alias의 내용을 덮어쓰지 않으며 변경은 새 alias와 재평가로만 배포한다. 알 수 없는 식별자, 누락된 식별자 또는 요청·registry·artifact 사이의 hash 불일치는 `POLICY_VERSION_MISMATCH`로 fail closed 한다.

## 2. AI Gateway의 독립 서비스 경계

### 2.1 배치 불변조건

AI Gateway는 Application API·worker·모델 serving과 다른 배포 단위, process/container, workload identity, network policy, secret scope와 autoscaling policy를 갖는 별도 내부 서비스다. 동일 node에 배치할 수는 있으나 in-process library, sidecar 우회 또는 provider SDK 공유로 경계를 합칠 수 없다. provider credential과 외부 AI egress 권한은 AI Gateway identity에만 부여한다. Application API, worker, browser, parser와 관리자 도구의 provider 직접 호출은 network deny와 CI dependency 검사로 차단한다.

호출자는 mTLS로 접속하고 인증서의 workload identity를 `spiffe://yonlab/{environment}/{service}` 형식으로 제시한다. Gateway는 trust bundle, 인증서 유효기간·폐기상태, audience, 호출 service와 허용 `task` 조합을 검증한다. tenant나 사용자 bearer token만으로는 내부 Gateway에 접근할 수 없다. 인증 실패, trust bundle stale 또는 workload-task 미등록은 호출 전에 거부한다.

### 2.2 Canonical internal API

| Method·path | 용도 | 요청 schema | 응답 schema |
|---|---|---|---|
| `POST /internal/ai/v1/responses` | text·structured generation | `CanonicalAIRequest.v1` | `CanonicalAIResponse.v1` |
| `POST /internal/ai/v1/embeddings` | embedding batch | `CanonicalEmbeddingRequest.v1` | `CanonicalEmbeddingResponse.v1` |
| `POST /internal/ai/v1/rerank` | 승인 reranker | `CanonicalRerankRequest.v1` | `CanonicalRerankResponse.v1` |
| `GET /internal/ai/v1/health/ready` | registry·policy·provider readiness | 없음 | `GatewayReadiness.v1` |

모든 mutation은 `Content-Type: application/json`, UUID `Idempotency-Key`, UUID `X-Request-ID`, W3C `traceparent`와 mTLS에서 검증한 `workload_spiffe_id`를 요구한다. machine contract [ai-gateway-request.schema.json](ai-gateway-request.schema.json)은 fixture 표현의 top-level을 exact `headers,body`로 닫는다. request body는 exact `task,tenant_id,input,response_schema_id,policy_versions,latency_budget_ms,data_use_context`만 포함한다. `policy_versions`는 exact `routing,prompt,model_registry,schema_registry,data_use,consent_authorization,tenant_isolation,safeguarding_routing` 8개다. `input`은 nonempty object이고 아래 signed context의 `payload_sha256`이 `UTF-8(JCS(body.input))`에 결속된다. 공급자명·provider parameter·모델 alias·credential과 unknown field를 canonical body에 전달하지 않는다. 응답은 `run_id`, `output`, exact deployment/model/prompt/schema/routing version, usage, latency, safety, fallback count와 `trace_id`를 포함한다. 표준 오류는 `application/problem+json`이며 `DATA_USE_CONTEXT_INVALID`, `CONSENT_EPOCH_STALE`, `ACL_VERSION_STALE`, `AUTHZ_UNAVAILABLE`, `DATA_CLASS_DENIED`, `SAFEGUARDING_ROUTE_REQUIRED`, `POLICY_VERSION_MISMATCH`를 안정 code로 제공한다.

### 2.3 Workload PKI·SPIFFE 수명주기

production workload identity 구현은 환경별 trust domain `spiffe://yonlab/{environment}`를 갖는 SPIRE Server/Agent를 사용한다. production SPIRE Server는 서로 다른 failure domain의 3개 replica와 HA datastore를 사용하고, node attestation을 통과한 host에만 Agent를 등록한다. 등록 entry는 `application-api`, `document-worker`, `identity-consent`, `ai-gateway`, `hwp-converter-bridge` 서비스별 selector와 정확한 SPIFFE ID를 묶으며 wildcard service ID를 금지한다.

- X.509-SVID TTL은 최대 60분, workload는 TTL 절반 이전에 자동 rotate하고 private key를 disk에 export하지 않는다.
- trust bundle은 SPIRE bundle endpoint에서 mTLS로 배포하고 bundle version/hash를 telemetry와 release evidence에 기록한다. stale bundle이나 만료 SVID는 fail closed 한다.
- node/service 폐기, 침해 또는 역할 변경은 registration entry 삭제, workload drain, SVID 만료 대기 없이 workload/host 격리, provider key rotate 순서로 처리하고 `RB-016 certificate-renewal` 및 `RB-015 secret-rotation` 증거를 남긴다.
- Gateway authorization table은 caller SPIFFE ID×task allowlist를 version/hash로 고정한다. `application-api`와 `document-worker`만 승인 task를 호출하며 parser/browser/admin tool은 등록하지 않는다.
- local/test는 production trust와 분리된 ephemeral dev trust domain과 deterministic Gateway stub을 사용한다. dev CA·SVID·dummy provider key는 production에서 거부되고 stub은 실제 external egress와 production credential을 가질 수 없다.

## 3. `DataUseContext`와 동기 승인

### 3.1 서명 wire envelope와 검증 순서

모든 generation, embedding, rerank, evaluation sampling과 repair/fallback 호출은 다음 exact wire shape의 fail-closed signed context를 `data_use_context` field에 포함한다. `DataUseContext`는 payload type 이름이며 wire field 이름으로 사용하지 않는다. fallback과 repair는 원 호출의 승인을 상속한다고 가정하지 않고 매번 새 context로 재승인한다.

```json
{
  "data_use_context": {
    "payload": {
      "schema": "DataUseContext.v1",
      "context_id": "uuid",
      "tenant_id": "uuid",
      "subject_pseudonym": "opaque-or-null",
      "purpose": "diagnosis_support",
      "task": "diagnosis.evidence.extract",
      "data_class": "INTERNAL",
      "field_categories": ["diagnosis_narrative.redacted"],
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
      "payload_sha256": "64-lowercase-hex",
      "issuer": "spiffe://yonlab/production/identity-consent",
      "audience": "spiffe://yonlab/production/ai-gateway",
      "issued_at": "2026-07-13T00:00:00Z",
      "expires_at": "2026-07-13T00:01:00Z",
      "trace_id": "uuid"
    },
    "signature": "BASE64URL_PROTECTED..BASE64URL_SIGNATURE",
    "canonicalization": "JCS"
  },
  "input": {"messages": [{"role": "user", "content": "..."}]}
}
```

`payload`는 `DataUseContext.v1` object, `signature`는 compact detached JWS `BASE64URL(protected)..BASE64URL(signature)`, `canonicalization`은 다른 대소문자를 허용하지 않는 literal `JCS`다. JSON parser는 duplicate key와 non-I-JSON number를 거부하고 모든 context string은 NFC여야 한다. `payload_sha256`은 request의 exact `input` object를 `UTF-8(JCS(input))`로 직렬화한 bytes의 SHA-256 lowercase hex다. 원문·직접 식별자는 context에 넣지 않는다.

Identity & Consent service는 `payload_bytes=UTF-8(JCS(data_use_context.payload))`를 만든다. protected header는 `alg=EdDSA`, 등록 `kid`, `typ=yonlab-data-use-context+jws` 세 member만 가지며 `b64`, `crit`와 추가 member를 금지한다. detached JWS signing input은 `ASCII(BASE64URL(protected)) || 0x2e || ASCII(BASE64URL(payload_bytes))`다. 따라서 signature는 wire object를 다시 JCS로 만든 것이 아니라 `payload` object의 exact JCS bytes를 결속한다.

Gateway는 body를 처리하기 전에 mTLS workload identity와 caller/task allowlist를 검증한다. 그 뒤 검증 순서는 다음과 같으며 하나라도 실패하면 이후 단계와 provider 호출을 실행하지 않는다.

1. strict JSON parse, duplicate key·unknown envelope property 거부, field 이름 `data_use_context`, members `payload/signature/canonicalization`와 literal `JCS` 확인
2. protected header를 decode하고 compact detached 두 점 형식, `alg`, `kid`, `typ`, 금지 header를 검사
3. `payload_bytes`를 다시 만들고 등록 public key로 detached JWS signature를 검증
4. payload schema와 issuer, audience, 최대 60초 TTL, clock skew 최대 5초, 모든 policy version을 검증
5. request와 payload의 tenant, task, trace를 비교하고 `SHA-256(UTF-8(JCS(input)))`을 다시 계산해 `payload_sha256`과 비교
6. single-use `context_id` replay를 원자적으로 거부
7. 아래 동기 authorization을 호출해 current epoch, rights, 목적, task, destination과 payload hash를 비교
8. candidate route의 destination이 `allowed_destination`과 같고 동기 승인된 destination인지 확인하고 safeguarding·data-class route를 적용한 뒤에만 provider를 호출

### 3.2 `consent_epoch` 동기 승인

`consent_epoch`은 `(tenant_id, subject_id, purpose)`별 단조 증가 정수다. 동의 grant, 철회, 목적·범위·보유기간·제3자 제공 변경을 commit하는 같은 DB transaction에서 증가한다. 철회 transaction이 먼저 commit되고 purge event는 transactional outbox에 기록된다.

AI Gateway는 provider 선택 전에 매 호출마다 Identity & Consent authorization endpoint에 mTLS로 `context_id`, tenant, subject pseudonym, purpose, task, field categories, destination, `consent_epoch`, `acl_version`, payload hash를 보내 동기 재승인한다. authorization endpoint는 primary/current policy view에서 다음 값을 반환한다.

```json
{
  "context_id": "uuid",
  "decision": "ALLOW",
  "current_consent_epoch": 17,
  "current_acl_version": 42,
  "rights_decision": "ALLOW",
  "purpose_decision": "ALLOW",
  "task_decision": "ALLOW",
  "destination_decision": "ALLOW",
  "authorized_payload_sha256": "64-lowercase-hex",
  "authorization_policy_version": "consent-authz.v1",
  "decided_at": "2026-07-13T00:00:00Z"
}
```

Gateway는 `decision=ALLOW`, `current_consent_epoch == payload.consent_epoch`, `current_acl_version == payload.acl_version`, 네 current decision이 모두 `ALLOW`, `authorized_payload_sha256 == payload.payload_sha256 == recomputed request input hash`, context ID와 policy version 일치가 동시에 참일 때만 계속한다. ACL이 더 새롭거나 오래된 모든 불일치는 `ACL_VERSION_STALE`, consent 불일치는 `CONSENT_EPOCH_STALE`다. 과거 ALLOW cache나 JWT snapshot은 사용할 수 없고 timeout·5xx·stale replica·응답 불완전은 `AUTHZ_UNAVAILABLE`로 거부한다. negative cache는 허용하지만 ALLOW cache는 금지한다.

개인 주체가 없는 공개 문서 호출도 `subject_pseudonym=null`, `consent_basis=PUBLICATION_RIGHTS`인 context와 현재 권리 승인을 요구한다. 운영 상태·health probe만 DataUseContext 예외이며 사용자 payload를 받을 수 없다.

### 3.3 미분류 데이터와 safeguarding

등급을 판정하지 못한 교사 자유서술, narrative field, raw upload, scan/OCR 원문은 모두 `RESTRICTED`다. 분류와 정책 승인이 둘 다 성공하기 전 external destination은 `DENY`다. RESTRICTED는 승인된 내부 model만 사용할 수 있고 내부 경로도 목적·동의·tenant·권리 검사를 생략하지 않는다.

전처리기는 모델 호출 전에 `STANDARD`, `CHILD_SAFEGUARDING`, `IMMINENT_DANGER`, `SECURITY_EXFILTRATION`, `POLICY_BLOCK` 중 하나를 결정한다. `CHILD_SAFEGUARDING`과 `IMMINENT_DANGER`는 외부 AI를 호출하지 않고 최소정보만 기관 승인 safeguarding queue와 사용자 안내 경로로 보낸다. 자동 신고·징계·인사조치를 만들지 않으며 훈련된 담당자와 법적 근거가 후속 조치를 결정한다. `SECURITY_EXFILTRATION`은 tool 호출과 egress를 차단하고 보안 event를 만든다. classifier 불가·timeout·unknown 결과는 `POLICY_BLOCK`이다.

## 4. Tenant와 권리 철회 계약

### 4.1 저장 불변조건

`Tenant`는 격리·키·quota·audit의 최상위 단위이고 `Organization`은 하나의 tenant에 속하는 업무 조직이다. `Membership(tenant_id,user_id,organization_id,role_id,valid_from,valid_to,version)`이 사용자 접근을 부여한다. access token은 하나의 `active_tenant_id`, membership ID/version과 role-policy version만 갖는다. 여러 membership을 가진 사용자는 `POST /api/v1/tenants/{tenant_id}/activate`에서 current membership과 MFA/재인증 정책을 확인한 뒤 새 token을 받아 전환하며, request header/query/path로 active tenant를 덮어쓰지 않는다.

공개 콘텐츠는 tenant row의 nullable tenant나 우회 RLS로 표현하지 않는다. 별도 immutable `PublicRegistryEntry` allowlist가 opaque public ID, current publication/rights pointer와 source hash만 제공한다. tenant-owned 원본 dereference는 current rights를 다시 승인한다. global entity registry는 정책 ID, 공개 taxonomy, schema identifier 같은 immutable 기준정보만 허용하고 사용자·기관·문서·AI 실행을 포함할 수 없다.

tenant-scoped relational entity는 `tenant_id NOT NULL`을 가지며 기본키·unique key·부모 FK에 tenant key를 포함한다. 표준 형태는 `PRIMARY KEY (tenant_id, id)`와 `FOREIGN KEY (tenant_id, parent_id) REFERENCES parent(tenant_id, id)`다. 전역 entity는 registry allowlist에 명시된 immutable 공개 기준정보로 제한한다.

PostgreSQL 요청은 current membership을 검증한 뒤 transaction을 시작하고 첫 DB statement로 parameterized `SET LOCAL app.tenant_id = :validated_tenant_id`를 실행한다. 이어 `current_setting('app.tenant_id', true)` equality를 확인한 뒤에만 domain query를 허용한다. 모든 tenant table에 `ENABLE ROW LEVEL SECURITY`, `FORCE ROW LEVEL SECURITY`, 동일 tenant의 `USING`과 `WITH CHECK` policy를 적용한다. connection pool 반환 시 transaction 종료로 local setting이 소멸해야 하며, background job도 signed event tenant와 current service grant를 재검증해 새 transaction에서 같은 절차를 수행한다. 업무 service role은 `BYPASSRLS`·superuser가 될 수 없다. RLS를 제공하지 않는 datastore는 tenant key를 storage key/partition와 authorization condition에 원자적으로 결합하고 cross-tenant negative test로 동등함을 증명해야 한다. application `WHERE tenant_id=...`만으로는 동등한 통제가 아니다. 이 datastore-bound invariant와 자동 부정 시험이 없는 tenant entity는 production 승인을 받을 수 없다.

Object key는 `tenants/{tenant_id}/...`, encryption context는 tenant ID를 포함한다. Redis key, queue, search/vector index, cache와 outbox/event envelope도 tenant namespace를 요구한다. vector 검색은 ANN 후보 생성 전에 tenant와 현재 ACL predicate를 적용하거나 물리 tenant partition을 사용해야 하며 post-filter-only 검색은 금지한다. signed URL은 tenant·object·operation·최대 5분 expiry에 묶고 발급과 사용 시 권리를 확인한다.

### 4.2 `acl_version`과 현재 권리 재승인

`acl_version`은 tenant별 단조 증가 정수로 membership, document ACL, publication state, license/retention right, legal hold 또는 subject access 변경 transaction에서 증가한다. 검색 index와 citation에 저장된 ACL은 후보 생성용 snapshot일 뿐 권한 근거가 아니다.

TCH-015 초안 화면의 `ACTIVE_TENANT_MEMBERSHIP`은 route 진입 조건일 뿐 resource authorization이 아니다. [tch-015-authorization-contract.json](tch-015-authorization-contract.json)의 네 operation 계약이 tenant equality, 교사 owner 또는 검수자 assignment, draft state와 action을 모두 검사한다. `PATCH`와 `export`는 교사 owner 전용이고, `review`는 교사의 `SUBMIT_REVIEW`와 배정 검수자의 `APPROVE`/`REQUEST_CHANGES`를 분기한다. unknown role/action/state, 교사의 승인, 검수자의 편집·내보내기, 같은 tenant의 비소유·미배정 접근과 다른 tenant 접근은 기본 `DENY`다. allow 6개와 role·tenant·ownership/assignment·state denial 11개로 구성된 17개 canonical case를 `T-DOC-012`에 결속한다.

검색 결과 반환, RAG evidence 선택, claim-citation 검증, citation dereference, draft export 각각에서 canonical database의 현재 membership·source publication·license·retention·ACL을 동기 재승인한다. Citation은 `tenant_id`, immutable `document_version_id`, locator, source hash와 생성 당시 `acl_version`을 저장하고, 응답에는 판정 시점의 current `acl_version`을 기록한다. 현재 권리가 없거나 권리 service가 불가하면 해당 evidence와 claim을 제거하고, 근거가 부족하면 no-answer로 전환한다.

권리 철회는 canonical transaction을 먼저 commit하여 즉시 deny하고 purge/reindex event를 outbox에 기록한다. index 삭제 완료를 기다려 접근을 차단해서는 안 된다. index snapshot rollback은 ranking·embedding 상태만 되돌릴 수 있으며 현재 ACL, publication, license, retention, deletion ledger 또는 `acl_version`을 과거로 되돌릴 수 없다. rollback snapshot에 현재 무권리 chunk가 있어도 query와 citation 단계에서 반드시 제거한다.

## 5. 결정적 진단·페르소나·추천 정책

입력 집합은 `(tenant_id, immutable result/session snapshot)`에 고정한다. ID와 feature key는 NFC UTF-8 bytewise 오름차순, UUID는 lowercase canonical text, profile은 기준선 순서 `O`로 순회한다. 정렬되지 않은 map iteration, database natural order, SIMD/FMA 차이와 host `libm` 호출은 금지한다. 저장 결과는 입력 artifact hash, 정책 alias·semantic version·hash, deterministic math runtime version/digest와 tie-break 결과를 가진다.

scoring과 recommendation은 `SCALE=1_000_000`인 non-negative arbitrary-precision integer fixed-point를 사용한다. `[0,1]` 입력은 정확히 여섯 소수의 canonical decimal string으로 받고 `u = decimal * SCALE`로 변환한다. `div_half_up(n,d)=floor((2*n+d)/(2*d))`(`n>=0,d>0`)만 반올림에 사용한다. 결과는 JSON integer `*_microunit`와 정확히 여섯 소수의 `*_decimal` string을 함께 저장하고 JCS로 직렬화한다.

### 5.1 `ScoringPolicyVersion=diagnosis-scoring.v1`

승인 rubric은 여섯 소수 decimal의 dimension weight `W_d>0`, indicator weight `w_i>0`, 각 indicator의 ordinal anchor 수 `K_i>=2`를 가진다. evidence는 `indicator_id`, `anchor a_i∈{0,...,K_i-1}`, 여섯 소수 confidence `c_i∈[0,1]`, `turn_sequence`, half-open span과 UUID를 요구한다. schema 밖 값은 계산에서 조용히 버리지 않고 결과 전체를 `INVALID_EVIDENCE`로 만든다.

1. 같은 `(indicator_id, turn_sequence)` evidence는 confidence 내림차순, span 시작 오름차순, evidence UUID bytewise 오름차순의 첫 항목만 선택한다.
2. 선택 evidence를 `(indicator_id UTF-8, turn_sequence, span_start, evidence UUID)`로 정렬하고 `x_i_u=div_half_up(100*SCALE*a_i,K_i-1)`, `q_i_u2=w_i_u*c_i_u`로 변환한다.
3. dimension에 `q_i_u2>0`인 evidence가 없으면 그 dimension은 `INSUFFICIENT_EVIDENCE`이며 숫자 점수를 만들지 않는다.
4. dimension ID 순서로 각 dimension 내부를 위 순서대로 누적해 `S_d_u=div_half_up(Σ(q_i_u2*x_i_u),Σq_i_u2)`를 계산한다.
5. required dimension 하나라도 `INSUFFICIENT_EVIDENCE`이면 overall은 `INSUFFICIENT_EVIDENCE`다. 그렇지 않으면 숫자 점수가 있는 dimension ID 순서 집합 `D*`에 대해 `S_u=div_half_up(Σ(W_d_u*S_d_u),ΣW_d_u)`다.
6. 다음 질문 후보는 아직 충족되지 않은 required indicator 우선, `coverage_count` 오름차순, rubric priority 오름차순, `question_id` NFC UTF-8 bytewise 오름차순으로 하나를 선택한다.

LLM은 anchor와 evidence 후보를 제안할 수 있지만 점수, 누락 판정과 tie-break를 계산하지 않는다.

#### 5.1.1 `DiagnosisDecisionPolicyVersion=diagnosis-decision.v1`

진단 decision은 다음 exact 순서를 사용하며 뒤 단계가 앞 단계 오류를 덮을 수 없다.

1. score가 `0..100000000`, confidence/conflict가 `0..1000000` 밖이거나 numeric field가 boolean/non-integer이거나 required coverage field가 boolean이 아니면 먼저 `INVALID_EVIDENCE`다. level과 numeric 결과를 발행하지 않는다.
2. required indicator마다 confidence가 `>=600000`인 서로 다른 `turn_sequence` evidence가 최소 2개 없으면 `INSUFFICIENT_EVIDENCE`다. 단일 turn에서 반복된 span은 두 회로 세지 않는다.
3. confidence `>=600000`인 서로 다른 turn의 같은 indicator anchor pair로 계산한 최대 conflict가 `>=500000`이면 `HUMAN_REVIEW_REQUIRED`다. 정확히 `500000`도 review다.
4. 전체 confidence가 `<600000`이면 `ADDITIONAL_CONFIRMATION_REQUIRED`다. 정확히 `600000`은 통과한다.
5. 위 조건이 없을 때 score `0..24999999=L1`, `25000000..49999999=L2`, `50000000..74999999=L3`, `75000000..100000000=L4`로 `LEVEL_ASSIGNED`한다.

따라서 precedence는 exact `INVALID_EVIDENCE → INSUFFICIENT_EVIDENCE → HUMAN_REVIEW_REQUIRED → ADDITIONAL_CONFIRMATION_REQUIRED → LEVEL_ASSIGNED`다. required coverage, conflict와 level boundary의 양쪽 경계는 [diagnosis-scoring-golden-vectors.json](diagnosis-scoring-golden-vectors.json)의 `decision_contract`와 모든 `decision_vectors`를 executable oracle로 사용한다. 구현은 표에서 기대값을 다시 계산해 자기 정당화하지 않고 vector expected object와 byte-level 비교한다.

### 5.2 `PersonaInferencePolicyVersion=persona-inference.v1`

기준선의 정확한 12-profile 순서를 `O`로 사용한다. 승인 policy artifact는 소수점 이하 정확히 12자리인 canonical decimal string으로 profile별 intercept `b_p`, feature coefficient `β_pj`, feature별 normalization mean `μ_j`와 양수 scale `σ_j`를 가진다. feature가 하나라도 없거나 non-finite면 `INSUFFICIENT_EVIDENCE`이며 0으로 대치하지 않는다.

`DeterministicMathRuntimeVersion=detmath-decimal128.v1`은 release manifest에 immutable WASM artifact SHA-256과 함께 고정한다. 이 runtime만 precision 34, exponent range `[-6143,6144]`, `ROUND_HALF_EVEN` decimal context와 correctly-rounded decimal `exp`를 제공한다. 모든 환경은 같은 WASM digest를 사용하며 digest 누락·불일치는 `POLICY_VERSION_MISMATCH`다. feature는 feature ID UTF-8 순서, profile은 `O` 순서로 multiply/add하고 host floating point와 host `exp`를 사용하지 않는다.

```text
z_j = (x_j - μ_j) / σ_j
logit_p = b_p + Σ_j β_pj*z_j
m = max_p(logit_p)
profile_probability_p = exp(logit_p-m) / Σ_q exp(logit_q-m)
family_probability_f = Σ_{p in f} profile_probability_p
```

각 raw probability는 pinned runtime에서 계산한다. `floor(raw_probability*SCALE)`을 profile 순서로 구하고, `remainder=SCALE-Σfloor`만큼 1 micro-unit을 fractional remainder 내림차순, 동률이면 `O` 순서에 따라 한 번씩 더하는 largest-remainder correction을 적용한다. 따라서 profile integer 합은 정확히 `1_000_000`, family integer는 두 profile integer의 합이며 family 합도 정확히 `1_000_000`이다. 확률은 integer `probability_microunit`와 `0.000000`~`1.000000` fixed-six string으로만 직렬화한다.

top profile은 integer probability 내림차순 후 `O` 순서로 정확히 3개를 선택한다. family tie는 family ID 오름차순이다. `max(family_probability_microunit)<450000`일 때만 `MIXED_OR_UNDETERMINED`; 정확히 `450000`은 해당 family다. 사용자 수정은 별도 `user_selected_context`로 저장해 UI·추천 입력에서 우선할 수 있지만 inferred 확률을 덮어쓰거나 인사평가에 사용할 수 없다.

### 5.3 `RecommendationPolicyVersion=recommendation-ranking.v1`

후보는 현재 tenant/ACL·게시·license·기간·언어·접근성·prerequisite·사용자 차단 조건을 모두 만족해야 한다. 한 hard filter가 unknown이면 제외한다. 각 feature는 versioned extractor가 canonical fixed-six `[0,1]` 범위를 검증한 뒤 micro-unit integer로 변환하며 out-of-range 값을 clamp하지 않는다.

```text
base_u(c) = div_half_up(400000*competency_gap_match_u
                       + 200000*persona_fit_u
                       + 150000*difficulty_fit_u
                       + 100000*constraint_fit_u
                       + 100000*quality_prior_u
                       +  50000*freshness_u, SCALE)

novelty_u(c, selected) = SCALE                    if selected is empty
  SCALE - max div_half_up(SCALE*|tags(c)∩tags(s)|, |tags(c)∪tags(s)|) otherwise
selection_score_u(c) = div_half_up(850000*base_u(c)
                                  + 150000*novelty_u(c, selected), SCALE)
```

tag는 NFC UTF-8 bytewise 정렬·중복 제거 후 integer set count를 계산한다. 빈 tag 집합끼리 Jaccard는 0, 동일한 non-empty 집합은 1이다. Top-N은 후보를 먼저 `content_id` bytewise 순서로 평가하고 빈 집합에서 시작해 `selection_score_u` 내림차순, `base_u` 내림차순, duration 분 오름차순, `content_id` UUID bytewise 오름차순으로 한 개씩 greedy 선택한다. 선택 직전 current source rights를 다시 확인하고 탈락 후보는 제외한 뒤 남은 후보를 같은 고정 순서로 다시 계산한다. 설명 LLM은 선택·순위를 변경할 수 없고 저장된 feature와 citation만 문장화한다.

### 5.4 Canonical output과 golden vectors

동일 canonical input bytes, policy artifact hashes와 deterministic runtime digest에 대해서만 output object를 JCS로 직렬화한 bytes가 동일하다고 판정한다. decimal 의미값은 fixed-six/fixed-twelve string, fixed-point 값은 JSON integer, ID는 lowercase canonical string, array는 위 고정 순서로 직렬화한다. 다음 vector는 release suite의 최소 immutable golden set이다.

repository의 executable seed는 [diagnosis-scoring-golden-vectors.json](diagnosis-scoring-golden-vectors.json)이다. 표와 JSON이 충돌하면 이 절의 알고리즘을 기준으로 JSON을 수정하고 새 policy/version 평가를 수행한다. JSON은 표의 scoring/persona/recommendation/tie vector와 scoring duplicate-selection·invalid-evidence vector를 모두 포함하며, 모든 지원 runtime에서 byte-level 동일해야 한다.

| Vector | 입력 | 정확한 기대값 |
|---|---|---|
| `GV-SCORE-001` | 한 dimension/indicator, `W=w=1.000000`, `K=5`, `a=3`, `c=0.800000` | dimension/overall `score_microunit=75000000`, `score_decimal="75.000000"` |
| `GV-PERSONA-001` | 12개 logit 모두 `0.000000000000` | `O[0..3]=83334`, `O[4..11]=83333`; family `P-01=166668`, `P-02=166668`, 나머지 `166666`; `MIXED_OR_UNDETERMINED` |
| `GV-PERSONA-002` | family micro-unit `[450000,110000,110000,110000,110000,110000]` | 최대값이 경계와 같으므로 `P-01`, mixed 아님 |
| `GV-REC-001` | 모든 feature `1.000000`, selected 비어 있음 | `base_microunit=1000000`, `selection_score_microunit=1000000` |
| `GV-REC-002` | feature `[0.500000,1.000000,0.000000,1.000000,0.000000,0.000000]`, max Jaccard `0.500000` | `base_microunit=500000`, `novelty_microunit=500000`, `selection_score_microunit=500000` |
| `GV-TIE-001` | score·base·duration 동일, content UUID `00000000-0000-4000-8000-000000000001`과 `00000000-0000-4000-8000-000000000002` | suffix `...0001` 후보가 먼저 선택됨 |

## 6. DocumentGraph JSON schema와 locator

### 6.1 Canonical graph

`DocumentGraphSchemaVersion=document-graph.v1`은 repository의 immutable [JSON Schema 2020-12 artifact](document-graph.schema.json)와 `$id=urn:yonlab:document-graph:1.0.0`을 가리킨다. schema SHA-256을 SchemaRegistry와 release manifest에 고정하고 같은 `$id`의 file bytes를 덮어쓰지 않는다. artifact는 graph, closed node object, HWPX/page/table locator, table/cell topology, provenance, validation과 integer micro-unit 좌표의 required field를 정의한다. deep verifier는 root required field와 `additionalProperties=false`, source locator union, node/table/cell topology, `nodes.minItems=1`, `confidence_ppm` 및 bbox `x0/y0/x1/y1_microunit`의 exact integer 범위 `0..1_000_000`을 별도로 고정한다. schema 내부 값을 완화하고 overlay digest를 갱신해도 이 독립 계약을 통과할 수 없다.

node type은 `DOCUMENT, SECTION, PARAGRAPH, LIST, LIST_ITEM, TABLE, ROW, CELL, IMAGE, CAPTION, FOOTNOTE, HEADER, FOOTER, PAGE_BREAK` allowlist다. 모든 node는 schema-required parent, 0-based sibling order, NFC text, locator, integer `confidence_ppm`, children과 provenance를 가진다. `nodes` array는 root-first preorder이고 각 `children`은 `order` 오름차순이며 동일 parent의 order는 연속 `0..n-1`이어야 한다. child 순환, orphan, duplicate node ID/order, root 불일치, source hash 불일치, schema unknown은 publish를 차단한다. chunk는 node ID의 ordered set만 참조하고 locator를 새로 만들지 않는다.

### 6.2 `LocatorPolicyVersion=source-locator.v1`

- 모든 character offset은 NFC-normalized text의 Unicode code point 기준 0-based half-open `[start_codepoint,end_codepoint)`이며 end는 start 이상이다.
- HWPX `package_part`는 NFC literal character의 absolute POSIX path다. `.`/`..` segment, backslash와 percent-encoding을 금지한다. `element_path`의 각 segment는 `Q{namespace-uri}local-name[zero-based-sibling-occurrence]`이며 root부터 absolute하게 연결한다. 암묵적 namespace와 변환 때 달라지는 임의 array index는 금지한다.
- page locator는 `page_number` 1-based, top-left origin이고 bbox는 page width·height를 `0..1_000_000`으로 정규화한 integer micro-unit `x0/y0/x1/y1_microunit`이다. `x0<x1`, `y0<y1`을 semantic validator가 강제하며 floating coordinate를 저장하지 않는다.
- table locator와 cell data는 table node ID와 0-based half-open `[row_start,row_end)`, `[column_start,column_end)`를 사용하며 end는 start보다 커야 한다. merged cell은 anchor cell 하나와 range를 저장하고 covered cell을 중복 생성하지 않는다.
- citation은 document version과 source SHA-256을 고정한다. 다른 version에서 동일 문장을 찾아 자동 재지정하지 않는다.

locator object의 string은 NFC, UUID·SHA-256은 lowercase, integer는 leading zero 없는 base-10 JSON integer로 만든 뒤 `locator_bytes=UTF-8(JCS(source_locator))`로 직렬화한다. `prefix=UTF-8("document-graph.v1\n" + node.type + "\n" + base10(node.order) + "\n")`, `name_bytes=prefix || locator_bytes`로 만들고 RFC 4122 UUIDv5의 namespace UUID는 `document_version_id`의 16 network-order bytes로 사용한다. 결과 lowercase UUID가 `node_id`이며 다른 namespace, delimiter, key order 또는 locator serialization은 허용하지 않는다. 전체 graph canonical bytes는 위 preorder array를 포함한 `UTF-8(JCS(graph))`다.

UI는 page/row/column을 사람에게 1-based로 표시할 수 있으나 API와 저장소의 locator를 바꾸지 않는다. schema validation 뒤 semantic validator가 range 관계, graph topology, preorder, UUIDv5 재계산과 locator round-trip을 검사한다. 하나라도 실패하면 `LOCATOR_UNRESOLVABLE`이며 해당 graph, chunk와 citation을 publish하지 않는다.

### 6.3 `HwpConversionPolicyVersion=hwp-conversion.v1`

HWP binary는 직접 publish/parser 입력으로 사용하지 않고 별도 Windows VM/node의 격리 converter에서 HWPX로 변환한 뒤 canonical DocumentGraph를 만든다. Linux Compose가 Windows worker를 포함한다고 가정하지 않는다. Application/Document worker는 broker 전용 queue에 `source_object_id`, tenant, SHA-256, detected MIME, requested output `HWPX`, converter image digest, config hash와 idempotency key만 게시한다. Windows worker는 SPIFFE mTLS identity로 queue를 소비하고 short-lived tenant-bound object capability로 입력을 읽고 출력 manifest를 쓴다. DB credential, interactive desktop, inbound public port와 일반 network egress를 갖지 않는다. OS egress allowlist는 SPIRE, broker, object endpoint, telemetry만 허용한다. worker는 read-only base image 또는 immutable VM image, 비특권 service account, CPU/memory/time 제한, macro·script·OLE 실행 금지, 입력별 disposable workspace를 강제한다.

[hwp-conversion-boundary-contract.json](hwp-conversion-boundary-contract.json)은 bridge/child의 executable 상위 계약이다. bridge만 exact allowlist `conversion-job-broker`, `tenant-object-capability-service`, `telemetry-collector`에 egress할 수 있다. raw document bytes는 queue에 넣지 않고 최대 300초 job envelope와 tenant-bound object capability로 전달한다. child는 job당 하나의 unprivileged ephemeral process이고 bridge와 host-local named pipe 또는 vsock의 length-prefixed canonical CBOR만 사용한다. child network socket, credential/environment secret, DB, queue, object storage, telemetry와 host path는 모두 `NONE/DENY`다. input은 read-only single file, output은 write-only empty directory이며 binary mount는 read-only다.

bridge는 child output을 바로 신뢰하지 않는다. exact job/tenant/input hash, output actual byte size/hash, approved converter image·binary·sandbox digest, structure/preview evidence와 bridge Ed25519 signature를 모두 확인한 output attestation 뒤에만 object commit과 queue ACK를 수행한다. production converter binary/image/license와 대표 HWP/HWPX golden corpus의 fresh structure·preview evidence가 없으면 contract state는 `BLOCKED_UNTIL_PRODUCTION_CONVERTER_AND_GOLDEN_CORPUS_EVIDENCE`이고 release는 `BLOCKED`다. simulator는 기능 개발용일 뿐 production 수용 증거가 될 수 없다.

출력 manifest는 HWPX SHA-256, converter/version/license, 시작·종료시각, section/page/paragraph/table/cell/image/footnote count, normalized text hash, 발견·손실 항목과 malware result를 포함한다. package path traversal, encrypted/unsupported stream, decompression limit, XML/schema 오류 또는 malware는 `FAILED`; 텍스트 hash 부재, structure count 불일치, merged-cell·footnote·caption·reading-order 손실은 `REVIEW_REQUIRED`다. `PASS` 또는 승인 reviewer가 서명한 `REVIEW_REQUIRED`만 graph 단계로 이동한다. reviewer 승인은 손실 목록과 preview hash에 묶인다.

동일 source SHA-256, converter digest와 config hash는 metadata-normalization 후 동일 canonical HWPX hash를 내야 한다. 그렇지 않으면 converter release를 차단한다. 원본은 quarantine/retention policy에 따라 보존하고 변환 artifact는 원본보다 낮은 data class를 가질 수 없다. HWP export는 승인 HWPX에서 별도 격리 변환하며 원본 HWP를 덮어쓰지 않는다.

stage/production readiness는 converter license ID/expiry, immutable OS·converter digest, queue concurrency·age, success/error rate, disposable workspace cleanup과 malware scanner health를 확인한다. capacity 초과는 queue/backpressure로 처리하고 다른 경로로 raw HWP를 우회하지 않는다. local/test는 같은 queue/object/manifest 계약의 deterministic simulator를 사용하며 기능 상태를 `SIMULATED`; simulator가 없으면 `DISABLED`로 표시한다. simulator 결과는 HWP 형식 수용 증거로 사용할 수 없다.

## 7. 물리 데이터·파기 계약

모든 raw source, normalized text, DocumentGraph, chunk, embedding, prompt sample, cache, export와 backup manifest는 `tenant_id`, source lineage, purpose, data class, retention policy와 encryption key reference를 가진다. 파생물 등급은 모든 source 중 가장 강한 등급보다 낮아질 수 없다. embedding과 model input/output도 개인정보·권리 파기 범위에 포함한다.

삭제 상태는 `ACTIVE → DELETE_REQUESTED → PURGING → VERIFIED`이며 legal hold가 있으면 `LEGAL_HOLD`로 분기한다. `DELETE_REQUESTED` transaction은 현재 읽기·AI 사용·citation을 즉시 deny하고 `consent_epoch` 또는 `acl_version`을 증가시키며 immutable deletion ledger와 purge outbox를 함께 기록한다. purge worker는 DB 본문, object/version, cache, search/vector row, evaluation copy, export, provider-held artifact를 lineage로 삭제하고 각 adapter receipt/hash를 모은다. `VERIFIED`는 독립 verifier가 예상 location과 실제 receipt를 대조한 뒤에만 가능하다.

법적 감사가 요구되면 content·직접 식별자는 제거하고 request ID, 대상의 keyed hash, 법적 근거, 요청·완료시각, verifier와 receipt hash만 tombstone으로 보존한다. backup은 즉시 변조하지 않되 복원 전에 deletion ledger를 재적용하고 삭제 대상 key의 crypto-erasure를 수행한다. 복원 시험은 삭제 데이터가 query, object, vector, cache, citation과 AI context에 재등장하지 않음을 확인해야 한다. 삭제 adapter 불가, receipt 누락 또는 lineage unknown은 `BLOCKED` 증거이며 release 상태를 `ACCEPTED`로 만들 수 없다.

## 8. 필수 계약 시험과 production topology 판정

다음은 구현 release의 최소 자동 시험이다.

1. 변조·만료·재사용·epoch stale `DataUseContext`, authorization outage와 unknown policy가 모두 provider 호출 0건으로 거부된다.
2. API/worker/parser identity가 provider endpoint에 직접 egress하지 못하고 Gateway가 잘못된 workload/task mTLS identity를 거부한다.
3. tenant A의 PK/FK/object/cache/vector/event로 tenant B 자원을 읽거나 쓰는 부정 시험이 datastore boundary에서 실패한다.
4. ACL·license 철회 직후 stale index와 rollback snapshot이 있어도 검색·citation·signed URL·AI context에 노출되지 않는다.
5. 기준선의 profile 순서·합 tolerance·0.45 경계와 scoring/recommendation 모든 tie를 golden vector로 byte-for-byte 재현한다.
6. HWP/HWPX fixture의 section·table/merged cell·footnote·caption·locator round-trip과 malformed package quarantine를 검증한다.
7. deletion ledger fixture가 DB/object/cache/vector/export/backup-restore/provider receipt까지 `VERIFIED` 또는 명시적 `BLOCKED`가 된다.

production의 필수 topology 결정은 “별도 내부 AI Gateway 서비스”로 확정한다. 배포 환경별 node/replica 수는 부하·복구 시험으로 조정할 수 있으나 서비스 identity, mTLS, provider credential 독점, egress deny와 fail-closed DataUseContext 조건은 완화할 수 없다. topology 변경 CDR에는 task별 p95·throughput, provider/sLLM failure domain, queue·circuit behavior, tenant isolation, restricted egress 0건, cost/TCO, RTO/RPO drill과 rollback evidence를 첨부한다. 증거 상태는 기준선의 `PASS`, `FAIL`, `BLOCKED`, `REQUIRES_ACCEPTANCE_DATA`만 사용하며 누락·stale 증거가 있으면 release는 `NOT_READY`다.

## 9. Release ID·경로·source tree 무결성

`ReleaseIdentifierPolicyVersion=release-id.v1`은 [design-baseline.json](design-baseline.json)의 exact regex와 path rule을 사용한다. `release_id`는 검증된 단일 path segment이며 `docs/releases/ai-training-platform/{release_id}`와 `dist/docs/{release_id}`의 canonical non-reparse root 아래에서만 확장한다. slash, backslash, colon, percent-encoding, NUL, dot segment, trailing dot/space, absolute path, symlink, junction, mount redirect와 Windows reparse point를 거부한다. `ACCEPTED` tag relation과 pending의 tag 금지는 기준선 `tag_rule`을 따른다.

`SourceTreeHashPolicyVersion=source-tree-hash.v1`은 tracked regular file만 대상으로 한다. `.git`, 기존 `dist/`, 생성 final document roots는 제외한다. path는 repository-relative POSIX, NFC이며 UTF-8 byte order로 정렬한다. 허용 mode는 literal `100644`와 `100755`뿐이고 symlink(`120000`), submodule(`160000`), duplicate normalized path와 다른 file type은 fail closed 한다. 각 file record는 JCS object `{content_sha256,mode,path,size_bytes}`이고 manifest는 exact object `{files:[...],schema:"source-tree-manifest.v1"}`다. content hash는 exact file bytes, size는 byte length다. `source_tree_sha256=SHA-256(UTF-8(RFC8785-JCS(manifest)))`이며 다른 separator·framing·escape를 사용할 수 없다. [golden vector](source-tree-hash-golden-vector.json)의 canonical bytes와 digest를 독립 구현이 재현해야 한다.

### 9.1 Release/distribution artifact와 evidence 결속

[artifact-manifest.schema.json](artifact-manifest.schema.json)은 `scope=RELEASE|DISTRIBUTION`을 요구한다. RELEASE manifest는 `source_release_manifest_sha256=null`이고 release root만 포함한다. DISTRIBUTION manifest는 검증된 RELEASE manifest exact bytes SHA-256을 non-null로 고정하고 distribution root만 포함한다. path/source path는 repository-relative POSIX NFC이고 absolute, drive/colon, backslash, percent-encoding, dot/empty segment, duplicate와 scope 밖 containment를 거부한다. 각 scope는 자체 `artifact-manifest.json(.sig)`와 `SHA256SUMS.txt(.sig)`를 가져야 한다.

[evidence-index.schema.json](evidence-index.schema.json)의 canonical root는 exact `schema_version,release,source_commit,generated_at_utc,overall_status,evidence`다. 각 row는 exact `evidence_id,requirement_ids,test_ids,gate_ids,status,freshness,artifact_path,artifact_sha256,source_commit,executed_at_utc,expires_at_utc,owner_ids,candidate_bound,dependency_fingerprint`를 가진다. 외부 URI만으로는 release 증거가 아니며 `artifact_path` actual bytes/hash, candidate commit, `FRESH`, future expiry를 검증한다. 전체 index의 `FAIL|BLOCKED|MISSING|STALE`은 최종 reducer에 전파되고 ACCEPTED는 전체 PASS, acceptance-pending은 PASS 또는 `REQUIRES_ACCEPTANCE_DATA`만 허용한다.
