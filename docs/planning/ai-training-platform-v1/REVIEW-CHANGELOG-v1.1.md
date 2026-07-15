# REVIEW CHANGELOG v1.1

문서 ID: REVIEW-CHANGELOG-011
기준일: 2026-07-13

## 1. 기준선 승격

- [design-baseline.json](design-baseline.json)을 경로, KPI 계산식·한계값, 페르소나 계층, 복구 목표 승인 상태, 판정 상태, 산출물 루트의 machine-readable normative source로 추가했다.
- 목표 저장소는 `D:\Views\yonlab-inuri-site`, 원격은 `https://github.com/yubi-lee/yonlab-i-nuri-site.git`, 작업 branch는 `feat/ai-training-platform-v1`로 고정했다.
- 계획 원천은 `docs/planning/ai-training-platform-v1/`에 두고 최종 설계, 운영, QA, 매뉴얼, 릴리스 산출물은 기준선에 정의한 서로 다른 루트를 사용한다.

## 2. 제거한 v1.0 값

다음 문자열은 변경 이력을 설명하기 위해 이 문서에만 남긴다. 활성 기준이나 실행 지시로 사용하지 않는다.

| 제거한 값 | v1.1 값 |
|---|---|
| `D:\Views\yonlab-i-nuri-site` | `D:\Views\yonlab-inuri-site` |
| 구조화 출력 `99.5%` | `99.8%` |
| 진단 일치 `≥0.80` | `≥0.85` |
| 추천 적합 `≥85%` | `≥90%` |
| `Top-5` 검색 정확도 `≥90%` | RAG Top-5 hit rate `≥95%` |
| `6개 persona` 또는 `6 persona` 단일 계층 | 6개 대표 family 아래 12개 versioned operational profile |

## 3. 강화한 수용 기준

- 중요 claim citation coverage는 95% 이상이고 invalid citation은 0건이어야 한다.
- 사용자 만족도는 90/100 이상, 승인 개선 반영률은 90% 이상이어야 한다.
- 12개 operational profile probability를 출력하고 이를 6개 family probability로 합산한다.
- 제안 RPO 15분, 핵심 서비스 RTO 4시간, 문서 재색인 RTO 24시간은 발주기관 승인과 격리 복구시험 증거 전까지 `REQUIRES_ACCEPTANCE_DATA`다.

## 4. Fail-closed 판정

- 증거 상태는 `PASS`, `FAIL`, `BLOCKED`, `REQUIRES_ACCEPTANCE_DATA`만 사용한다.
- `FAIL`, `BLOCKED`, 누락 또는 stale 증거가 있으면 release state는 `NOT_READY`다.
- 외부 수용 데이터만 남은 경우의 상한은 `CODE_COMPLETE / ACCEPTANCE DATA PENDING`이며 모든 필수 증거가 fresh `PASS`일 때만 `ACCEPTED`다.

## 5. 최종 타이트 기준 보강

- 화면 113개와 service-auth 4개를 합한 OpenAPI operation 117개를 명시하고, 61개 write operation은 request body가 필수인 계약으로 고정했다.
- 102개 영속 엔터티에 PK, FK, unique constraint, index, 필드 타입·nullability를 machine-readable catalog로 고정하고 참조 무결성을 검증한다.
- 최종 설계·운영·시험·사용자·관리자·릴리스 문서 147개를 `final-document-inventory.json`으로 계약화했다.
- 실행 상태를 구현 `S`, 직계 release snapshot `R`, candidate 검증, 수용 검증으로 분리했다. 구현 실행은 서명 없는 candidate까지만 만들며 `ACCEPTED`를 선언하지 않는다.
- 외부 trust store의 도구 7종 exact path·version·SHA-256·ACL 정책, artifact 서명, exact PR·CI·승인 증거를 모두 검증해야 candidate 상태가 승격된다.
- bootstrap과 runner의 도구 신뢰 경로는 user-writable LocalAppData를 제외하고 executable부터 volume root까지 trusted owner·write ACE·reparse 여부를 검증한다.
- overlay는 재귀 exact manifest, NTFS alternate stream 거부, reparse point 거부, durable write-ahead transaction과 rollback 증거를 사용한다.
- overlay backup·staging·설치 파일은 `FileStream.Flush(true)`로 data를 내린 뒤에만 `PREPARED`와 `COMMITTED` journal 상태로 전이하며, 동일 NTFS volume의 atomic rename을 metadata 경계로 명시한다.
- 패키지 내부 verifier는 발행자 신원을 스스로 증명할 수 없으므로, ZIP을 풀기 전에 별도 채널의 SHA-256을 대조하는 절차를 최초 신뢰 경계로 고정했다.

## 6. 검증 한계의 명시

- 정적·계약·변이·PowerShell 7 회귀시험 통과는 Windows 운영 승인을 대신하지 않는다.
- Windows PowerShell 5.1, 실제 NTFS ACL·ADS, Docker Desktop, 보호된 trust store, GitHub PR·CI·서명 검증은 대상 PC에서 실행 증거를 만들기 전까지 `BLOCKED` 또는 `NOT_READY`다.
- 이 패키지는 완성 애플리케이션이 아니라 구현을 통제하는 설계·실행 기준선이다. 애플리케이션 완료 판정은 runner가 생성한 증거와 별도 수용 승인을 함께 적용한다.
