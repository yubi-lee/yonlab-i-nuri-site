# Private-source traceability baseline

문서 ID: `SRC-TRACE-016`

기준일: 2026-07-14

공개 등급: Public-safe locator package

## 1. 목적과 공개 범위

이 문서는 계약 기준인 RFP와 기술 제안서가 목표 설계·시험에 어떻게 연결되는지 공개 가능한 수준으로 설명한다. 원본 PDF/DOCX, 본문 발췌, 로컬 절대 경로, 개인정보는 저장소에 포함하지 않는다. [source-traceability-manifest.json](source-traceability-manifest.json)에 파일 exact-byte digest, 수량, 제목·요약, 물리 페이지 또는 OPC 구조 locator와 설계·시험 edge만 기록한다.

RFP 원문을 대신하는 문서가 아니다. 계약 해석이나 수용 판단 시에는 아래 SHA-256과 일치하는 보호된 원본을 권한 있는 검토자가 직접 확인해야 한다.

## 2. Source identity

| Source ID | 파일명 | Exact bytes | SHA-256 | 페이지/구조 기준 |
|---|---|---:|---|---|
| `SRC-RFP-2026-05` | `(제안요청서)보육교사 맞춤형 연수혁신 AI 서비스 고도화-조달의견반영.pdf` | 2,141,467 | `2d9e23088b3e2234af8cca49847c1226840695660780b39ad549381e51a5f959` | PDF physical page 74개; requirement detail은 physical 11~38 |
| `SRC-PROPOSAL-V04` | `와이온랩_보육교사 맞춤형 연수혁신 AI 서비스 고도화 제안서_v0.4_개발설계보강.docx` | 17,475,962 | `53af230c1fbbd9f4efc504c749ed17810922080ff1b3d9d4efab423d9043da27` | DOCX docProps 179 pages; reference render 135 pages; OPC locator가 규범 |

DOCX 페이지 수는 글꼴·렌더러에 따라 달라질 수 있다. reference render는 `LibreOfficeDev 26.8.0.0.alpha0 (X86_64)`에서 135 pages였으며 위치 증거로 사용하지 않는다. 제안서 위치는 `word/document.xml`의 body child index, paragraph/table index와 정규화 텍스트 SHA-256으로 고정한다. 원본 OPC inventory는 body children 1,755개, paragraphs 1,489개, tables 264개다.

## 3. RFP detail coverage

RFP 요구사항은 60/60 모두 목록 페이지 9/10이 아니라 `Ⅲ. 제안 요청 내용 > 3. 세부요구 사항`의 상세 physical 11~38에 연결한다. `PLR-002`만 physical 11과 12에 걸쳐 있고 나머지 59개 상세 block은 각 한 physical page에 있다. 각 JSON 행은 다음을 함께 고정한다.

- 상세 물리 페이지와 인쇄 페이지 label
- 요구사항 분류 절과 상세 제목
- 공개용 engineering paraphrase
- `MANDATORY`와 obligation type
- `requirements-test-registry.json`의 exact acceptance test IDs와 design IDs

| 분류 | 행 수 | 상세 physical pages | Obligation type |
|---|---:|---|---|
| PLR | 4 | 11~13 | `PLANNING` |
| ECR | 2 | 13~14 | `ENVIRONMENT_PROVISIONING` |
| DER | 8 | 14~17 | `FUNCTIONAL_DELIVERY` |
| SIR | 3 | 18 | `INTERFACE_DELIVERY` |
| DAR | 7 | 19~21 | `DATA_GOVERNANCE` |
| TER | 4 | 21~23 | `VERIFICATION` |
| SER | 8 | 24~28 | `SECURITY_CONTROL` |
| QUR | 5 | 29~30 | `QUALITY_CONTROL` |
| COR | 6 | 31~33 | `CONTRACTUAL_CONSTRAINT` |
| PMR | 8 | 33~37 | `PROJECT_MANAGEMENT` |
| PSR | 5 | 37~38 | `SERVICE_SUPPORT` |

## 4. Proposal topic locators

각 주제는 section heading paragraph와 구현·정책 table을 한 쌍으로 연결한다. 아래 index는 zero-based이며 원문을 공개하지 않아도 exact hashed DOCX에서 위치와 내용 동일성을 재검증할 수 있다.

| Topic ID | Public-safe summary | Heading locator | Table locator |
|---|---|---|---|
| `PROPOSAL-DIAGNOSIS` | 상태 기반 진단·루브릭·근거·신뢰도 | body 398 / paragraph 342 | body 401 / table 55 |
| `PROPOSAL-PERSONA` | 대표 페르소나와 안전한 개별화 정책 | body 510 / paragraph 436 | body 518 / table 74 |
| `PROPOSAL-RECOMMENDATION` | 설명 가능한 추천·학습경로 | body 544 / paragraph 465 | body 547 / table 78 |
| `PROPOSAL-HWP-RAG` | HWP 구조 보존·검색·근거 응답·초안 | body 645 / paragraph 548 | body 647 / table 96 |
| `PROPOSAL-AI-GATEWAY` | 모델 라우팅·PII·검증·감사 통제 | body 320 / paragraph 278 | body 323 / table 41 |
| `PROPOSAL-UI` | 교사 연속 여정·관리 화면·접근성 | body 1131 / paragraph 967 | body 1134 / table 163 |
| `PROPOSAL-PILOT` | 200명·2회 검증과 피드백 재검증 | body 1205 / paragraph 1030 | body 1207 / table 174 |
| `PROPOSAL-OPERATIONS` | 운영전환·교육·품질·보안·문서 인계 | body 1694 / paragraph 1440 | body 1698 / table 253 |

## 5. 검증

공개 패키지만 검증한다.

```bash
python3 yonlab-ai-training-platform-design/verify-source-traceability.py
bash yonlab-ai-training-platform-design/test-source-traceability.sh
```

보호된 원본을 보유한 검토 환경에서는 원본 directory를 명시하여 exact bytes, PDF 74 pages, DOCX docProps/OPC inventory, 16개 locator text fingerprint까지 재검증한다. 원본 directory는 저장소 밖이어야 한다.

```bash
python3 yonlab-ai-training-platform-design/verify-source-traceability.py \
  --private-source-dir "<protected-source-directory>"
```

## 6. 정확도 한계와 변경 규칙

- PDF physical page는 exact hashed 74-page PDF의 1-based page다. 페이지 11/12와 모든 분류 전환을 렌더링해 육안 점검했지만, 공개 manifest는 긴 원문을 포함하지 않는다.
- 제안서의 physical page는 렌더러에 따라 달라지므로 OPC locator만 규범이다. 정규화 hash는 descendant text를 결합하고 Unicode NFC 적용 후 공백을 한 칸으로 축약한 UTF-8 bytes의 SHA-256이다.
- `paraphrase`는 설계 추적 label이며 법률적 인용이나 계약 해석이 아니다.
- 원본 개정 시 기존 source ID나 digest를 덮어쓰지 않는다. 새 source ID, exact digest, page/OPC locator 검토, registry edge 검증과 checker golden digest 변경을 하나의 review로 수행한다.
- private source 원본, 렌더링 복제본과 추출 본문은 Git·배포 bundle·공개 증적에 포함하지 않는다.
