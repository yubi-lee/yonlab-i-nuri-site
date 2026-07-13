# 01. 목표 범위와 요구사항 추적성

문서 ID: REQ-BASELINE-001  
상태: 목표 기준선

## 1. 시스템 목표

YOnLab 플랫폼은 보육교사가 AI와 자연스럽게 대화하면서 자신의 역량과 학습 필요를 파악하고, 검증된 연수·자료·실천 과제를 추천받으며, HWP/HWPX 중심의 현장 자료를 출처 기반으로 검색·활용·초안 생성할 수 있도록 한다. 운영자는 AI 품질, 콘텐츠, 문서, 추천, 사용자, 성과와 보안을 통합 관리한다.

## 2. 핵심 성과지표

| ID | 지표 | 목표 | 증거 |
|---|---|---:|---|
| KPI-001 | 전문가 진단 일치도 | ≥0.80 | 이중 전문가 라벨 골든셋 |
| KPI-002 | 맞춤 연수 추천 적합도 | ≥85% | 전문가·교사 적합성 평가 |
| KPI-003 | RAG Top-5 검색 정확도 | ≥90% | HWP/HWPX/PDF 질의셋 |
| KPI-004 | 출처 제시율 | ≥95% | answer-citation 검사 |
| KPI-005 | 구조화 출력 성공률 | ≥99.5% | Schema validator 로그 |
| KPI-006 | 사용자 만족도 | ≥80/100 | 시범운영 설문 |
| KPI-007 | 시범운영 개선 반영률 | ≥80% | 이슈-릴리스 추적표 |
| KPI-008 | Restricted 외부 전송 | 0건 | egress audit |
| KPI-009 | 접근성 핵심 여정 | 오류 0건 | 자동+수동 접근성 결과 |
| KPI-010 | 백업 복구 | 승인 RPO/RTO 충족 | restore drill 기록 |

## 3. 시스템 기능 요구사항

| ID | 요구사항 | 수용 기준 |
|---|---|---|
| SYS-F-001 | 대화형 역량진단 | 세션·턴·근거·점수·결과가 재현 가능 |
| SYS-F-002 | 교사 맥락·페르소나 | 5~6종 확률 분포, 근거, 사용자 수정 제공 |
| SYS-F-003 | 결정적 진단 scoring | 동일 evidence/rubric에 동일 결과 |
| SYS-F-004 | 맞춤 추천 | 추천 사유·보완역량·학습단계·대안 표시 |
| SYS-F-005 | 학습경로 | 기초-심화-적용, 실천과제, 후속 추천 연결 |
| SYS-F-006 | 성과 리포트 | 사전·사후 진단, 학습·추천·실천 이력 포함 |
| SYS-F-007 | HWP/HWPX 수집 | 원본·파생물·권리·버전·ACL 관리 |
| SYS-F-008 | DocumentGraph | 문단·표·행·열·셀·이미지·서식 구조 보존 |
| SYS-F-009 | OCR·구조 분석 | 스캔·혼합·복잡 표 품질점수와 검수 큐 제공 |
| SYS-F-010 | Hybrid RAG | lexical+vector+metadata+reranker 지원 |
| SYS-F-011 | Grounded answer | 모든 중요 주장에 유효 evidence 연결 |
| SYS-F-012 | HWPX 초안 | 승인 템플릿·근거·변경이력·검수상태 포함 |
| SYS-F-013 | AI Gateway | OpenAI/sLLM 교체·라우팅·fallback·감사 지원 |
| SYS-F-014 | 사용자 포털 | 진단·추천·학습·검색·리포트 일관 경험 |
| SYS-F-015 | 관리자 콘솔 | 콘텐츠·문서·AI·성과·보안 통합 관리 |
| SYS-F-016 | 시범운영 | cohort, 설문, FGI, 개선항목 추적 |
| SYS-F-017 | 외부 연계 | 포털·연수·메일·스토리지 adapter 제공 |
| SYS-F-018 | 감사·재현 | 사용자·관리자·AI 실행·모델 버전 감사 가능 |

## 4. 비기능 요구사항

| ID | 요구사항 | 목표 기준 |
|---|---|---|
| SYS-NF-001 | 보안 | OWASP ASVS 기반, 취약점 High/Critical 0건 |
| SYS-NF-002 | 개인정보 | 최소수집·동의·목적제한·보유기간·파기 |
| SYS-NF-003 | 접근성 | WCAG 2.2 AA 및 공공 웹 접근성 기준 준용 |
| SYS-NF-004 | 가용성 | readiness·health·graceful degradation |
| SYS-NF-005 | 확장성 | API·worker·model serving 독립 scale-out |
| SYS-NF-006 | 성능 | 사용자별 p95 목표를 승인 성능표로 관리 |
| SYS-NF-007 | 관측성 | trace·metric·structured log·cost ledger |
| SYS-NF-008 | 이식성 | provider·storage·email·portal adapter |
| SYS-NF-009 | 재현성 | model/prompt/schema/rubric/index version 기록 |
| SYS-NF-010 | 유지보수성 | 모듈 경계, migration, API versioning |
| SYS-NF-011 | 데이터 품질 | validation·lineage·quality score·검수상태 |
| SYS-NF-012 | 복구성 | 암호화 백업, off-host 보관, restore drill |
| SYS-NF-013 | 시험 가능성 | deterministic fixture와 provider stub 제공 |
| SYS-NF-014 | 감사성 | tamper-evident audit와 최소권한 조회 |
| SYS-NF-015 | Clean-room | 타 사이트 코드·문구·자산·고유 배치 미사용 |

## 5. RFP 60개 요구사항 추적표

검증 문서의 시험 ID는 [시험 절차서](09-test-procedure-acceptance.md)를 따른다.

