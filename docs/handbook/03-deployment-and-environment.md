# 배포와 환경 구성 가이드

## 환경별 원칙

| 환경 | 목적 | 허용 데이터 | 기본 방식 |
|---|---|---|---|
| Local | 개발·디버깅 | synthetic/demo only | `.venv` + Vite + local DB |
| Verification | 자동 gate | synthetic fixture only | `scripts/verify.ps1` |
| Demo | 기능 시연 | YOnLab 작성 fictional seed | Docker Compose |
| Production candidate | 운영 전 검증 | 승인된 테스트 데이터 | immutable image + migration + smoke |
| Production | 외부 서비스 | 승인된 개인정보·콘텐츠 | secret manager, TLS, PostgreSQL, backup |

## 로컬 실행

```powershell
Copy-Item .env.example .env
.\scripts\setup.ps1
.\scripts\seed.ps1
.\scripts\dev.ps1
```

접속 주소:

- Web: `http://localhost:5173`
- API: `http://localhost:8000`
- Swagger: `http://localhost:8000/docs`
- Health: `/health`, `/health/live`, `/health/ready`, `/ready`

## Docker Compose 실행

`.env`에는 최소한 `JWT_SECRET`을 채웁니다. 데모 계정 값은 데모 환경에만 사용합니다.

```powershell
docker compose up --build -d
docker compose exec backend python -m alembic -c alembic.ini upgrade head
docker compose exec backend python -m app.seed
Invoke-WebRequest http://localhost:8000/health/ready
Invoke-WebRequest http://localhost:8080
```

실제 운영에서는 demo seed 계정과 fictional content를 제거하거나 격리하고, 보호된 secret manager에서 값을 주입합니다.

## 운영 배포 순서

1. 승인된 commit/tag와 image digest를 고정합니다.
2. production 환경 파일을 Git 외부에 배치하고 `scripts/verify-production-readiness.ps1`로 값의 존재·형식만 확인합니다.
3. PostgreSQL 백업과 복구 가능성을 확인합니다.
4. 이미지 build/scan 후 migration을 트래픽 이전에 실행합니다.
5. backend readiness와 frontend 응답을 확인합니다.
6. 관리자 bootstrap·rotation 결과를 operations log에 기록합니다.
7. 로그인, 검색, 자료 상세, 문의, 관리자 경로를 smoke test합니다.
8. 이상이 있으면 애플리케이션을 직전 승인 image로 되돌리고, schema 변경이 포함된 경우 [백업·복원 runbook](../operations/backup-restore.md)을 따릅니다.

## 검증 명령

```powershell
.\scripts\verify-design-docs.ps1
.\scripts\verify.ps1
.\scripts\verify-production-readiness.ps1 -TemplateMode -SkipHttp
```

`verify.ps1`는 Docker가 실행 중일 때 Docker build·migration·seed·health·restart·persistence·log scan까지 수행합니다. Docker가 없으면 성공으로 간주하지 않고 `BLOCKED`로 처리합니다.

## 구성 주의

- `CORS_ORIGINS`는 실제 HTTPS frontend origin만 허용합니다.
- `JWT_SECRET`은 최소 32자 이상의 고엔트로피 값으로 설정합니다.
- `VITE_API_URL`은 browser가 접근 가능한 API base URL이어야 합니다.
- `ADMIN_EMAIL`·`ADMIN_PASSWORD`는 demo seed용이며 production 관리자 초기값과 혼동하지 않습니다.
- 실제 email provider, OCR/PDF converter, object storage를 연결하기 전에는 해당 기능을 production capability로 표시하지 않습니다.
