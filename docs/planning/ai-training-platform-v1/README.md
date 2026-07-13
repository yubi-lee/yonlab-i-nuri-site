# YOnLab 보육교사 맞춤형 연수혁신 AI 플랫폼 목표 설계 문서셋

문서 기준일: 2026-07-13  
설계 상태: 승인된 목표 기준선  
서비스 형태: YOnLab 독립 실행형 플랫폼 + 누리과정 포털 연계 Adapter  
구현 원칙: 공개 인터페이스와 추상적 사용자 흐름만 참고하는 Clean-room 개발

## 1. 문서 목적

본 문서셋은 제안요청서와 YOnLab 제안서를 기준으로 최종 서비스의 기능, 화면, 데이터, AI, 문서지능, 보안, 운영, 검증 및 구축 절차를 정의한다. 모든 문서는 완성될 목표 시스템을 일관되게 기술하며 구현 상태를 본문에서 구분하지 않는다.

## 2. 설계 기준

- React·TypeScript 기반 반응형 사용자 포털과 관리자 콘솔
- FastAPI 기반 모듈형 API 및 AI orchestration
- PostgreSQL+pgvector, Redis, 비동기 worker, Object Storage
- OpenAI와 내부 sLLM을 함께 지원하는 Hybrid AI Gateway
- AI 대화 기반 역량진단과 결정적 rubric scoring
- 5~6종 대표 페르소나의 확률적 분석과 사용자 수정
- 추천 연수, 기초-심화-적용 학습경로, 성과 리포트 연계
- HWP/HWPX 구조 보존형 Document AI와 grounded RAG
- HWPX canonical draft와 격리된 HWP 변환 worker
- 데이터 등급, 동의, 개인정보 최소화, 감사 및 모델 평가
- 200명×2회 시범운영과 전문가 FGI 기반 품질 개선

## 3. 문서 목록

| 번호 | 문서 | 역할 |
|---|---|---|
| 00 | [원천·의사결정 기준선](00-source-decision-baseline.md) | RFP·제안서·승인결정 우선순위와 성과목표 |
| 01 | [목표 범위와 요구사항 추적성](01-requirements-traceability.md) | 60개 RFP 요구사항, 시스템 요구, 검증 추적 |
| 02 | [사용자·기능·화면 설계](02-functional-screen-design.md) | 역할, 사용자 여정, 화면 IA, 상태·행동 설계 |
| 03 | [시스템 아키텍처와 CDD/CDR](03-system-architecture-cdd-cdr.md) | 구성도, 배포, 컴포넌트 책임, 결정사항 |
| 04 | [AI 역량진단·페르소나·추천 설계](04-ai-diagnosis-persona-recommendation.md) | 대화진단, scoring, 페르소나, 추천·성과 연계 |
| 05 | [Document AI·HWP RAG 설계](05-document-ai-hwp-rag.md) | HWP/HWPX 처리, 구조화, 검색, 근거, 초안 생성 |
| 06 | [AI Gateway·모델 선정 설계](06-ai-gateway-model-selection.md) | OpenAI/sLLM, routing, evaluation, fallback |
| 07 | [데이터·API·인터페이스 설계](07-data-api-interface-design.md) | 엔터티, ERD, API 계약, 이벤트·외부 연계 |
| 08 | [보안·개인정보·운영 설계](08-security-privacy-operations.md) | trust boundary, RBAC, consent, 배포·백업·관측 |
| 09 | [시험 절차서와 수용 기준](09-test-procedure-acceptance.md) | 단위·통합·AI·HWP·보안·성능·시범운영 시험 |
| 10 | [구축·전환·산출물 계획](10-delivery-implementation-plan.md) | 180일 단계계획, 산출물, Gate, 운영전환 |
| 11 | [Codex 일괄 구현 프롬프트](11-codex-one-shot-implementation-prompt.md) | 문서 기준 구현·검증·GitHub 반영 지시 |

별도 분석 근거:

- [AI Gateway 및 UniClaudeProxy 재사용 설계](../AI-Gateway-UniClaudeProxy-Reuse-Design.md)

## 4. 시스템 범위

### 사용자 서비스

- 회원·교사 프로필과 개인정보 동의
- AI 역량진단 챗봇
- 진단 근거·점수·불확실도 확인 및 정정
- 교사 페르소나 확인 및 수정
- 맞춤형 연수 추천과 학습경로
- 학습 이력·실천 과제·사후 진단
- 개인 성과 리포트
- HWP/HWPX/PDF 자료 검색·질의응답·요약
- 출처·페이지·표·셀 근거 확인
- 승인 템플릿 기반 HWPX 초안 생성
- 문의·피드백·접근성 지원

### 관리자·전문가 서비스

- 콘텐츠·연수·역량체계·루브릭 관리
- 페르소나·추천규칙·학습경로 관리
- 문서 수집·변환·OCR·검수·게시
- 프롬프트·모델·Schema·평가셋 관리
- AI 품질·비용·지연·fallback 관제
- 사용자·기관·권한·동의 관리
- 시범운영·FGI·개선요청 관리
- 개인·기관 성과 대시보드와 보고서
- 감사로그·보안·운영 상태 확인

## 5. 비범위와 통제

- 의료·정신건강 진단
- 교사 인사평가·채용·징계 결정
- AI가 근거 없이 확정하는 역량 점수
- 권리 검토되지 않은 포털 원문·이미지·첨부파일 복제
- 검수 없이 자동 배포되는 HWP/HWPX 문서
- 민감 데이터의 무조건적인 외부 AI 전송
- 모델 공급자 이름과 버전을 업무 코드에 직접 고정하는 구현

## 6. 완료 정의

본 설계는 다음 조건을 모두 충족할 때 구현 완료로 판정한다.

1. 모든 필수 요구사항이 구현 항목과 시험 사례에 연결됨
2. 사용자·관리자 핵심 여정이 데스크톱·태블릿·모바일에서 통과
3. 진단 전문가 일치도 0.80 이상
4. 추천 적합도 85% 이상
5. RAG Top-5 검색 정확도 90% 이상
6. 출처 제시율 95% 이상
7. Restricted 데이터의 외부 전송 0건
8. HWP/HWPX 구조·인용·초안 생성 시험 통과
9. 보안·접근성·성능·백업복구·롤백 시험 통과
10. 200명×2회 시범운영 결과와 개선 반영률 80% 이상
