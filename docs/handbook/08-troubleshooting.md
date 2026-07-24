# 문제 해결

## API가 시작되지 않음

1. `DATABASE_URL`, `JWT_SECRET`, `CORS_ORIGINS`가 설정됐는지 확인합니다.
2. PostgreSQL health를 확인합니다.
3. `backend` 디렉터리에서 Alembic migration을 실행합니다.
4. 전체 stack을 재시작하기 전에 backend 로그와 `X-Request-ID`를 보존합니다.

```powershell
docker compose ps
docker compose logs --tail 200 backend postgres
docker compose exec backend python -m alembic -c alembic.ini upgrade head
```

## 프런트엔드에서 API 오류

- `VITE_API_URL`이 browser에서 접근 가능한 주소인지 확인합니다.
- backend CORS allowlist에 frontend origin이 정확히 포함됐는지 확인합니다.
- browser Network에서 status, response request ID, endpoint를 확인합니다.
- token을 URL·스크린샷·로그에 복사하지 않습니다.

## 로그인 실패

- demo 계정과 production bootstrap 계정을 구분합니다.
- password policy와 seed 완료 여부를 확인합니다.
- 관리자 경로는 member token으로 접근할 수 없습니다.
- 실패 로그에 비밀번호·token을 남기지 않습니다.

## `/training`에서 기능이 보이지 않음

- 로그인 후 접근했는지 확인합니다.
- organization을 생성·선택했는지 확인합니다.
- API 응답의 request ID와 organization ID를 함께 확인합니다.
- 다른 organization의 document가 보이면 즉시 검색 기능을 중지하고 보안 incident로 처리합니다.

## 검증 gate 실패

| 실패 | 우선 확인 |
|---|---|
| 설계 문서 gate | ID 중복, 상대 링크, Mermaid fence, 절대 경로, placeholder |
| Ruff/pytest | 첫 실패 traceback과 migration 상태 |
| TypeScript/Vite | API schema와 import path |
| Playwright | 포트 점유, seed 계정, frontend/API origin |
| Docker | Docker daemon, image build, readiness, cleanup |
| secret scan | 실제 값이 아닌 fixture allowlist인지, 문서에 secret이 들어갔는지 |

자동 gate가 `BLOCKED`를 반환하면 성공으로 취급하지 않습니다. 원인과 환경 fingerprint를 기록한 뒤 필요한 실행 환경을 확보하고 다시 수행합니다.
