# Architecture

YOnLearn Hub is a modular monolith. React Router and TanStack Query call the versioned FastAPI boundary. FastAPI validates input with Pydantic, enforces bearer-token roles, and persists typed SQLAlchemy models in PostgreSQL. Nginx serves the production client and proxies API traffic.

Authentication issues a short-lived access token. This MVP includes only a refresh-session hint; production must replace it with hashed rotating sessions and CSRF protection. Search currently uses parameter-bound SQL ILIKE behind a separate endpoint so PostgreSQL FTS or OpenSearch can replace it later.
