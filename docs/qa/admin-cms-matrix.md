# 관리자 CMS 검증 매트릭스

범례: `구현`은 현재 API/UI 코드에 존재, `검증`은 자동 테스트 또는 실행 증거가 있는 항목입니다.

| 엔터티 | 목록 | 검색/필터 | 생성 | 수정 | 삭제/비활성화 | 권한 차단 | 감사 로그 | 백엔드 테스트 | 프론트 단위 | E2E/수동 |
|---|---|---|---|---|---|---|---|---|---|---|
| Resource | 구현·검증 | 구현·검증 | 구현·검증 | 구현·검증 | 구현·검증 | 공통 admin guard 검증 | 공통 CRUD audit 검증 | 파일 업로드/생성 `test_rc1.py` | 8탭 렌더 | 관리자 E2E 로그인·CMS 접근 |
| Notice | 구현·검증 | 구현·검증 | 구현 | 구현 | 구현 | 공통 guard | 공통 CRUD audit | 공통 generic route coverage | 8탭 렌더 | 관리자 탭 접근 |
| Article | 구현·검증 | 구현·검증 | 구현 | 구현 | 구현 | 공통 guard | 공통 CRUD audit | 공통 generic route coverage | 8탭 렌더 | 관리자 탭 접근 |
| FAQ | 구현·검증 | 구현·검증 | 구현 | 구현 | 구현 | 공통 guard | 공통 CRUD audit | 공통 generic route coverage | 8탭 렌더 | 관리자 탭 접근 |
| Category | 구현·검증 | 구현·검증 | 구현·검증 | 구현·검증 | 구현·검증 | 403 일반 사용자·마지막 관리자 보호 | create/update/delete 검증 | `test_admin_category_crud_and_audit_log` | 8탭 렌더 | 관리자 생성 E2E |
| Tag | 구현·검증 | 구현·검증 | 구현 | 구현 | 구현 | 공통 guard | 공통 CRUD audit | generic route coverage | 8탭 렌더 | 관리자 탭 접근 |
| Inquiry | 구현·검증 | 구현·검증 | 공개 문의 검증 | 상태/메모 수정 구현 | 상태 처리 | 공통 guard | update audit | 문의 privacy/API 테스트 | 8탭 렌더 | 회원 문의 이력 E2E |
| User | 구현·검증 | 구현·검증 | 회원가입 검증 | 역할/활성 수정 검증 | 비활성화·마지막 관리자 보호 | 일반 사용자 403 검증 | user.update audit | `test_regular_user_cannot_access_admin...` | 8탭 렌더 | 관리자 로그인·권한 E2E |

대표 E2E 범위는 Resource 접근/첨부, Category 생성, Inquiry 제출/이력, User 관리자 권한을 포함합니다. Notice/Article/Tag/FAQ의 공통 generic CRUD는 백엔드 route 구조와 관리자 탭 렌더 테스트로 증거를 유지하며, 별도 반복 E2E는 추가하지 않았습니다.