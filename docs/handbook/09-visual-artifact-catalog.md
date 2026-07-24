# 시각 자료 카탈로그

## 다이어그램

| 자료 | 설명 | 용도 |
|---|---|---|
| [system-context.drawio.png](../diagrams/system-context.drawio.png) | 사용자·Web·API·DB·AI Gateway·문서 경계 | 신규 구성원 설명 |
| [deployment-topology.drawio.png](../diagrams/deployment-topology.drawio.png) | Docker Compose와 production trust boundary | 배포 검토 |
| [training-flow.drawio.png](../diagrams/training-flow.drawio.png) | 로그인부터 진단·학습·활동까지 | 사용자 교육 |
| [document-grounded-search.drawio.png](../diagrams/document-grounded-search.drawio.png) | 문서 등록·처리·citation 검색 | 콘텐츠 검수 |
| [domain-data-model.drawio.png](../diagrams/domain-data-model.drawio.png) | 조직·진단·학습·문서 핵심 entity | 개발·DB 검토 |

각 PNG에는 draw.io XML이 포함되어 있으며, 편집이 필요하면 동명의 `.drawio` 파일을 draw.io Desktop 또는 diagrams.net에서 엽니다.

## 동작 캡처

현재 캡처는 seed된 fictional content와 합성 계정만 사용합니다.

| 캡처 | 화면·상태 | 대체텍스트 |
|---|---|---|
| [home-desktop.png](../assets/screenshots/home-desktop.png) | 1440×900 공개 홈 | YOnLearn Hub 홈에서 검색창과 추천 자료 카드가 보이는 데스크톱 화면 |
| [home-tablet.png](../assets/screenshots/home-tablet.png) | 768×1024 공개 홈 | YOnLearn Hub 홈의 태블릿 레이아웃과 주제 탐색 카드 |
| [home-mobile.png](../assets/screenshots/home-mobile.png) | 390×844 공개 홈 | YOnLearn Hub 홈의 모바일 레이아웃과 메뉴 진입 화면 |
| [training-guard.png](../assets/screenshots/training-guard.png) | 비로그인 `/training` guard | 로그인 안내와 로그인 링크가 표시된 AI 학습 접근 제한 화면 |
| [training-hub.png](../assets/screenshots/training-hub.png) | 로그인 후 AI 학습 | 조직 공간·역량 진단·추천 학습·근거 문서 패널이 세로로 배치된 화면 |

캡처는 설명용 보조 증거입니다. 실제 릴리스 판정에는 해당 commit·image·viewport·브라우저·실행 시각이 기록된 E2E/접근성 evidence가 필요합니다. 정상 캡처만으로 접근성·오류 상태·보안 검증을 대체하지 않습니다.
