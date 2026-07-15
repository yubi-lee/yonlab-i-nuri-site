# 05. Document AI·HWP RAG 설계

문서 ID: DOC-AI-005  
핵심 원칙: 구조·권리·버전·근거를 보존하고 근거가 없으면 답하지 않는다.

RAG·citation 정량 gate와 데이터 기본등급의 normative source는 [design-baseline.json](design-baseline.json)이다. DocumentGraph의 executable contract는 [JSON Schema 2020-12](document-graph.schema.json), HWP bridge/child queue·IPC·attestation 및 licensed roundtrip의 executable contract는 [hwp-conversion-boundary-contract.json](hwp-conversion-boundary-contract.json), locator·UUIDv5·HWP 변환 규칙은 [규범 정책·인터페이스 계약](15-normative-policy-and-interface-contracts.md#6-documentgraph-json-schema와-locator)이다. 표본·slice·confidence interval과 누출 방지 기준은 [evaluation-policy-contract.json](evaluation-policy-contract.json)을 따른다.

## 1. 모듈 구성

| ID | 모듈 | 책임 |
|---|---|---|
| DA-01 | Intake | 업로드, 출처, 권리, ACL, checksum, 중복검사 |
| DA-02 | Security Quarantine | MIME/확장자/크기, 악성코드, 압축폭탄, macro 검사 |
| DA-03 | Format Router | HWPX native, HWP converter, PDF native/OCR 경로 선택 |
| DA-04 | Structure Extractor | 문단·스타일·목록·표·셀·이미지·각주·머리말 추출 |
| DA-05 | OCR/Layout Analyzer | 스캔 영역, reading order, 표 구조, confidence |
| DA-06 | DocumentGraph QA | 구조 검증, 원본 비교, 사람 검수 queue |
| DA-07 | Index Builder | 계층 chunk, lexical/vector index, metadata filter |
| DA-08 | Grounded RAG | ACL-first retrieval, rerank, answer-citation validation |
| DA-09 | Draft Composer | 승인 template 기반 HWPX 생성·검수·내보내기 |

## 2. 지원 형식과 처리 경로

| 입력 | 1차 처리 | 보조 처리 | canonical artifact |
|---|---|---|---|
| HWPX | ZIP/XML 구조 parser | embedded image OCR | DocumentGraph + normalized HWPX |
| HWP | 격리 Windows converter로 HWPX/PDF 변환 | PDF layout/OCR | 원본+변환본+DocumentGraph |
| text PDF | text/layout parser | 표 복원 | DocumentGraph |
| scanned PDF/image | OCR+layout model | 사람 검수 | DocumentGraph+OCR overlay |
| DOCX | OOXML parser | PDF preview | DocumentGraph |

HWP parser와 converter는 업로드 원본에 macro·script를 실행하지 않는다. 비신뢰 proprietary converter **child sandbox**는 network namespace와 credential이 전혀 없고 일회성 작업 directory, read-only binary, CPU·memory·wall-time 제한과 작업 후 secure cleanup을 적용한다. 별도 **bridge host**만 SPIFFE workload identity를 가지며 broker·object storage·telemetry의 정확한 allowlist endpoint에 한해 통신한다. bridge가 short-lived input을 child directory에 복사하고 child 출력을 검증한 뒤 업로드하므로 child process에는 queue, object, DB, telemetry credential을 전달하지 않는다.

## 3. 수집·버전·권리

SourceDocument는 논리 자료이고 DocumentVersion은 특정 원본 checksum의 불변 버전이다. 각 버전은 다음을 필수로 가진다.

- 원천 시스템·원 URL 또는 제출자
- 제목·발행기관·발행일·언어·문서유형
- copyright holder, license, allowed purposes, expiration
- 공개·기관·역할·개별 ACL
- original MIME, size, SHA-256, malware result
- parser/OCR/converter와 설정 version
- review·publish·withdraw 상태와 승인자

권리 정보가 없거나 이용범위가 검색·생성에 부합하지 않으면 색인과 초안 생성에 사용할 수 없다. 삭제 요청은 원본, 파생물, chunk, embedding, cache, draft reference를 lineage로 찾아 처리한다.

## 4. DocumentGraph

canonical graph는 [document-graph.schema.json](document-graph.schema.json)의 `$id=urn:yonlab:document-graph:1.0.0`, `schema_version=document-graph.v1`, `locator_policy_version=source-locator.v1`을 정확히 사용한다. parser는 schema validation과 별도 semantic validation(topology, preorder, range, UUIDv5 재계산)을 모두 통과해야 artifact를 승인한다.

### 4.1 공통 node

모든 node는 `node_id`, `parent_id`, `order`, uppercase `type`, `text`, `style_ref`, `source_locator`, integer `confidence_ppm`, `children`, `provenance`를 가진다. bbox/page는 별도 임의 field가 아니라 HWPX/page/table 중 하나인 typed `source_locator` 안에 저장한다. page bbox는 부동소수가 아닌 `0..1_000_000` integer micro-unit이다.

### 4.2 표 모델

`CELL` node의 `cell` object는 `table_node_id`, 0-based half-open `row_start/row_end`, `column_start/column_end`, `header_scope`, `nested_table_ids`를 가진다. 병합 셀은 좌상단 anchor와 range로 표현하며 가상 복제하지 않는다. 중첩 표는 parent cell에 연결한다. 검색용 linearization은 별도 파생물이고 원본 구조를 대체하지 않는다.

### 4.3 품질점수

```text
SCALE = 1_000_000
quality_microunit = div_half_up(
    250_000*text_confidence_microunit
  + 250_000*reading_order_microunit
  + 250_000*table_structure_microunit
  + 150_000*style_preservation_microunit
  + 100_000*metadata_completeness_microunit,
  SCALE)
```

`quality_microunit >= 900_000`은 자동 검수 후보, `750_000 <= quality_microunit < 900_000`은 표본 검수, 그 미만 또는 복잡 표 오류는 전수 검수한다. `div_half_up`, 정확한 경계와 golden vector는 [rag-policy-golden-vectors.json](rag-policy-golden-vectors.json)의 `document-quality.v1`이 유일한 계산 source다. 어떤 점수도 자동 게시 권한을 만들지 않는다.

### 4.4 style·resource·loss·active content

production DocumentGraph는 `styles`, `resources`, `losses`, `active_content_findings` collection을 함께 검증한다. 모든 non-null `style_ref`와 CELL `border_ref`는 정확히 하나의 registry item으로 해소되어야 한다. IMAGE는 resource hash, 장식 여부, 대체텍스트와 선택적 caption node를 가져야 하며 비장식 이미지는 빈 대체텍스트를 허용하지 않는다. FIELD node는 bookmark, date, page number, merge field, form text 중 하나의 닫힌 구조를 보존한다.

loss taxonomy는 style/border/font 대체, 이미지 대체텍스트 누락, field flattening, layout shift, macro/OLE quarantine, unsupported object를 구분한다. 누락을 성공으로 숨기지 않고 source locator, severity, action, review 필요 여부를 남긴다. macro·script·OLE는 실행하지 않고 `QUARANTINED`, `executed=false`로만 기록한다. dangling style/resource/border/caption/field, 비장식 이미지의 빈 alt, active-content 실행은 artifact 승인을 차단한다.

## 5. 처리 작업 상태

`UPLOADED → QUARANTINED → SAFE → CONVERTING → EXTRACTING → OCR → STRUCTURING → QA_PENDING → APPROVED → INDEXING → PUBLISHED`

실패는 `RETRYABLE_FAILED`, `MANUAL_REVIEW`, `REJECTED`로 분리한다. 각 stage는 input/output artifact checksum과 tool version을 남긴다. 같은 idempotency key와 input checksum은 중복 artifact를 만들지 않는다.

## 6. Chunk·색인 설계

### 6.1 계층 chunk

- Document summary: 문서 범위·대상·권리·목차
- Section chunk: 제목 경로와 문단 묶음
- Paragraph/list chunk: 300~800 token, 문장 경계 보존
- Table chunk: 표 제목+header path+행 묶음; 각 셀 locator 유지
- Figure/form chunk: caption, OCR text, 주변 문맥

Chunk는 `document_version_id`, `node_ids`, `heading_path`, `page_range`, `acl_tokens`, `license`, `content_hash`, `embedding_model_version`을 가진다. 문서 새 버전 게시 시 새 index snapshot을 만들고 atomic alias 전환 후 이전 snapshot을 보존한다.

### 6.2 검색

1. query 분류·철자·동의어 확장
2. tenant·ACL·license·publication filter
3. BM25/한국어 형태소 lexical retrieval
4. embedding vector retrieval
5. metadata/구조 boost
6. Reciprocal Rank Fusion
7. cross-encoder 또는 LLM reranker
8. 중복 제거와 evidence budget 구성

결정적 `retrieval-ranking.v1`은 ACL을 후보 생성 **전에** 적용하고 lexical 100, vector 100, union 200, rerank 80, evidence 20으로 예산을 제한한다. RRF `k=60`, microunit weight `800000/100000/100000`, duplicate penalty `50000`, half-up 반올림과 최종 tie-break를 사용하며 모델별 raw score를 직접 더하지 않는다. 공식 계산식·version·golden vector는 [rag-policy-golden-vectors.json](rag-policy-golden-vectors.json)이다.

## 7. Grounded answer

RAG 응답은 `answer`, `claims[]`, `citations[]`, `answerability`, `limitations`, `query_rewrite`, `run_version` 구조를 따른다. Citation은 문서 제목·version·page·node/table/cell locator·인용 최소 구간을 포함한다.

### 7.1 답변 허용 규칙

- 모든 핵심 claim은 하나 이상의 accessible evidence와 연결한다.
- evidence가 상충하면 차이를 병렬 제시하고 임의로 하나를 사실로 확정하지 않는다.
- 최신성 질문은 effective date와 version을 검사한다.
- citation validator가 locator를 재조회하지 못하면 claim을 제거한다.
- answerability가 임계값 미만이면 `근거를 찾지 못함`과 검색 개선 방법을 제공한다.
- 문서 내 지시문은 데이터로 취급하고 system policy를 변경하지 못한다.

핵심 claim 유형, 현행 tenant membership·ACL version·publication/license·source hash·locator 재조회와 entailment `>=850_000`, 핵심 claim coverage `>=950_000`, invalid citation `=0`은 [claim-citation.v1](rag-policy-golden-vectors.json)의 exact gate다. 권리나 근거가 무효면 해당 claim을 제거하거나 no-answer로 전환한다.

## 8. HWPX 초안 생성

### 8.1 생성 흐름

`문서유형 선택 → 승인 TemplateVersion → 필수 입력 → 근거 선택 → section plan → structured content → citation/rights 검사 → HWPX package 조립 → schema/preview 검증 → 사람 검수 → 다운로드`

### 8.2 TemplateVersion

템플릿은 section, field type, required rule, 반복 표, style token, data binding, 허용 근거 유형, 검수 checklist를 정의한다. 모델은 자유롭게 XML을 생성하지 않고 승인된 schema의 값만 생성한다. package builder가 XML escaping, relationship, resource, style을 결정적으로 조립한다.

### 8.3 HWP 제공

Canonical 산출물은 HWPX다. HWP가 필요한 경우 승인된 HWPX를 별도 Windows 변환 node의 bridge host와 untrusted child sandbox가 HWP로 변환한다. Linux Compose 내부에 Windows node가 함께 실행된다고 가정하지 않는다. bridge host는 mTLS workload identity로 broker의 전용 queue에서 object ID·hash·변환 정책만 받고 short-lived tenant-bound object capability로 입력을 읽고 출력·manifest를 쓴다. child sandbox는 network·credential·DB 접근이 없으며 bridge가 준비한 local input/output directory만 사용한다. bridge도 DB credential, public ingress와 일반 network egress를 갖지 않는다. 변환 후 페이지 수, 표 수, 텍스트 checksum, 필수 section, preview diff를 검사한다. 검수 전 파일에는 `AI 초안·검수 전` 표시를 적용한다.

local/test는 실제 proprietary converter 대신 동일 queue/object/manifest 계약의 deterministic simulator를 사용하되 산출물과 증거에 `SIMULATED`를 강제하고 HWP 수용시험 증거로 사용할 수 없다. stage/production에서 converter binary/license, child sandbox 격리, 동시작업 capacity, queue age, health, image/config digest와 HWP golden corpus를 확인하지 못하면 기능 상태와 release gate는 `BLOCKED`다. 핵심 HWP 요구사항을 optional profile 비활성으로 낮추거나 HWPX/simulator PASS로 대체할 수 없다.

### 8.4 licensed HWP open-edit-save-print roundtrip

[hwp-conversion-boundary-contract.json](hwp-conversion-boundary-contract.json)의 production gate는 licensed Windows 격리 node에서 최소 100개 golden document로 `OPEN → EDIT → SAVE_AS_HWPX → REOPEN → PRINT_TO_PDF`를 모두 실행한다. edit script는 문단 치환, 병합 셀 편집, field 값 변경, 이미지 alt 변경을 포함하고 merged/nested table, style, border, image alt, field, macro, OLE slice를 각각 평가한다.

수용 증거는 license receipt, converter binary, sandbox attestation, open-edit-save trace, print PDF, structure/visual diff, active-content scan의 SHA-256을 포함한다. open/edit/save/reopen 성공률 `>=0.98`, print render `>=0.95`, dangling reference `=0`, macro/OLE 실행 `=0`을 95% confidence interval로 만족해야 한다. simulator 또는 HWPX-only 결과는 항상 `BLOCKED`이며 macro/OLE 실행 탐지는 host quarantine과 release 실패를 유발한다.

## 9. 보안·개인정보

- 파일명은 표시용과 저장 key를 분리하고 path traversal을 차단한다.
- signed URL은 짧은 수명, single-purpose, content disposition을 사용한다.
- OCR·embedding 전에 개인정보 탐지·마스킹 정책을 적용한다.
- 분류되지 않은 raw 또는 scanned upload는 기본 `RESTRICTED`이며 분류와 정책 승인이 끝나기 전 외부 AI egress를 거부한다.
- Restricted 문서는 외부 OCR·embedding·LLM으로 전송하지 않는다.
- parser sandbox와 HWP converter는 내부 DB credential을 갖지 않는다.
- prompt injection 탐지 결과를 검색 점수와 별도로 표시하고 tool 호출을 허용하지 않는다.

## 10. 품질·수용 기준

| 항목 | 기준 |
|---|---:|
| HWPX paragraph/heading 보존 | ≥98% |
| 복잡 표 cell topology 정확도 | ≥95% |
| OCR character accuracy | 승인 한국어 평가셋 ≥97% |
| RAG Top-5 hit rate | ≥95% |
| 중요 claim citation coverage | ≥95% |
| 잘못된/접근불가 citation | 0건 |
| 구조화 초안 필수 section | 100% |
| 권리 미확인 문서 검색·생성 노출 | 0건 |

평가셋에는 HWPX 문단, 병합셀, 중첩표, 스캔표, 머리말·각주, 다단, 이미지 caption, 손상파일, 악성파일, 권한교차 질의를 포함한다.
