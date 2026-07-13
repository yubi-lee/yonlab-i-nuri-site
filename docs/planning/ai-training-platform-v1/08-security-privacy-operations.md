# 08. 보안·개인정보·운영 설계

문서 ID: SEC-OPS-008  
보안 기준: 최소권한, zero implicit trust, privacy by design, fail closed

## 1. 데이터 분류와 처리

| 등급 | 예시 | 저장·전송 | AI 처리 |
|---|---|---|---|
| PUBLIC | 게시 승인 교육자료 | 표준 암호화 | 승인 외부·내부 모델 허용 |
| INTERNAL | 운영 메타, 가명 평가셋 | 조직 접근통제 | 최소화 후 승인 route |
| PERSONAL | 이름, 이메일, 자유서술, 학습이력 | field/volume 암호화, 목적별 권한 | 비식별 field만 외부 허용 |
| RESTRICTED | raw 감사, 보안자료, 고위험 원문 | 분리 key, 강한 감사, 반출승인 | 외부 전송 금지 |

데이터 소유자는 수집 목적, 필수성, 보유기간, 처리자, 제3자 제공, 파기방식을 DataProcessingRegistry에 등록한다. 목적이 없는 field는 수집하지 않는다.

## 2. 개인정보 생명주기

1. 가입·진단·시범운영 목적별 동의를 분리한다.
2. 교사 맥락의 심리상태는 임상정보가 아닌 사용자가 선택한 학습지원 제약으로 최소 수집한다.
3. 분석·AI 평가에는 직접 식별자를 분리하고 rotating pseudonym을 사용한다.
4. 동의 철회 즉시 신규 처리를 중단하고 파기 job을 생성한다.
5. 내보내기는 재인증, 비동기 생성, 짧은 signed URL, 다운로드 감사를 적용한다.
6. 파기는 DB, object, index, cache, 평가 복제본을 lineage로 확인하고 증적을 보존한다.

## 3. 인증·세션·권한

- 비밀번호는 Argon2id와 승인 parameter로 hash하며 유출·금지 비밀번호를 거부한다.
- access token은 10분 이내, refresh session은 HttpOnly·Secure·SameSite cookie와 rotation을 사용한다.
- 사용된 refresh token 재사용을 탐지하면 token family를 폐기하고 보안 event를 만든다.
- 관리자·감사자·모델배포 권한은 MFA를 요구한다.
- 권한·secret·삭제·반출·모델배포 변경은 15분 이내 재인증한다.
- RBAC로 기능을, ABAC로 tenant·organization·ownership·data class를 판단한다.
- 사용자·기관 관리자는 다른 교사의 진단 원문을 기본 열람할 수 없다.

## 4. 애플리케이션 보안

| 위협 | 통제 |
|---|---|
| CSRF | SameSite cookie, state-changing request CSRF token, Origin 검사 |
| XSS | React escaping, sanitizer allowlist, CSP nonce, unsafe HTML 금지 |
| IDOR | resource별 policy check와 tenant predicate, negative test |
| SQL/command injection | ORM bind, allowlist, shell 호출 격리·인자 배열 |
| SSRF | outbound proxy, DNS/IP 재검증, metadata·private range 차단 |
| File attack | quarantine, magic MIME, size/decompression ratio, malware scan |
| Supply chain | lockfile, SBOM, image signing, dependency/SAST/container scan |
| Abuse | IP+account+tenant rate limit, bot control, quota, anomaly detection |
| Secret leak | secret manager, startup validation, log redaction, repository scan |

Critical/High 취약점은 production release를 차단한다. Medium은 위험 승인·기한·보완통제를 기록한다.

## 5. AI·RAG 보안

- system/developer prompt와 검색 문서를 서로 다른 trust level로 취급한다.
- 문서 안의 지시문은 실행하지 않고 인용 데이터로만 처리한다.
- tool 호출은 task별 allowlist, typed argument, 사용자·정책 승인으로 제한한다.
- 검색 전에 ACL을 적용하고 citation 조회 때 다시 권한을 확인한다.
- 외부 AI egress는 AI Gateway와 outbound allowlist를 통과해야 한다.
- prompt·response 원문은 기본 log 금지; 품질 재현용 표본은 별도 동의·가명·기한을 적용한다.
- 모델 탈옥, indirect injection, data exfiltration, cross-tenant retrieval 평가를 release gate에 포함한다.

## 6. 감사

