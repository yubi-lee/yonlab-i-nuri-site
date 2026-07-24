# 검증과 릴리스 가이드

## 필수 gate

```powershell
.\scripts\verify-design-docs.ps1
.\scripts\verify.ps1
```

`verify.ps1`는 다음을 포함합니다.

- 설계 문서·traceability 검사
- Ruff와 backend pytest
- ESLint·TypeScript·Vitest·Vite build
- empty DB Alembic migration
- seed first run·idempotency
- Playwright desktop/mobile E2E
- secret scan
- Docker build·health·migration·seed·restart·persistence·log scan·cleanup

## 수동 smoke checklist

- [ ] 홈·자료실·상세·검색·문의 접근
- [ ] 회원 로그인 후 `/mypage` 이동
- [ ] 자료 bookmark와 문의 history 확인
- [ ] 관리자 로그인 후 `/admin` guard와 category 저장 확인
- [ ] `/training` 로그인 guard 확인
- [ ] 조직 생성·진단 시작·응답 저장·진단 완료 확인
- [ ] 학습 등록 확인
- [ ] 문서 등록·처리·근거 검색·citation 확인
- [ ] 근거 없음 상태가 추정 답변 대신 표시되는지 확인
- [ ] 390×844, 768×1024, 1440×900에서 수평 overflow가 없는지 확인

## 릴리스 판정

현재 저장소의 검증 통과는 구현된 vertical slice의 코드·통합 품질을 증명합니다. 다음이 없는 경우 production release로 판정하지 않습니다.

- 승인된 production image와 artifact provenance
- real provider/model·OCR/converter의 fresh acceptance evidence
- MFA·RLS·privacy/terms·backup/restore drill 승인
- 운영 owner와 rollback owner
- secret manager, TLS, monitoring, alert routing

## 변경 영향 규칙

| 변경 | 반드시 다시 검토할 문서 |
|---|---|
| API route/schema | ICD-001, REQ-003, API tests |
| DB model/migration | CDD-008, ICD-002, ERD, migration tests |
| 인증·권한 | CDD-003, `docs/design/05-security/`, auth tests |
| 파일·문서 처리 | CDD-006, ICD-003, privacy/security docs |
| 배포·환경 | SYS-005, OPS-001/002/004/005 |
| 화면·접근성 | CDD-001, E2E, screenshot catalog |

설계 문서 변경 후에는 `verify-design-docs.ps1`를 먼저 실행하고, 구현·문서·증거가 같은 변경 단위로 갱신됐는지 확인합니다.
