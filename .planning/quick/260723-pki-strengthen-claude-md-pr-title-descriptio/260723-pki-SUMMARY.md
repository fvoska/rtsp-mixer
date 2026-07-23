---
phase: quick-260723-pki
plan: 01
subsystem: docs
tags: [conventions, pr, release-please, claude-md]
requires: []
provides:
  - "CLAUDE.md 'Creating a PR' procedure"
affects:
  - CLAUDE.md
tech-stack:
  added: []
  patterns: []
key-files:
  created: []
  modified:
    - CLAUDE.md
decisions: []
metrics:
  duration: 1min
  completed: 2026-07-23
status: complete
---

# Quick Task 260723-pki: Strengthen CLAUDE.md PR title/description guidance Summary

Reworked the "Never accept GitHub's auto-generated PR title or description" bullet in CLAUDE.md's Conventions into an explicit, numbered "Creating a PR" procedure that forces PR title and description to be derived from ALL branch commits rather than GitHub's first-commit default.

## What Changed

Within the `### Commits and PR titles — Conventional Commits (release-please)` subsection (inside the `<!-- GSD:conventions-start -->` markers), the single freeform "Never accept GitHub's auto-generated PR title or description" bullet was replaced with a bolded, 5-step numbered procedure:

1. Review all branch commits first via `git log --oneline main..HEAD` (and optional `git diff main...HEAD --stat`), noting the first commit is usually the `docs(...): pre-dispatch plan` GSD commit that must not be used as the title.
2. Compose the title as a single Conventional Commits line for the OVERALL change.
3. Compose the description to summarize the whole diff / all meaningful commits.
4. Always pass explicit title AND body to the PR tool (`gh pr create --title ... --body ...` or GitHub MCP `create_pull_request`) — never let GitHub default them.
5. If a PR already has a default title/description, fix it with `gh pr edit --title ... --body ...`.

The four surrounding bullets (Conventional Commits format rule, commit-linting, allowed types, version bump) are unchanged, as is the rest of the file.

## Verification

- Automated check passed: `grep -q "Creating a PR"`, `grep -q "git log --oneline"`, `grep -q "create_pull_request"`, `grep -q "gh pr edit"` all succeed → `PASS`.
- `git diff --stat` confirms only CLAUDE.md changed (6 insertions, 1 deletion), confined to the Conventions region.

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED

- FOUND: CLAUDE.md (modified, contains "Creating a PR" procedure)
- FOUND: commit c58afd1
