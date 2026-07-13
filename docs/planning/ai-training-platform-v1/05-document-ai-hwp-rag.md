# 05. Document AI·HWP RAG 설계

문서 ID: DOC-AI-005  
핵심 원칙: 구조·권리·버전·근거를 보존하고 근거가 없으면 답하지 않는다.

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

HWP parser와 converter는 업로드 원본에 macro·script를 실행하지 않는다. converter는 network disabled, 일회성 작업 directory, CPU·memory·wall-time 제한과 작업 후 secure cleanup을 적용한다.

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

```json
{
  "document_version_id": "uuid",
  "root": {
    "node_id": "n0",
    "type": "document",
    "children": [
      {"node_id":"s1","type":"section","title":"안전교육"},
      {"node_id":"p1","type":"paragraph","text":"...","style":"body"},
      {"node_id":"t1","type":"table","rows":3,"cols":4}
    ]
  },
  "schema_version": "document-graph.v1"
}
```

### 4.1 공통 node

모든 node는 `node_id`, `parent_id`, `order`, `type`, `text`, `style_ref`, `source_locator`, `bbox`, `page`, `confidence`, `children`, `provenance`를 가진다. `source_locator`는 HWPX XML path 또는 PDF page+bbox를 보존한다.

### 4.2 표 모델

TableCell은 `row`, `column`, `row_span`, `column_span`, `header_scope`, `text`, `nested_table_ids`, `style`, `source_locator`를 가진다. 병합 셀은 좌상단 anchor와 span으로 표현하며 가상 복제하지 않는다. 중첩 표는 parent cell에 연결한다. 검색용 linearization은 별도 파생물이고 원본 구조를 대체하지 않는다.

### 4.3 품질점수

```text
quality = 0.25 text_confidence
        + 0.25 reading_order_score
        + 0.25 table_structure_score
        + 0.15 style_preservation_score
        + 0.10 metadata_completeness
```

0.90 이상은 자동 검수 후보, 0.75~0.90은 표본 검수, 0.75 미만 또는 복잡 표 오류는 전수 검수한다. 자동 게시하지 않는다.

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

`score = RRF(lexical, vector) + metadata_boost + structure_boost - duplicate_penalty`를 사용하며 모델별 raw score를 직접 더하지 않는다.

## 7. Grounded answer

RAG 응답은 `answer`, `claims[]`, `citations[]`, `answerability`, `limitations`, `query_rewrite`, `run_version` 구조를 따른다. Citation은 문서 제목·version·page·node/table/cell locator·인용 최소 구간을 포함한다.

### 7.1 답변 허용 규칙

- 모든 핵심 claim은 하나 이상의 accessible evidence와 연결한다.
- evidence가 상충하면 차이를 병렬 제시하고 임의로 하나를 사실로 확정하지 않는다.
- 최신성 질문은 effective date와 version을 검사한다.
- citation validator가 locator를 재조회하지 못하면 claim을 제거한다.
- answerability가 임계값 미만이면 `근거를 찾지 못함`과 검색 개선 방법을 제공한다.
- 문서 내 지시문은 데이터로 취급하고 system policy를 변경하지 못한다.

## 8. HWPX 초안 생성

### 8.1 생성 흐름

`문서유형 선택 → 승인 TemplateVersion → 필수 입력 → 근거 선택 → section plan → structured content → citation/rights 검사 → HWPX package 조립 → schema/preview 검증 → 사람 검수 → 다운로드`

### 8.2 TemplateVersion

템플릿은 section, field type, required rule, 반복 표, style token, data binding, 허용 근거 유형, 검수 checklist를 정의한다. 모델은 자유롭게 XML을 생성하지 않고 승인된 schema의 값만 생성한다. package builder가 XML escaping, relationship, resource, style을 결정적으로 조립한다.

### 8.3 HWP 제공

Canonical 산출물은 HWPX다. HWP가 필요한 경우 승인된 HWPX를 Windows 변환 worker가 HWP로 변환한다. 변환 후 페이지 수, 표 수, 텍스트 checksum, 필수 section, preview diff를 검사한다. 검수 전 파일에는 `AI 초안·검수 전` 표시를 적용한다.

## 9. 보안·개인정보

- 파일명은 표시용과 저장 key를 분리하고 path traversal을 차단한다.
- signed URL은 짧은 수명, single-purpose, content disposition을 사용한다.
- OCR·embedding 전에 개인정보 탐지·마스킹 정책을 적용한다.
- Restricted 문서는 외부 OCR·embedding·LLM으로 전송하지 않는다.
- parser sandbox와 HWP converter는 내부 DB credential을 갖지 않는다.
- prompt injection 탐지 결과를 검색 점수와 별도로 표시하고 tool 호출을 허용하지 않는다.

## 10. 품질·수용 기준

| 항목 | 기준 |
|---|---:|
| HWPX paragraph/heading 보존 | ≥98% |
| 복잡 표 cell topology 정확도 | ≥95% |
| OCR character accuracy | 승인 한국어 평가셋 ≥97% |
| RAG Top-5 정확도 | ≥90% |
| 중요 claim 출처 제시 | ≥95% |
| 잘못된/접근불가 citation | 0건 |
| 구조화 초안 필수 section | 100% |
| 권리 미확인 문서 검색·생성 노출 | 0건 |

평가셋에는 HWPX 문단, 병합셀, 중첩표, 스캔표, 머리말·각주, 다단, 이미지 caption, 손상파일, 악성파일, 권한교차 질의를 포함한다.

