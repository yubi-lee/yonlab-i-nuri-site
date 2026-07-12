# Production Target Design Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `docs/design` with a production-ready target system design package for YOnLearn Hub.

**Architecture:** The documentation describes the completed target system, not repository implementation status. Source code and repository history are treated as input evidence only; design scope is defined by product requirements, architecture consistency, operability, security, and verifiability.

**Tech Stack:** Markdown, PowerShell document verification, React, Nginx-compatible web service layer, FastAPI, PostgreSQL, object storage, email provider, structured logging, monitoring, Docker Compose, CI/CD.

## Global Constraints

- Baseline: YOnLearn Hub Production-Ready Target Design.
- Version: 1.0-draft.
- Status: Draft for Internal Design Review.
- Owner: YOnLab Engineering.
- Reviewer: YOnLab Internal Design Review.
- Do not modify application code.
- Do not write release-roadmap or source-map design documents.
- Do not include local absolute paths, broken relative links, empty placeholders, or implementation-state phrases in `docs/design`.

---

### Task 1: Replace Design Package Content

**Files:**
- Modify: `docs/design/**/*.md`

**Interfaces:**
- Consumes: product requirements, repository architecture evidence, prior documentation names
- Produces: target-system design documents

- [x] **Step 1: Define package metadata**

Use the production-ready target baseline metadata consistently across the package.

- [x] **Step 2: Rewrite requirements**

Write functional and non-functional requirements with ID, requirement, rationale, priority, acceptance criteria, related design, and verification method.

- [x] **Step 3: Rewrite system, CDD, ICD, security, operations, verification, and CDR documents**

Keep the target architecture complete enough for design review and delivery planning.

### Task 2: Add Document Verification

**Files:**
- Create: `scripts/verify-design-docs.ps1`

**Interfaces:**
- Consumes: `docs/design`
- Produces: deterministic document-quality checks

- [x] **Step 1: Check required files**

Verify the exact required package file set exists.

- [x] **Step 2: Check prohibited language and placeholders**

Detect state-reporting phrases, local absolute paths, and empty placeholder markers.

- [x] **Step 3: Check IDs, traceability, links, and Mermaid fences**

Verify duplicate document and requirement IDs, requirement traceability to design and verification, relative links, CDD headings, data model coverage, and Markdown fence closure.

### Task 3: Verify And Report

**Files:**
- Read: `docs/design/**/*.md`
- Read: `scripts/verify-design-docs.ps1`

**Interfaces:**
- Consumes: generated docs and verification output
- Produces: final status report

- [x] **Step 1: Run document verification**

Run: `.\scripts\verify-design-docs.ps1`
Expected: PASS.

- [x] **Step 2: Inspect Git status**

Run: `git status --short --untracked-files=all`
Expected: design docs and verification script are visible for review.

### Task 4: Semantic Review And Gate Integration

**Files:**
- Modify: `docs/design/**/*.md`
- Modify: `scripts/verify-design-docs.ps1`
- Modify: `scripts/verify.ps1`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: generated target design package and repository quality gate
- Produces: semantically reviewed design baseline connected to continuous verification

- [x] **Step 1: Review requirements, CDD, ICD, security, operations, verification, and CDR consistency**

Add the missing testability requirement, tighten data-model detail, centralize token configuration policy, and expand verification method evidence requirements.

- [x] **Step 2: Connect documentation to repository maintenance flow**

Link the design package from the root README and add design-maintenance rules to AGENTS.md.

- [x] **Step 3: Integrate the design gate into `scripts/verify.ps1`**

Run `scripts/verify-design-docs.ps1` as `PASS: production target design documentation` before code gates.

- [x] **Step 4: Verify and commit**

Run document verification, integrated verification, diff checks, and create the baseline documentation commit when gates pass.
