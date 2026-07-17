# Nested Windows Job Object Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Windows runner detect nested Job Object execution and preserve fail-closed isolation for Codex Implement while allowing only explicitly allowlisted read-only probes to continue when `AssignProcessToJobObject` returns `ERROR_ACCESS_DENIED`.

**Architecture:** Keep process creation on direct `ProcessStartInfo` with no shell, exact executable paths, bounded stdout/stderr capture, and hard timeouts. Add an explicit isolation mode to the native-process helpers: `Required`, `BestEffortReadOnly`, and `DisabledForPolicySelfTest`; only the second mode may return an unassigned process, and only for a validated read-only probe. Add a pure policy-fixture assertion so the adversarial contract is testable without mutating the machine Job Object state.

**Tech Stack:** Windows PowerShell 5.1, .NET `System.Diagnostics.Process`, `kernel32.dll` P/Invoke, PowerShell policy fixtures, Markdown design documentation.

## Global Constraints

- Keep Codex Implement/isolation-required execution fail-closed; never ignore `AssignProcessToJobObject` failure.
- Keep `release-trust.json`, private keys, tokens, key bundles, ZIPs, raw captures, and existing untracked files out of commits.
- Do not change `C:\ProgramData` root ACLs or Windows system ACLs.
- Do not merge `main`; work only on `feat/ai-training-platform-v1`.
- Preserve exact executable paths, no-shell startup, bounded capture, and hard timeout behavior.
- Run the required PowerShell parser, policy fixtures, design-doc verifier, and `git diff --check` before completion; run the production runner only once after the fix.

---

### Task 1: Lock the Job Object policy with failing fixtures

**Files:**
- Modify: `D:/Views/yonlab-inuri-site/scripts/tests/test-runner-policy-fixtures.ps1`
- Test: `D:/Views/yonlab-inuri-site/scripts/invoke-ai-training-platform-v1.ps1` via `PolicySelfTest`

**Interfaces:**
- Consumes: the existing `job-isolation` fixture already present in the user’s modified test file.
- Produces: adversarial fixtures for required fail-closed assignment, read-only fallback, Codex fallback rejection, and policy-self-test bypass.

- [ ] **Step 1: Preserve the existing RED fixture and add one assertion per required behavior.** Extend the existing `$jobIsolation` payload with `command_kind`, `assignment_failed`, `fallback_used`, and an error message containing `Access Denied`, `nested Job Object`, and `independent shell`; add copies that represent a required-mode failure, an unallowlisted read-only command, and a Codex/Implement fallback attempt.

- [ ] **Step 2: Run the policy fixture test before changing the runner.**

