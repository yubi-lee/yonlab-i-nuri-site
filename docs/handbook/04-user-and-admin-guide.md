# 사용자·관리자 사용법

## 방문자

1. 홈에서 키워드를 입력하거나 주제 링크를 선택합니다.
2. 자료실에서 자료를 열고 요약·태그·첨부 정보를 확인합니다.
3. 통합검색에서 자료·공지·인사이트·FAQ를 함께 검색합니다.
4. 문의 페이지에서 이메일, 제목, 내용, 답변용 동의를 입력합니다.

## 교사·학습자

1. `로그인` 또는 `회원가입`으로 인증합니다.
2. `AI 학습`으로 이동해 조직을 만들거나 조직 공간을 선택합니다.
3. `진단 시작`에서 목표를 입력합니다.
4. 현장 응답을 저장하고 `진단 완료`를 선택합니다.
5. 추천 학습 카드에서 `학습 등록`을 선택합니다.
6. 근거 문서의 제목과 텍스트를 등록하고 `처리`를 선택합니다.
7. `근거 검색`에 질문 또는 키워드를 입력하고 문서 제목·locator를 확인합니다.
8. 근거가 없을 때는 결과를 추정하지 않고 `확인 가능한 근거가 없습니다.` 상태를 사용합니다.

## 조직·데이터 경계

- 조직 ID는 문서·진단·학습 등록·검색 요청에 함께 전달합니다.
- 다른 조직의 문서와 근거가 검색 결과에 섞이지 않아야 합니다.
- 운영 데이터에 실제 아동·가족·교직원 개인정보를 입력하지 않습니다.
- AI 진단 점수는 학습 추천을 위한 보조 지표이며 인사·의료·입학·징계 판단에 직접 사용하지 않습니다.

## 기관 관리자·콘텐츠 검수자

현재 RC1 관리자 화면은 콘텐츠·카테고리·문의 운영을 중심으로 합니다. 조직별 집계·문서 승인·AI 정책·파일럿 지표 운영은 API와 설계 경계를 기준으로 확장 중입니다.

- 콘텐츠 등록 전 제목·요약·태그·저작권 상태를 확인합니다.
- 문서 처리 결과는 `processed`, `failed`, `review_required` 상태를 확인합니다.
- citation locator가 없는 답변은 승인하지 않습니다.
- 모델·prompt·schema·rubric 변경은 코드 변경과 별개로 평가·릴리스 기록을 남깁니다.

## API 사용 예

보호된 API는 `Authorization: Bearer <access_token>`을 사용하고, 모든 응답의 `X-Request-ID`를 장애 추적에 보존합니다.

```powershell
$headers = @{ Authorization = "Bearer $accessToken" }
Invoke-RestMethod -Headers $headers -Uri "$api/api/v1/organizations"
Invoke-RestMethod -Headers $headers -Uri "$api/api/v1/learning/paths"
Invoke-RestMethod -Headers $headers -Uri "$api/api/v1/knowledge/search?organization_id=$organizationId&q=수업"
```

정확한 request/response schema는 [ICD-001](../design/04-interfaces/ICD-001-api-interface.md)과 실행 중 Swagger `/docs`를 기준으로 확인합니다.
