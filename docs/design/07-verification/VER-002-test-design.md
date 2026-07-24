# VER-002 Test Design

## Functional Test Areas

| Area | Test focus |
|---|---|
| Public portal | Navigation, resource browsing, content browsing, search, downloads, inquiry submission |
| Diagnosis scoring | Strict request validation, deterministic score response, safe errors, correlation, and no raw evidence persistence |
| User and member | Registration, login, profile, bookmarks, inquiry history, inactive-account denial |
| Authentication | Access token expiry, refresh rotation, replay detection, logout, password reset |
| CMS | Eight entity types, lifecycle rules, audit records, authorization denial |
| Files | Upload validation, object storage, signed access, deletion, reconciliation |
| Email | Template rendering, reset links, retry policy, bounce and complaint events |
| Search | Query parsing, filters, ranking, visibility, pagination, indexing lifecycle |
| Health | Liveness, readiness, dependency failure behavior |

## Non-Functional Test Areas

| Area | Test focus |
|---|---|
| Security | RBAC, IDOR, injection, XSS, CSRF, CORS, file attacks, secret leakage |
| Privacy | Consent, data minimization, log redaction, access restrictions |
| Accessibility | Keyboard, focus, landmarks, names, contrast, responsive layout |
| Performance | API latency, search latency, list pagination, asset budgets |
| Scalability | Pagination, provider boundaries, index behavior, storage scale |
| Reliability | Transaction rollback, provider timeout, retry, idempotency |
| Observability | Correlation IDs, metrics, alerts, audit records |
| Backup/restore | Database restore, object reconciliation, recovery evidence |
| Deployment | Migrations, controlled rollout, readiness, rollback |

## Verification Method Matrix

| Method | Purpose | Input or precondition | Execution | Expected result | Pass criterion | Evidence form |
|---|---|---|---|---|---|---|
| unit | Prove isolated domain rules | Function, service, or validator with synthetic data | Run deterministic unit test suite | Rule output matches specified result | All assertions pass | Test report and coverage summary |
| component | Prove component behavior behind its boundary | Component dependencies replaced by test doubles or contract fixtures | Run component tests for CDD responsibilities | Component honors provided and consumed interfaces | All component scenarios pass | Component test report |
| contract | Prove provider interface compatibility | Storage, email, search, or observability adapter contract fixtures | Run adapter contract tests against provider or simulator | Adapter handles success, timeout, retry, and error cases | Contract suite passes | Contract test log |
| API integration | Prove HTTP contract and transaction behavior | API runtime, database, and controlled configuration | Call API endpoints with valid and invalid cases | Responses, errors, auth, and audit match ICD | Endpoint scenarios pass | API integration report |
| database migration | Prove schema evolution and constraints | Empty database and representative upgraded database | Apply migrations and run constraint checks | Schema reaches target revision and constraints hold | Migration command and checks pass | Migration log and schema report |
| authentication security | Prove credential, session, reset, and replay controls | Test accounts, token fixtures, time-control support | Execute login, refresh, replay, reset, logout, and expiry scenarios | Invalid and replayed credentials are rejected; valid flows rotate safely | Security scenarios pass | Auth security report |
| authorization | Prove RBAC, ownership, and visibility controls | Users with different roles and ownership states | Attempt allowed and denied operations | Allowed calls succeed and denied calls fail safely | No privilege bypass found | Authorization test report |
| frontend | Prove client behavior and accessibility hooks | Built or test-rendered frontend with API fixtures | Run component and interaction tests | Forms, state, errors, and focus behavior match design | Frontend suite passes | Frontend test report |
| E2E | Prove critical user journeys | Running system with synthetic data | Drive browser workflows for public, member, and admin paths | User-visible workflows complete and errors are understandable | Journey suite passes | Browser test report and screenshots when useful |
| accessibility | Prove inclusive interaction | Representative pages at supported breakpoints | Run automated checks and keyboard/manual review | Landmarks, labels, contrast, focus, and keyboard paths meet criteria | No blocking accessibility defects | Accessibility report |
| performance | Prove latency and asset budgets | Production-like dataset and runtime profile | Run load, search, API, and frontend budget tests | Metrics stay within approved budgets | Budgets met under stated profile | Performance report |
| security | Prove threat controls | Threat model, dependency inventory, and attack fixtures | Run static, dependency, dynamic, and abuse-case tests | Controls resist defined threats | No unresolved critical or high findings | Security report |
| backup/restore | Prove recoverability | Backup artifacts and restore environment | Restore database and object storage, then run consistency checks | Restored system passes integrity checks | Recovery meets approved objectives | Drill record |
| deployment | Prove rollout safety | Build artifact, migration, deployment target | Run build, migrate, deploy, readiness, and smoke sequence | Release reaches ready state | Deployment gate passes | Release evidence |
| rollback | Prove reversibility | Deployed release and previous approved artifact | Execute rollback plan and smoke checks | Previous compatible service state is restored | Rollback gate passes | Rollback drill record |
| disaster recovery | Prove response to severe provider or data incidents | DR scenario and approved recovery objective | Execute documented recovery sequence | Service and data integrity are restored within approved objective | DR drill passes | DR evidence package |
| acceptance review | Prove requirement and design satisfaction | Completed traceability and review package | Review requirements, design, risks, and evidence | Review disposition and conditions are recorded | CDR disposition accepted | Signed review record |
## Requirement Coverage

All requirement IDs from `REQ-F-001` through `REQ-F-018` and `REQ-NF-001` through `REQ-NF-015` require at least one automated or review-based verification method.
The diagnosis score API is covered by backend/tests/test_diagnosis_api.py:

- valid evidence.v1 input returns the deterministic golden score and preserves X-Request-ID
- unknown fields and mismatched anchor counts return a safe 422 validation envelope
- the response contains no quoted span or raw evidence and explicitly reports persisted: false

## Test Data

Test data is synthetic, non-secret, and independent from reference-site material. Personal-data scenarios use generated identities and controlled retention checks.
