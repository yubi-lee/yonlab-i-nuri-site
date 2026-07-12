# Completion gap audit

Audited 2026-07-12 from the repository and fresh file inspection. Status vocabulary: Complete, Partial, Missing, Environment-blocked, Verified, Unverified.

| Area | Status | Evidence |
|---|---|---|
| Public routes | Partial, Verified | Home, about, resources, resource detail, search, login, register, inquiry exist. Notice/article/FAQ dedicated routes are absent. |
| Member routes | Partial, Verified | Protected My Page route exists, but it renders a placeholder rather than bookmark and inquiry data. |
| Admin routes | Missing, Verified | Only one `/admin` dashboard route exists. Entity list/create/edit/delete screens are absent. |
| Public API integration | Partial, Verified | Resource/search/inquiry APIs are connected. Notice/article/FAQ content is not surfaced in dedicated UI. |
| Resource CMS | Partial, Verified | Create API only. No admin list/detail/update/archive UI or APIs. |
| Notice, Article, FAQ, Category, Tag CMS | Missing, Verified | No administrator CRUD endpoints or UI. |
| Inquiry CMS | Partial, Verified | Status update endpoint exists; admin list/filter/detail UI and API are absent. |
| User CMS | Missing, Verified | No list/search/role/disable APIs or UI. |
| Access token | Partial, Verified | Short-lived signed JWT exists; client stores it in localStorage and has no expiry recovery. |
| Refresh session | Missing, Verified | Model exists, but login writes only a constant `refresh_hint` cookie. No session row, rotation, reuse detection, logout or all-device logout. |
| Password reset | Missing, Verified | No token model, mail adapter, endpoints, expiry or reuse protection. |
| Storage adapter | Missing, Verified | Attachment model exists; no StorageAdapter, LocalStorageAdapter, upload/download/delete endpoints or validation. |
| Alembic/model match | Partial, Unverified | Migration calls metadata `create_all`; no explicit revision operations or empty-schema comparison test. |
| Backend tests | Partial, Verified | Three tests cover health, registration duplicate, failed login and inquiry consent only. |
| Frontend tests | Missing, Verified | One hero render test; critical auth, forms, CMS, loading/error, bookmark and mobile flows are untested. |
| Playwright project tests | Partial, Unverified | Two specs exist. Browser binaries and project runner have not been successfully verified. |
| In-app browser | Environment-blocked, Verified | Codex Node browser runtime previously failed while applying Windows sandbox ACLs. This is separate from project Playwright. |
| Docker integration | Environment-blocked, Verified | Docker command was not installed in the prior environment. Static Compose review still required. |
| Documentation accuracy | Partial, Verified | README and AGENTS contain encoding damage and describe capabilities not fully implemented. |
| Git hygiene | Partial, Verified | Repository has no commits and all project files are untracked. `.env`, databases, storage, raw references and screenshots are ignored; generated egg-info and tsbuildinfo are currently visible. |
| Placeholders/mocks | Partial, Verified | My Page is placeholder copy; refresh cookie is a constant hint; seed data is intentionally synthetic. No TODO markers in product source. |

## RC1 blockers

1. Complete database-backed refresh rotation, logout, reset flow and client expiry recovery.
2. Complete administrator CRUD APIs and usable mobile admin UI for all eight entity types.
3. Complete storage adapter and file-security path with tests.
4. Expand backend/frontend tests around critical risks.
5. Diagnose and run project Playwright independently of the in-app browser.
6. Add Docker pending verification workflow when Docker is unavailable.
7. Replace stale or encoding-damaged documentation and re-run every quality gate.


## RC1 closeout update (2026-07-12)

Lifespan, UTC policy, integrated verification, CMS evidence, and first-commit review are complete. Local code gates and Playwright pass. Docker remains environment-blocked; the external Starlette TestClient warning is documented and not suppressed.
