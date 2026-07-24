# 보안·개인정보·저작권 주의사항

## 절대 저장·커밋하지 않는 것

- `.env`의 실제 secret, JWT signing key, provider credential
- 실제 사용자·아동·가족·교직원 개인정보
- 관리자 초기 비밀번호와 shell history
- reference site의 원문, 이미지, 아이콘, 첨부, distinctive layout
- 실사용자 화면 캡처와 운영 DB dump
- 승인되지 않은 모델·prompt·학습 데이터

## 현재 코드의 보안 경계

- API는 `/api/v1` 아래에 있고 health endpoint는 `/health/*`에 남습니다.
- Pydantic 입력 검증, ORM parameter binding, role guard, safe error, CORS allowlist, security headers를 사용합니다.
- 문서 검색은 organization scope를 기준으로 제한하고 citation locator를 반환합니다.
- storage와 search는 교체 가능한 service boundary 뒤에 있습니다.
- 모든 외부 장애 보고에는 `X-Request-ID`를 사용하되 token과 개인정보를 함께 전송하지 않습니다.

## 아직 production 전 보완해야 하는 항목

- hashed rotating refresh session과 CSRF 방어
- MFA, email verification, reset provider, distributed login throttling
- PostgreSQL row-level security와 실제 tenant isolation 검증
- object storage·malware scanning·retention/deletion automation
- 외부 AI egress 정책, 모델·prompt·schema registry, provider DPA
- 라이선스가 있는 Windows HWP converter, OCR, golden corpus, 격리 실행과 attestation
- 개인정보·이용약관·보존·삭제 정책의 법무·운영 승인

## AI 결과의 안전한 사용

- 진단 결과는 학습 지원용 참고 정보이며 전문가·교사 판단을 대체하지 않습니다.
- 문서에 없는 내용을 보충 추정하지 않고 no-answer를 유지합니다.
- 답변을 게시·공유하기 전 citation locator와 원문 권리를 확인합니다.
- 실제 고위험 의사결정에 자동 점수·추천을 직접 사용하지 않습니다.

## 저작권과 clean-room

reference 분석은 도메인 이해에만 사용합니다. 제품 문서·코드·화면·이미지는 독립적으로 작성하며, 참고 사이트의 문구·색상·레이아웃·이미지·아이콘·파일명·콘텐츠를 복사하지 않습니다.
