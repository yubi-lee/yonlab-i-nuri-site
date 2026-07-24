# 프로젝트 개요와 범위

## 목적

YOnLearn Hub는 교육자가 AI 교육 자료를 탐색하고, 조직 맥락을 바탕으로 역량을 진단하며, 근거가 남는 학습 활동으로 이어지도록 돕는 YOnLab의 지식·학습 플랫폼입니다. 기존 공개 포털은 자료·공지·FAQ·문의·관리자 CMS를 제공하고, AI training platform slice는 조직 단위 학습 흐름을 추가합니다.

## 진행 과정 요약

1. 공개 포털과 FastAPI/PostgreSQL 기반을 정리했습니다.
2. 인증·권한·콘텐츠·검색·문의·관리자 흐름을 RC1 범위로 안정화했습니다.
3. production target design package를 `docs/design/`에 정리했습니다.
4. 조직, 교사 프로필, 진단 세션, 학습 경로, 문서 노드, 근거 검색, 보고서·파일럿 지표를 하나의 독립적인 API 경계로 연결했습니다.
5. 프런트엔드 `/training` 화면과 AI Gateway 정책 경계를 추가했습니다.
6. 설계 검증, Python/TypeScript 테스트, E2E, Docker 통합 검증을 통과시켰습니다.

## 현재 구현 범위

| 영역 | 현재 결과 | 상태 |
|---|---|---|
| 공개 포털 | 자료·공지·FAQ·통합검색·문의 | `IMPLEMENTED` |
| 인증·권한 | Bearer access token, member/admin guard | `IMPLEMENTED` |
| 조직 학습 | 조직·멤버·동의·교사 프로필 | `IMPLEMENTED` |
| AI 진단 | 세션·응답·SSE 이벤트·결과 점수 | `IMPLEMENTED` |
| 학습 | 학습 경로·등록·활동·개인 학습 조회 | `IMPLEMENTED` |
| 문서 AI | text/Markdown/HTML 및 제한된 HWPX 추출, 문서 노드, lexical search | `IMPLEMENTED` |
| 근거 답변 | tenant-scoped 검색·locator citation·no-answer | `IMPLEMENTED` |
| 운영 지표 | 보고서와 pilot metric API | `IMPLEMENTED` |
| 외부 AI provider | 독립 AI Gateway 정책 경계와 deterministic adapter | `DESIGN_TARGET` |
| PDF/OCR/HWP binary | production converter·OCR·golden corpus | `BLOCKED_UNTIL_PRODUCTION_EVIDENCE` |
| 운영 보안 | MFA·RLS·회전 refresh session·SPIRE mTLS | `DESIGN_TARGET` |

## 사용자 역할

- **방문자**: 공개 자료와 검색을 보고 문의를 제출합니다.
- **교사/학습자**: 조직을 선택하고 진단·학습·문서 근거 검색을 사용합니다.
- **기관 관리자**: 조직 멤버와 운영 지표를 관리하는 역할로 확장됩니다.
- **콘텐츠 검수자**: 문서·근거·AI 결과의 품질과 저작권을 확인합니다.
- **시스템 운영자**: 배포, health, 로그, 백업, 복구, 릴리스 gate를 담당합니다.

## 범위를 넘는 것으로 오해하면 안 되는 것

- deterministic 점수와 lexical 검색은 실제 AI 모델 평가·임상적 진단·전문가 판단을 대신하지 않습니다.
- 현재 구현을 production-ready로 표시하려면 외부 provider, OCR/PDF converter, RLS, MFA, 개인정보·약관 검토, 운영 수용 증거가 추가되어야 합니다.
- `reference/inuri-public/`는 분석용이며 제품 코드·문서·캡처에 원문 자산을 재사용하지 않습니다.
