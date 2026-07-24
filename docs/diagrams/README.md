# 다이어그램 산출물

각 다이어그램은 Mermaid 원천에서 draw.io native XML로 변환한 편집 가능한 `.drawio`와 XML이 내장된 `.drawio.png`를 함께 제공합니다. PNG는 문서·검토 자료용이며, 구조를 수정할 때는 `.drawio` 파일을 엽니다.

| 파일 | 종류 | 설명 |
|---|---|---|
| `system-context.drawio` | 컨텍스트·구조도 | 사용자에서 Web, API, DB, AI Gateway, Document AI, observability로 이어지는 경계 |
| `deployment-topology.drawio` | 배포·구성도 | Docker Compose verification boundary, secret source, backup, monitoring |
| `training-flow.drawio` | 사용자 플로우차트 | 로그인→조직→진단→학습→활동과 근거 문서 흐름 |
| `document-grounded-search.drawio` | 처리 플로우차트 | 문서 등록→처리→노드→검색→citation/no-answer |
| `domain-data-model.drawio` | ER 다이어그램 | 조직·진단·학습·문서·보고서 핵심 관계 |

원천 Mermaid 파일은 변환 완료 후 저장소에 남기지 않고, draw.io 산출물과 설명 문서만 배포합니다. 다이어그램 변경 후 PNG와 `.drawio`가 같은 변경에서 갱신됐는지 확인합니다.