| RFP ID | 목표 설계 반영 | 주요 시험 |
|---|---|---|
| PLR-001 | 최종 모듈·여정·품질 기준선 | T-GOV-001 |
| PLR-002 | 역량체계·진단·추천·경로 | T-AI-001~008 |
| PLR-003 | HWP DocumentGraph·RAG·초안 | T-DOC-001~012 |
| PLR-004 | 역할별 IA·접근성·사용성 | T-UX-001~008 |
| ECR-001 | Hybrid 인프라·AI serving·storage | T-OPS-001~006 |
| ECR-002 | dev/test/stage/prod 분리 | T-DEP-001~004 |
| DER-001 | 대화형 역량진단 engine | T-AI-001~004 |
| DER-002 | 5~6종 확률적 페르소나 | T-AI-005~008 |
| DER-003 | 맞춤 추천·학습경로 | T-REC-001~007 |
| DER-004 | 개인·기관 성과 리포트 | T-RPT-001~005 |
| DER-005 | Document AI·HWP RAG | T-DOC-001~012 |
| DER-006 | 교사·관리자 반응형 UI | T-UX-001~008 |
| DER-007 | cohort·설문·FGI·개선추적 | T-PILOT-001~006 |
| DER-008 | 독립 모듈·표준 계약 | T-ARCH-001~005 |
| SIR-001 | 교사·관리자 dashboard API | T-API-001~004 |
| SIR-002 | 진단·추천·문서·성과 API/event | T-API-005~010 |
| SIR-003 | 접근성·키보드·읽기 쉬운 UI | T-A11Y-001~008 |
| DAR-001 | 명명·코드·UTC·상위표준 | T-DATA-001 |
| DAR-002 | 데이터 사전·변경이력 | T-DATA-002 |
| DAR-003 | 논리·물리 모델·index·partition | T-DATA-003 |
| DAR-004 | 모델 완전성·무결성 검증 | T-DATA-004 |
| DAR-005 | migration·version·승인 | T-DATA-005 |
| DAR-006 | 값·참조·범위·중복 검증 | T-DATA-006 |
| DAR-007 | 메타데이터·lineage·개방 API | T-DATA-007 |
| TER-001 | 자동 단위시험 | T-GATE-001 |
| TER-002 | 모듈 통합·provider stub | T-GATE-002 |
| TER-003 | 전체 시스템·부하·보안 | T-GATE-003 |
| TER-004 | 200명×2회 사용자 검증 | T-PILOT-001~006 |
| SER-001 | 보안 거버넌스·책임·점검 | T-SEC-001 |
| SER-002 | 법령·지침·개발보안 준수 | T-SEC-002 |
| SER-003 | 개발장소·원격접속 통제 | T-SEC-003 |
| SER-004 | 월간점검·자료반출·종료보안 | T-SEC-004 |
| SER-005 | 장비·IP·계정·행위 감사 | T-SEC-005 |
| SER-006 | SAST·DAST·dependency·웹취약점 | T-SEC-006 |
| SER-007 | 개인정보 동의·가명·파기 | T-PRIV-001~006 |
| SER-008 | 취약점 조치·관리수준 진단 | T-SEC-007 |
| QUR-001 | 코딩·API·문서·데이터 표준 | T-QUAL-001 |
| QUR-002 | 품질계획·요구추적·AI 품질 | T-QUAL-002 |
| QUR-003 | 확장·상호운용·유지보수 | T-ARCH-001~005 |
| QUR-004 | 요구별 기능 정확성 | T-ACC-001 |
| QUR-005 | 오류·설명·도움말·신뢰성 | T-UX-007, T-RES-001 |
| COR-001 | 공통 규정 준수대장 | T-GOV-002 |
| COR-002 | 기존 자원·표준·호환 adapter | T-INT-001~004 |
| COR-003 | 과업 변경 심의·승인 이력 | T-GOV-003 |
| COR-004 | 업무 영향도·연속성 계획 | T-BCP-001 |
| COR-005 | 손해·책임·보험 관련 산출물 | T-GOV-004 |
| COR-006 | 하도급 승인·산출물 통제 | T-GOV-005 |
| PMR-001 | 180일 WBS·milestone | T-PM-001 |
| PMR-002 | 주간·월간·이슈 보고 | T-PM-002 |
| PMR-003 | 착수·수행계획 기준선 | T-PM-003 |
| PMR-004 | 장소·장비·접근권한 계획 | T-PM-004 |
| PMR-005 | 산출물 현행화·형상관리 | T-DOCS-001 |
| PMR-006 | 위험대장·완화·escalation | T-PM-005 |
| PMR-007 | SW사업정보 저장소 제출 | T-GOV-006 |
| PMR-008 | 사전협의 조치 추적 | T-GOV-007 |
| PSR-001 | 역할별 교육계획·이수증적 | T-TRN-001 |
| PSR-002 | 사용자·관리자·운영 매뉴얼 | T-DOCS-002 |
| PSR-003 | 소스·설계·운영 기술이전 | T-TRN-002 |
| PSR-004 | 하자보수·SLA·접수절차 | T-SUP-001 |
| PSR-005 | 백업·복구·장애대응 | T-DR-001~005 |

## 6. 변경 통제

- 요구사항 변경은 ChangeRequest로 등록한다.
- 영향받는 화면, CDD, API, 엔터티, 시험 ID를 자동·수동으로 추적한다.
- 사업 범위·비용·일정·보안에 영향을 주는 변경은 CDR 또는 과업심의 승인을 요구한다.
- 승인 전 요구사항은 구현 baseline에 포함하지 않는다.
- 폐기된 요구사항도 사유, 승인자, 대체 요구사항과 함께 보존한다.

