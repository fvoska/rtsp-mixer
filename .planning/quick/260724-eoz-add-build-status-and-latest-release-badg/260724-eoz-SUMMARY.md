---
phase: quick-260724-eoz
plan: 01
subsystem: docs
tags: [readme, badges, ci, release]
requires: []
provides:
  - README build status badge for the Release workflow
  - README latest release version badge (shields.io)
affects: []
tech-stack:
  added: []
  patterns: []
key-files:
  created: []
  modified:
    - README.md
decisions: []
metrics:
  duration: 2min
  completed: 2026-07-24
status: complete
---

# Quick Task 260724-eoz: Add Build Status and Latest Release Badges Summary

**One-liner:** Added a Release-workflow build status badge and a shields.io latest-release version badge to README.md, both as clickable markdown image-links directly under the title.

## What Was Done

Inserted a single badge line between the `# RTSP Mixer` title and the description paragraph, separated by blank lines:

1. **Build status badge** — `https://github.com/fvoska/rtsp-mixer/actions/workflows/release.yml/badge.svg` (alt "Release"), linking to the Release workflow runs page at `https://github.com/fvoska/rtsp-mixer/actions/workflows/release.yml`. Verified `.github/workflows/release.yml` exists, so the badge endpoint reflects the actual build workflow.
2. **Latest release badge** — `https://img.shields.io/github/v/release/fvoska/rtsp-mixer` (alt "Latest release"), linking to `https://github.com/fvoska/rtsp-mixer/releases/latest`. Version auto-updates with each release-please release.

Both use plain markdown `[![alt](image)](link)` syntax on one line separated by a single space. Title and description paragraph are byte-identical to before (`git diff` shows only 2 added lines).

## Task Commits

| Task | Name | Commit |
| ---- | ---- | ------ |
| 1 | Add build status and latest release badges to README.md | 049cd50 |

## Verification

- Plan's automated verify passed: all three grep checks → PASS
- `grep -c "badge.svg" README.md` → 1; `grep -c "img.shields.io" README.md` → 1
- `git diff README.md` (pre-commit) showed only added lines; no existing lines removed or modified

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED

- README.md exists and contains both badge URLs
- Commit 049cd50 exists on branch claude/readme-build-release-badges-62tup8
