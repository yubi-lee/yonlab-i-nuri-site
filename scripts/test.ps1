$ErrorActionPreference = "Stop"
& .\.venv\Scripts\ruff.exe check backend
& .\.venv\Scripts\python.exe -m pytest backend\tests -q
npm run lint --prefix frontend
npm run typecheck --prefix frontend
npm run test --prefix frontend
npm run build --prefix frontend
