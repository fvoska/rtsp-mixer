---
phase: quick-260723-pki
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - CLAUDE.md
autonomous: true
requirements: []

must_haves:
  truths:
    - "The 'Commits and PR titles' subsection contains an explicit, numbered 'Creating a PR' procedure that mandates reviewing ALL branch commits before composing title/description."
    - "The procedure names a concrete command for reviewing branch commits (git log <base>..HEAD)."
    - "The procedure requires always passing an explicit title AND body to the PR creation tool (gh pr create / GitHub MCP create_pull_request), never letting GitHub default them."
    - "The procedure covers fixing an already-opened PR that has default title/description."
  artifacts:
    - CLAUDE.md
  key_links:
    - "Edit stays between the <!-- GSD:conventions-start --> markers; rest of CLAUDE.md unchanged."
---

<objective>
Strengthen the "Commits and PR titles — Conventional Commits (release-please)" subsection of CLAUDE.md so Claude reliably composes PR title and description from ALL commits on the branch, not GitHub's default (which in this repo is usually the first `docs(...): pre-dispatch plan` GSD planning commit).

Purpose: Eliminate the recurring pain of poor auto-generated PR titles/descriptions that misclassify changes for release-please and require manual after-the-fact fixes.
Output: An updated CLAUDE.md with an explicit, mechanical "Creating a PR" procedure inside the existing subsection.
</objective>

<execution_context>
@/home/user/rtsp-mixer/.claude/gsd-core/workflows/execute-plan.md
@/home/user/rtsp-mixer/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md

# The file to edit — target the existing "Commits and PR titles" subsection (approx lines 116-124),
# which sits inside the <!-- GSD:conventions-start source:CONVENTIONS.md --> markers.
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add explicit "Creating a PR" procedure to the Commits and PR titles subsection</name>
  <files>CLAUDE.md</files>
  <action>
In CLAUDE.md, within the "### Commits and PR titles — Conventional Commits (release-please)" subsection (between the `<!-- GSD:conventions-start source:CONVENTIONS.md -->` marker and the next `###` heading), rework the existing "Never accept GitHub's auto-generated PR title or description." bullet into a strong, numbered "Creating a PR" procedure. Keep all other bullets (the Conventional Commits format rule, the commit-linting bullet, the allowed-types bullet, and the version-bump bullet) intact and in place.

The new procedure MUST be a numbered list (introduced by a bolded lead-in such as "**Creating a PR — always derive title and description from the whole branch:**") that includes, in order:
1. Before opening any PR, review ALL commits on the branch — name the concrete command `git log --oneline <base>..HEAD` (base is `main`) and optionally `git diff <base>...HEAD --stat` to see the full changeset. State plainly that the FIRST commit is usually a `docs(...): pre-dispatch plan` GSD planning commit and MUST NOT be used as the title.
2. Compose the PR title as a single Conventional Commits line (`type(scope): description`) describing the OVERALL change across all commits — the type reflects the substantive change (e.g. a feature PR is `feat(...)` even if the first commit is `docs:`/`test:`/`chore:`).
3. Compose the PR description to summarize the whole diff and all meaningful commits, not just one.
4. ALWAYS pass an explicit title AND body to the PR-creation tool (`gh pr create --title ... --body ...`, or the GitHub MCP `create_pull_request` with explicit `title` and `body`) — never omit them and let GitHub fill in defaults from the first commit.
5. If a PR was already opened with a default title/description, update it (e.g. `gh pr edit --title ... --body ...`) rather than leaving it.

Write in the same terse, imperative documentation voice as the surrounding bullets. Do not restructure any other part of the file. This is the only change; the commit type for this change is `docs`.
  </action>
  <verify>
    <automated>grep -q "Creating a PR" CLAUDE.md && grep -q "git log --oneline" CLAUDE.md && grep -q "create_pull_request" CLAUDE.md && grep -q "gh pr edit" CLAUDE.md && echo PASS</automated>
  </verify>
  <done>The "Commits and PR titles" subsection contains a numbered "Creating a PR" procedure that: references `git log --oneline <base>..HEAD`, names the first commit as the GSD planning commit not to use, requires an explicit Conventional Commits title and full-diff description, mandates passing explicit title+body to the PR tool, and covers editing an already-opened PR. All other bullets in the subsection and the rest of the file are unchanged.</done>
</task>

</tasks>

<verification>
- `grep -q "Creating a PR" CLAUDE.md` succeeds.
- The four original bullets (Conventional Commits format, commit linting, allowed types, version bump) still present.
- Edit is confined to the Conventions region; `git diff CLAUDE.md` shows changes only within the "Commits and PR titles" subsection.
</verification>

<success_criteria>
CLAUDE.md's PR conventions now give Claude a mechanical, unambiguous procedure to derive PR title and description from all branch commits, eliminating reliance on GitHub's first-commit default.
</success_criteria>

<output>
Create `.planning/quick/260723-pki-strengthen-claude-md-pr-title-descriptio/260723-pki-SUMMARY.md` when done.
</output>
