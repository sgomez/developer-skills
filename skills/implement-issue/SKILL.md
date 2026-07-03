---
name: implement-issue
description: Implements a GitHub issue end-to-end: fetches spec, creates branch, writes code with TDD, runs checks, commits, pushes, opens draft PR, closes issue. No API key, no containers — uses gh CLI and git directly with your Claude subscription. Use when user says "implement issue", "work on issue #N", "/implement-issue", or wants to process a GitHub issue locally.
---

# Implement Issue

Full issue → PR → close flow, locally, using `gh` and `git`.

## Invoke

```
/implement-issue          # lists open issues to pick from
/implement-issue 42       # implements issue #42 directly
/implement-issue 17       # if #17 has sub-issues, picks the first unblocked open one
```

One sub-issue per invocation — keeps sessions short and focused.

## Flow

### 1. Select issue

**If an orchestrator (e.g. /developer) already told you which sub-issue to
implement, skip selection entirely** — verify the issue is open and go to
step 2. The checks below are for interactive use, where the given number may
be a parent:

```bash
gh api graphql -f query='
{
  repository(owner:"OWNER", name:"REPO") {
    issue(number: ISSUE_NUM) {
      subIssues(first: 20) {
        nodes { number title state body }
      }
    }
  }
}' --jq '.data.repository.issue.subIssues.nodes[] | select(.state == "OPEN") | "#\(.number) \(.title)"'
```

If sub-issues exist, pick the first unblocked one. Check "Blocked by" in each sub-issue body and verify all referenced issues are closed:

```bash
gh issue view <N> --json state --jq '.state'  # must be "CLOSED" for each blocker
```

Pick the first open sub-issue where all blockers are closed. If none are unblocked, report to user and stop.

If no sub-issues exist, implement the issue directly.

**If no number given**, list candidates from the tracker:

```bash
gh issue list --state open --label "ready-for-agent" --json number,title,labels \
  --jq '.[] | "#\(.number) \(.title)"'
```

(`ready-for-agent` is the triage vocabulary from `docs/agents/triage-labels.md`; use the repo's mapping if it differs.)

Priority order: **bugs > tracer bullets > polish > refactors**. Pick highest-priority unblocked issue, or ask user to confirm.

### 2. Read spec

```bash
gh issue view <N> --comments
```

Read the full body, acceptance criteria, and all comments. Pull parent PRD if referenced (the "Parent" section in the issue body).

### 3. Create branch

```bash
# slug = issue title lowercased, spaces→dashes, max 50 chars
git fetch origin main
git checkout -b agent/issue-<N>-<slug> origin/main
```

Never `git checkout main` — when running in a linked worktree (the /developer
pipeline always does), `main` is checked out in the primary worktree and the
command fails. Branching straight from `origin/main` works everywhere.

### 4. Implement

- Explore relevant source files before writing any code
- Use TDD where tests exist: write failing test → implement → pass → refactor
- Keep change as small as possible — only what the issue requires
- Run the project's checks (see `AGENTS.md` / `CLAUDE.md` for the exact commands), typically:

```bash
pnpm typecheck
pnpm test
```

Fix all failures before proceeding. If you cannot fix them, see **Blocked** below.

### 5. Commit

Single commit, conventional format:

```
<type>(<scope>): <short description>

Implements #<N>: <issue title>
- <key decision 1>
- <key decision 2>
```

### 6. Push + open PR

```bash
git push origin agent/issue-<N>-<slug>

gh pr create \
  --draft \
  --base main \
  --title "<type>(<scope>): <short description>" \
  --body "Closes #<N>

## What changed
<brief summary>

## Test plan
- [ ] <acceptance criterion 1>
- [ ] <acceptance criterion 2>"
```

### 7. Done

The PR body contains `Closes #<N>` — GitHub auto-closes the implemented sub-issue when the PR is merged. Do **not** close the issue manually. The parent issue stays open until all sub-issues are merged.

## Blocked

If you cannot implement (missing context, unfixable failures, external dependency):

```bash
gh issue comment <N> --body "Blocked: <specific reason>. <what is needed to unblock>."
```

Do **not** close the issue. Stop and report. When running unattended, do not
wait for an answer — the blocking comment plus your final report is the output.

## Rules

- One sub-issue per invocation — always check for sub-issues before treating an issue as standalone
- No commented-out code or TODO comments in committed code
- Do not modify files unrelated to the issue
- Never close the issue manually — `Closes #N` in the PR body handles it on merge