Run:

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'D:\Views\yonlab-inuri-site\scripts\tests\test-runner-policy-fixtures.ps1' -RunnerPath 'D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1'
```

Expected: FAIL at the new `POLICY-JOB` fixture because the runner has no `job-isolation` policy case yet.

---

### Task 2: Add explicit isolation modes and nested-job detection

**Files:**
- Modify: `D:/Views/yonlab-inuri-site/scripts/invoke-ai-training-platform-v1.ps1:678-844`
- Test: `D:/Views/yonlab-inuri-site/scripts/tests/test-runner-policy-fixtures.ps1`

**Interfaces:**
- Consumes: `New-KillOnCloseJob`, `Invoke-NativeCaptureBytes`, `Invoke-TrustedValidatorProcess`, and `Invoke-Utf8Process`.
- Produces: `New-KillOnCloseJob($Process, $IsolationMode)`, `Assert-JobIsolationObservation($Observation)`, and explicit mode selection at each process boundary.

- [ ] **Step 1: Add the failing policy assertion for the exact mode contract.** The policy assertion must require `Required` to reject assignment error 5, allow `BestEffortReadOnly` only when `command_kind=ReadOnlyProbe` and the command/arguments match an allowlist, reject fallback for `Implement`/`Codex`, accept `DisabledForPolicySelfTest` without native assignment, and require the diagnostic text to include `Access Denied`, `nested Job Object`, and `independent shell`.

- [ ] **Step 2: Run the focused fixture test and confirm the expected RED result.** Use the command from Task 1 and verify the failure is a policy assertion failure rather than a parser or fixture-shape error.

- [ ] **Step 3: Extend the native P/Invoke type with `IsProcessInJob` and an explicit mode parameter.** Detect whether the current PowerShell process already belongs to a Job Object before starting a child. `ERROR_ACCESS_DENIED` (`5`) in `Required` mode must throw a fail-closed error. In `BestEffortReadOnly`, return a zero job handle only after the caller has already proven the command is an allowlisted read-only probe. `DisabledForPolicySelfTest` must return a zero handle without creating or assigning a native Job Object.

- [ ] **Step 4: Keep process safety invariants in the fallback path.** The fallback must still use the exact direct executable, `UseShellExecute = $false`, no shell shim, canonical executable working directory, safe environment, concurrent bounded stream capture, and hard timeout. `Codex`/Implement and trusted validator execution must use `Required`; only explicitly read-only probes may use `BestEffortReadOnly`.

- [ ] **Step 5: Implement the minimal policy case used by `PolicySelfTest`.** Route `case=job-isolation` to the real `Assert-JobIsolationObservation` function and keep the self-test path free of native process/job assignment.

- [ ] **Step 6: Run the focused policy fixture test and verify GREEN.** Confirm all required-mode, fallback, Codex, self-test, and error-message cases pass.

---

### Task 3: Document the isolation decision

**Files:**
- Modify: `D:/Views/yonlab-inuri-site/docs/planning/ai-training-platform-v1/13-one-command-execution.md:120-121`
- Test: `D:/Views/yonlab-inuri-site/scripts/verify-design-docs.ps1`

**Interfaces:**
- Consumes: the mode contract and error handling implemented in Task 2.
- Produces: an explicit design contract for nested Windows Job Objects and the required independent-shell recovery path.

- [ ] **Step 1: Add the normative isolation paragraph.** State the three modes, the `IsProcessInJob` check, the `ERROR_ACCESS_DENIED`/nested-job behavior, the read-only allowlist boundary, and the fact that Codex Implement cannot fall back.

- [ ] **Step 2: Run the design-document verifier.**

Run:

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'D:\Views\yonlab-inuri-site\scripts\verify-design-docs.ps1'
```

Expected: exit 0 with the existing design-document checks passing.

---

### Task 4: Verify, inspect, commit, and push

**Files:**
- Verify: `D:/Views/yonlab-inuri-site/scripts/invoke-ai-training-platform-v1.ps1`
- Verify: `D:/Views/yonlab-inuri-site/scripts/tests/test-runner-policy-fixtures.ps1`
- Verify: `D:/Views/yonlab-inuri-site/docs/planning/ai-training-platform-v1/13-one-command-execution.md`

**Interfaces:**
- Consumes: all changes from Tasks 1–3.
- Produces: verified branch state and a focused commit; no machine-local trust or secret artifacts.

- [ ] **Step 1: Run the PowerShell 5.1 parser check on the runner and test script.**

```powershell
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command '$null = [System.Management.Automation.Language.Parser]::ParseFile("D:\Views\yonlab-inuri-site\scripts\invoke-ai-training-platform-v1.ps1", [ref]$null, [ref]$null); $null = [System.Management.Automation.Language.Parser]::ParseFile("D:\Views\yonlab-inuri-site\scripts\tests\test-runner-policy-fixtures.ps1", [ref]$null, [ref]$null)'
```

- [ ] **Step 2: Run the policy fixture suite, design-doc verifier, and `git diff --check`; read every exit code.**
- [ ] **Step 3: Run the production runner exactly once after the fix using the independent `cmd.exe` command from the user request.** If the pre-existing protected ACL gate still fails, report it and do not weaken ACL policy or rerun the runner.
- [ ] **Step 4: Inspect `git status --short` and `git diff --check`; confirm existing user files remain present and machine-local trust/private-key/ZIP files are absent from the diff.**
- [ ] **Step 5: Commit only code/tests/design docs with `fix: handle nested Windows job object isolation safely`, then push the feature branch to both `origin` and `upstream` without merging `main`.**

## Self-review

- Spec coverage: Tasks 1–2 cover all five isolation requirements and the diagnostic message; Task 3 records the design decision; Task 4 covers the required verification and handoff constraints.
- Placeholder scan: all steps name concrete files, commands, expected outcomes, and behavior; no TODO/TBD placeholders remain.
- Type consistency: `New-KillOnCloseJob($Process, $IsolationMode)` and `Assert-JobIsolationObservation($Observation)` are the only new interfaces and are used consistently by the test and runner tasks.
