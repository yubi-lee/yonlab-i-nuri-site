# ERD

```mermaid
erDiagram
  USER ||--o{ REFRESH_SESSION : owns
  USER ||--o{ BOOKMARK : saves
  RESOURCE ||--o{ BOOKMARK : saved
  CATEGORY ||--o{ RESOURCE : classifies
  RESOURCE }o--o{ TAG : tagged
  RESOURCE ||--o{ RESOURCE_ATTACHMENT : contains
  USER ||--o{ INQUIRY : submits
  USER ||--o{ AUDIT_LOG : acts
```
