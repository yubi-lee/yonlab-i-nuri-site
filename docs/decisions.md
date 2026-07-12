# Decisions

1. Modular monolith for fewer deployment edges with replaceable search/storage boundaries.
2. Search-led center hero because finding applicable knowledge is the primary intent.
3. Independent navy/teal system to communicate trust without reproducing the reference.
4. PostgreSQL in Docker; SQLite only as local/test fallback.
5. Access tokens now; production refresh rotation is an explicit release gate.
