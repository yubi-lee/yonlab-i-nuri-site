# YOnLearn Hub 문서 허브

이 문서 묶음은 현재 저장소에서 실제로 실행·검증된 YOnLearn Hub와 향후 운영 목표를 한 곳에서 이해하기 위한 안내서입니다. 설계 기준선은 [`docs/design/README.md`](../design/README.md), 구현 상태의 기준은 [`docs/qa/implementation-status-2026-07-24.md`](../qa/implementation-status-2026-07-24.md)입니다.

## 먼저 읽을 문서

| 순서 | 문서 | 대상 |
|---:|---|---|
| 1 | [프로젝트 개요와 범위](01-overview-and-scope.md) | 모든 독자 |
| 2 | [설계 문서 읽기 안내](02-design-document-guide.md) | 개발자·설계자·검토자 |
| 3 | [배포와 환경 구성](03-deployment-and-environment.md) | 개발자·배포 담당자 |
| 4 | [사용자·관리자 사용법](04-user-and-admin-guide.md) | 교사·기관 관리자·운영자 |
| 5 | [운영 런북](05-operations-runbook.md) | 당직자·시스템 관리자 |
| 6 | [보안·개인정보·저작권 주의사항](06-security-privacy-copyright.md) | 전 구성원 |
| 7 | [검증과 릴리스](07-verification-and-release.md) | QA·릴리스 담당자 |
| 8 | [문제 해결](08-troubleshooting.md) | 모든 운영자 |
| 9 | [시각 자료 카탈로그](09-visual-artifact-catalog.md) | 모든 독자 |

## 문서 상태와 범위

| 상태 | 의미 |
|---|---|
| `IMPLEMENTED` | 현재 코드와 자동 검증으로 동작을 확인한 범위 |
| `DESIGN_TARGET` | 설계 기준선에 정의됐지만 운영 도입 전 추가 구현·승인이 필요한 범위 |
| `BLOCKED_UNTIL_PRODUCTION_EVIDENCE` | 실제 외부 provider, OCR/converter, 보안·수용 증거가 없으면 운영 릴리스로 승격할 수 없는 범위 |

현재 커밋에는 조직·교사 프로필·진단·학습·문서 처리·근거 검색·보고서·파일럿 지표를 연결한 통합 vertical slice가 포함되어 있습니다. 이것은 운영 가능성을 검증하는 구현 결과이지, 외부 AI provider·production OCR/PDF 변환·MFA·RLS·SPIRE 신뢰체계까지 완료된 production release를 의미하지 않습니다.

## 시작 명령

저장소 루트에서 실행합니다.

```powershell
Copy-Item .env.example .env
.\scripts\setup.ps1
.\scripts\seed.ps1
.\scripts\dev.ps1
```

접속 주소는 프런트엔드 `http://localhost:5173`, API `http://localhost:8000`, Swagger `http://localhost:8000/docs`입니다. Docker Compose 사용법은 [배포와 환경 구성](03-deployment-and-environment.md)을 따릅니다.

## 시각 자료

- [시스템 컨텍스트](../diagrams/system-context.drawio.png) · [편집 가능한 원본](../diagrams/system-context.drawio)
- [배포 구성](../diagrams/deployment-topology.drawio.png) · [편집 가능한 원본](../diagrams/deployment-topology.drawio)
- [진단→학습 흐름](../diagrams/training-flow.drawio.png) · [편집 가능한 원본](../diagrams/training-flow.drawio)
- [문서→근거 검색 흐름](../diagrams/document-grounded-search.drawio.png) · [편집 가능한 원본](../diagrams/document-grounded-search.drawio)
- [도메인 데이터 모델](../diagrams/domain-data-model.drawio.png) · [편집 가능한 원본](../diagrams/domain-data-model.drawio)
- [동작 캡처와 대체텍스트](09-visual-artifact-catalog.md)

## 문서 변경 후 필수 확인

설계 문서나 이 허브의 설계 링크를 변경하면 다음 순서로 확인합니다.

```powershell
.\scripts\verify-design-docs.ps1
.\scripts\verify.ps1
```

문서에는 비밀값, 실제 개인정보, 실제 사용자 화면 캡처, 참조 사이트의 원문·이미지·레이아웃을 넣지 않습니다.
