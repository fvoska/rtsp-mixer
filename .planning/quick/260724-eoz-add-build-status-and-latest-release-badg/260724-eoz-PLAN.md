---
phase: quick-260724-eoz
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - README.md
autonomous: true
requirements: []

must_haves:
  truths:
    - "README.md shows a build status badge for the Release workflow that links to the workflow runs page on GitHub Actions."
    - "README.md shows a latest release version badge that links to the latest GitHub release page."
    - "Badges render as images (markdown image-inside-link syntax), placed directly under the top-level title."
    - "The existing title and description paragraph are unchanged."
  artifacts:
    - README.md
  key_links:
    - "Build badge image URL points at the Release workflow badge endpoint (actions/workflows/release.yml/badge.svg) so status reflects the actual build workflow."
    - "Release badge image URL uses shields.io github/v/release for fvoska/rtsp-mixer so the version auto-updates with each release."
---

<objective>
Add a build status badge and a latest release badge to README.md, so anyone viewing the repo can see at a glance whether the Release workflow (release-please + Android APK build) is passing and what the newest released version is.

Purpose: Surface CI health and current release version on the repo landing page.
Output: Updated README.md with two clickable badges under the title.
</objective>

<execution_context>
@/home/user/rtsp-mixer/.claude/gsd-core/workflows/execute-plan.md
@/home/user/rtsp-mixer/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md

# The file to edit — currently 3 lines: "# RTSP Mixer" title + one description paragraph.
@README.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add build status and latest release badges to README.md</name>
  <files>README.md</files>
  <action>
In README.md, insert a single badge line between the `# RTSP Mixer` title and the description paragraph, separated from both by blank lines. The line contains exactly two markdown image-links, in this order:

1. Build status badge — image `https://github.com/fvoska/rtsp-mixer/actions/workflows/release.yml/badge.svg`, alt text "Release", linking to `https://github.com/fvoska/rtsp-mixer/actions/workflows/release.yml` (the Release workflow runs page).
2. Latest release badge — image `https://img.shields.io/github/v/release/fvoska/rtsp-mixer`, alt text "Latest release", linking to `https://github.com/fvoska/rtsp-mixer/releases/latest`.

Use plain markdown `[![alt](image-url)](link-url)` syntax (not HTML), with the two badges on one line separated by a single space. Do not modify the title or the description paragraph. No other changes to the file.

The commit type for this change is `docs`.
  </action>
  <verify>
    <automated>grep -q "actions/workflows/release.yml/badge.svg" README.md && grep -q "img.shields.io/github/v/release/fvoska/rtsp-mixer" README.md && grep -q "releases/latest" README.md && echo PASS</automated>
  </verify>
  <done>README.md contains one badge line under the title with: (1) the Release workflow badge.svg image linking to the workflow runs page, and (2) the shields.io release-version image linking to the latest release page. Title and description are byte-identical to before; file remains valid markdown.</done>
</task>

</tasks>

<verification>
- `grep -c "badge.svg" README.md` returns 1 and `grep -c "img.shields.io" README.md` returns 1.
- `git diff README.md` shows only added lines (the badge line and surrounding blank line); no existing lines removed or modified.
- Both badge links use markdown image-inside-link syntax so they are clickable on GitHub.
</verification>

<success_criteria>
The repo README displays a live build status badge for the Release workflow and a latest release version badge, each linking to the correct GitHub page, with the rest of the README untouched.
</success_criteria>

<output>
Create `.planning/quick/260724-eoz-add-build-status-and-latest-release-badg/260724-eoz-SUMMARY.md` when done.
</output>
