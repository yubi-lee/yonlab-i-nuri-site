# 운영 런북

## 일상 점검

```powershell
Invoke-WebRequest http://localhost:8000/health/ready
docker compose ps
docker compose logs --tail 100 backend frontend
```

확인 항목:

- backend와 PostgreSQL health가 정상인지 확인합니다.
- 최근 로그에 secret, token, 개인정보가 출력되지 않는지 확인합니다.
- 처리 중인 document job, 실패 job, 검색 zero-result가 급증하지 않는지 확인합니다.
- 최근 backup timestamp와 보존 정책을 확인합니다.

## 백업과 복원

```powershell
.\scripts\backup-postgres.ps1
.\scripts\restore-postgres.ps1 -BackupFile .\backups\<backup-file>.dump
```

복원은 파괴적입니다. 운영 DB가 아닌 격리 프로젝트에서 먼저 수행하고, [백업·복원 문서](../operations/backup-restore.md)의 `RESTORE` 확인과 복구 검증을 지킵니다.

## 장애 대응 순서

1. 시간(UTC), 환경, commit/image digest, endpoint, `X-Request-ID`를 기록합니다.
2. `/health/ready`와 `docker compose ps`로 장애 범위를 좁힙니다.
3. 최근 배포·migration·구성 변경 여부를 확인합니다.
4. 로그에 원문 개인정보나 secret이 없는지 확인하며 필요한 부분만 redacted capture합니다.
5. 영향 기능을 안전한 degraded mode로 제한합니다. 근거 없는 AI 답변을 fallback으로 만들지 않습니다.
6. 애플리케이션 image를 직전 승인 버전으로 rollback합니다.
7. 데이터 손상이 의심되면 쓰기를 중지하고 backup/restore owner를 호출합니다.
8. 복구 후 로그인·검색·문서·문의·관리자 smoke와 persistence를 확인합니다.
9. 원인, 영향, 조치, 재발 방지와 후속 issue를 기록합니다.

## 문서 처리·근거 검색 장애

| 증상 | 조치 |
|---|---|
| 문서가 `failed` | MIME·내용·크기·처리 job 로그를 확인하고 원본을 재전송하지 말고 hash로 대조 |
| citation이 없음 | 검색어·조직 ID·처리 상태를 확인하고 근거 없는 응답을 게시하지 않음 |
| 결과가 다른 조직에 노출 | 즉시 검색 endpoint를 차단하고 tenant scope·권한 로그를 보존 |
| HWP/PDF 변환 실패 | 현재 구현의 adapter 한계를 확인하고 production converter 없이 성공 처리하지 않음 |

## 백업 보존과 운영 기록

운영 기록에는 operator, UTC timestamp, commit/image, migration revision, 환경 설정 source, backup hash, health 결과, rollback 판단을 남깁니다. 실제 개인정보·원문 문서·secret은 운영 기록에 복사하지 않습니다.