감사 대상은 로그인, 권한·동의 변경, 진단 재산정, evidence 수정, 개인데이터 조회·반출, 문서 게시·폐기, 모델·프롬프트·정책 배포, HWP 변환, 관리자 작업, backup·restore다. AuditEvent는 actor, delegated actor, action, target, result, reason, before/after hash, source IP class, trace ID, timestamp를 가진다.

감사 저장소는 append-only/WORM 또는 hash chain을 사용하고 업무 DB 관리자도 수정할 수 없다. 검색·export는 감사자 권한과 반출승인을 요구하며 내용은 목적에 맞게 마스킹한다.

## 7. 운영 환경

### 7.1 구성·secret

- `.env.example`에는 key와 비밀이 아닌 예시만 둔다.
- production secret은 secret manager 또는 OS-protected file에서 주입한다.
- `ENVIRONMENT=production`, public URL, CORS, DB, Redis, Object Storage, email, model deployment, encryption key ID를 preflight 검사한다.
- placeholder·demo credential·약한 JWT key·localhost origin이 있으면 시작을 거부한다.
- secret rotation은 dual-key 기간과 rollback 절차를 가진다.

### 7.2 배포

`build → SBOM/scan → unit/integration → AI/doc eval → signed image → stage migration → smoke/E2E → approval → production migration → canary → full rollout`

Cloud VM+Docker Compose는 시범·초기 운영 기준으로 사용하되 reverse proxy/TLS, private DB, 자동재시작, resource limit, off-host backup, monitoring agent를 필수화한다. 확장 시 동일 image와 contract로 orchestrator 전환이 가능해야 한다.

## 8. 관측성과 SLO

| SLI | 목표 SLO |
|---|---:|
| 공개·회원 API availability | 월 99.9% |
| 일반 API latency | p95 ≤800 ms |
| 검색 latency | p95 ≤2.0 s |
| 진단 턴 첫 응답 | p95 ≤3.0 s |
| RAG 최종 답변 | p95 ≤10 s |
| 문서처리 성공률 | ≥98%, 검수대기 제외 |
| background job age | p95 ≤승인 task budget |
| error rate | 5분 window <1% |

Metric은 endpoint·task·status·model deployment까지 분해하되 user ID·원문을 label로 넣지 않는다. OpenTelemetry trace로 web→API→queue→worker→AI provider를 연결한다. 비용 ledger는 tenant·task·model별 token/GPU/storage를 집계한다.

### 8.1 경보

- P1: 전체 인증 불가, 데이터 유출 의심, DB 장애, Restricted egress
- P2: 핵심 AI 15분 장애, error rate/SLO 위반, queue 폭증, backup 실패
- P3: 일부 batch 지연, 비용 예산 80%, 품질 회귀 경고

경보에는 runbook, dashboard, 최근 배포, trace sample, 담당 escalation을 연결한다.

## 9. 백업·복구·연속성

- PostgreSQL: 일일 full+연속 WAL/PITR, AES-256 수준 암호화, off-host·cross-account 보관
- Object Storage: versioning, lifecycle, inventory, 필요 시 object lock
- 구성: image digest, IaC, migration, encrypted secret reference, release manifest
- AI/RAG: prompt·schema·rubric·model registry, source manifest; embedding은 재구축 가능
- 목표 제안: RPO 15분, 핵심 서비스 RTO 4시간, 전체 문서 재색인 RTO 24시간

분기마다 isolated restore drill을 수행해 DB-object manifest 정합성, 로그인, 진단 결과, 문서 citation, backup age를 확인한다. RPO/RTO 수치는 발주기관 승인 CDR로 확정한다.

## 10. 장애·사고 대응

1. 탐지와 incident ID 생성
2. 영향·데이터등급·사용자 범위 분류
3. 확산 방지: route 차단, key rotate, feature flag, 격리
4. 증거 보존과 원인 분석
5. 안전 복구와 무결성 확인
6. 법정·계약 통지 판단
7. 사후 분석, 재발방지, 시험 추가

운영자는 AI 오답을 서비스 장애와 분리하지 않고 품질 incident로 등록할 수 있다. model rollback은 Prompt/Schema/Route/Index snapshot을 함께 되돌린다.

## 11. 운영 전 필수 조건

- 실제 domain, DNS, TLS, CORS 승인
- production provider·data processing terms 승인
- 관리자 bootstrap과 demo account 비활성 확인
- off-host backup과 restore drill 증적
- 연락망·당직·incident·개인정보 통지 runbook
- SAST/DAST/dependency/container/pentest 결과 High/Critical 0
- 접근성·성능·AI·Document AI 수용시험 승인
- 운영·관리자·사용자 교육과 기술이전 완료

