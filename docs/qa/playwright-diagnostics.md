# Playwright diagnostics

- Node 24.18.0, npm 11.18.0, Playwright 1.61.1.
- Project and Playwright package ACLs allow normal read/execute access.
- Root cause: the default Playwright browser cache contained no browser binary.
- Remediation: `npx playwright install chromium` installed Chromium 1228, headless shell, FFmpeg, and WinLDD in the default user cache.
- Result: Chromium launches and the complete project E2E suite passes. This is distinct from the Codex in-app browser host ACL, which is outside this repository's control.