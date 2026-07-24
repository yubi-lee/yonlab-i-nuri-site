# 설계 문서 읽기 안내

설계 기준선 전체는 [`docs/design/README.md`](../design/README.md)에 있습니다. 아래 표는 각 문서를 언제 열어야 하는지와 구현 연결점을 요약합니다.

## 거버넌스·요구사항

| 문서 | 확인할 내용 |
|---|---|
| [DOC-001](../design/00-governance/DOC-001-document-control.md) | 문서 ID, 상태, 검토·변경 통제 |
| [DOC-002](../design/00-governance/DOC-002-terminology.md) | 용어와 역할의 기준 |
| [DOC-003](../design/00-governance/DOC-003-design-principles.md) | clean-room, 보안, 교체 가능한 경계 원칙 |
| [DOC-004](../design/00-governance/DOC-004-design-decisions.md) | 기술 선택과 보류 결정 |
| [REQ-001](../design/01-requirements/REQ-001-system-requirements.md) | 기능 요구사항 |
| [REQ-002](../design/01-requirements/REQ-002-non-functional-requirements.md) | 보안·성능·접근성·운영 요구사항 |
| [REQ-003](../design/01-requirements/REQ-003-requirements-traceability.md) | 요구사항→설계→시험 추적 |

## 시스템·컴포넌트·인터페이스

| 문서 | 확인할 내용 |
|---|---|
| [SYS-001](../design/02-system/SYS-001-system-design-description.md) | 전체 시스템 설명과 경계 |
| [SYS-002](../design/02-system/SYS-002-system-context.md) | 외부 actor와 시스템 관계 |
| [SYS-003](../design/02-system/SYS-003-logical-architecture.md) | 논리 계층과 서비스 경계 |
| [SYS-004](../design/02-system/SYS-004-runtime-data-flow.md) | 요청·이벤트·데이터 흐름 |
| [SYS-005](../design/02-system/SYS-005-deployment-architecture.md) | 배포 토폴로지와 trust boundary |
| [SYS-006](../design/02-system/SYS-006-development-system.md) | 로컬 개발·검증 환경 |
| [CDD-001](../design/03-components/CDD-001-frontend.md) | React 화면, 접근성, API client |
| [CDD-002](../design/03-components/CDD-002-backend-api.md) | FastAPI router·service·error boundary |
| [CDD-003](../design/03-components/CDD-003-authentication.md) | 인증, 역할, 세션, 보안 한계 |
| [CDD-004](../design/03-components/CDD-004-cms.md) | 콘텐츠·관리자 CMS |
| [CDD-005](../design/03-components/CDD-005-search.md) | 검색과 교체 가능한 search boundary |
| [CDD-006](../design/03-components/CDD-006-storage.md) | 파일 저장·문서 처리 경계 |
| [CDD-007](../design/03-components/CDD-007-audit-observability.md) | 감사·로그·관측성 |
| [CDD-008](../design/03-components/CDD-008-database.md) | SQLAlchemy 모델·migration·tenant 데이터 |
| [ICD-001](../design/04-interfaces/ICD-001-api-interface.md) | `/api/v1` 계약과 AI platform API |
| [ICD-002](../design/04-interfaces/ICD-002-database-interface.md) | DB 스키마와 무결성 |
| [ICD-003](../design/04-interfaces/ICD-003-file-storage-interface.md) | object/file storage interface |
| [ICD-004](../design/04-interfaces/ICD-004-email-interface.md) | 이메일 provider boundary |
| [ICD-005](../design/04-interfaces/ICD-005-error-catalog.md) | 안전한 오류 응답 |

## 보안·운영·검증

| 문서 | 확인할 내용 |
|---|---|
| [SEC-001](../design/05-security/SEC-001-security-architecture.md) | 방어 계층과 secret 경계 |
| [SEC-002](../design/05-security/SEC-002-threat-model.md) | 위협·완화·잔여 위험 |
| [SEC-003](../design/05-security/SEC-003-privacy-design.md) | 최소수집·동의·보존·삭제 |
| [OPS-001](../design/06-operations/OPS-001-configuration.md) | 환경 변수와 구성 관리 |
| [OPS-002](../design/06-operations/OPS-002-deployment.md) | 배포 단계·health·rollback |
| [OPS-003](../design/06-operations/OPS-003-logging-monitoring.md) | 로그·metrics·alerts |
| [OPS-004](../design/06-operations/OPS-004-backup-recovery.md) | 백업·복원·RPO/RTO |
| [OPS-005](../design/06-operations/OPS-005-operations-runbook.md) | 장애 대응과 운영 절차 |
| [VER-001](../design/07-verification/VER-001-verification-strategy.md) | 검증 전략 |
| [VER-002](../design/07-verification/VER-002-test-design.md) | 테스트 설계와 증거 |
| [VER-003](../design/07-verification/VER-003-acceptance-criteria.md) | 수용 기준 |
| [VER-004](../design/07-verification/VER-004-quality-gates.md) | 필수 quality gate |
| [CDR package](../design/08-review/CDR-001-review-package.md) | 설계 검토 패키지·checklist·risk·record |

## 구현과 설계의 대조

구현된 vertical slice는 [`backend/app/platform.py`](../../backend/app/platform.py), [`backend/app/platform_models.py`](../../backend/app/platform_models.py), [`backend/app/document_ai.py`](../../backend/app/document_ai.py), [`frontend/src/TrainingHub.tsx`](../../frontend/src/TrainingHub.tsx)에 있습니다. 현재 구현과 설계의 차이는 [`implementation-status-2026-07-24.md`](../qa/implementation-status-2026-07-24.md)에 기록하며, 설계 변경은 조용히 덮어쓰지 않고 해당 문서와 traceability를 함께 갱신합니다.
