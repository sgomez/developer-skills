---
name: review-pr
description: Reviews the current PR branch diff against main, posts inline review comments and a summary, then marks the PR ready for review. Local replacement for the agent-review GitHub workflow. Use when user says "review pr", "review this pr", "/review-pr", or wants to run automated review on a pull request.
---

# Review PR

Reviews current branch diff, posts GitHub review, marks PR ready.

## Invoke

```
/review-pr          # reviews PR for current branch
/review-pr 42       # reviews PR #42
```

## Flow

### 1. Identify and check out the PR

If no number given:
```bash
gh pr view --json number,title,headRefName,baseRefName,state
```

Refuse if PR is closed or merged.

If the current branch is not the PR branch (the /developer pipeline runs this
in a fresh worktree), first confirm **where you are**:

```bash
git rev-parse --git-dir --git-common-dir   # two different paths = linked worktree
```

If both paths are equal you are in the **primary checkout** — detaching or
switching it would hijack the user's working state. Never do it: as a
/developer worker end with `RESULT blocked reason=escaped worktree —
refusing to touch the primary checkout`; interactively, stop and tell the
user. In a linked worktree, check out the PR head detached:

```bash
git fetch origin "pull/<PR>/head" && git checkout --detach FETCH_HEAD
```

Never `gh pr checkout` — in a linked worktree it fails with
`fatal: '<branch>' is already used by worktree` because the PR branch is
still checked out in the build worker's worktree. Never `git checkout main`
either — `main` is checked out in the primary worktree.

### 2. Read full diff

```bash
git fetch origin main
git diff origin/main...HEAD
```

Also read:
```bash
gh pr view --comments   # existing comments
gh pr diff              # rendered diff with context
```

### 3. Review

Check for:
- **Correctness bugs** — logic errors, off-by-ones, null/undefined, wrong types
- **Missing tests** — acceptance criteria from issue not covered
- **Security** — injection, unvalidated input, exposed secrets
- **Simplification** — dead code, duplication, over-engineering
- **Checks** — run the project's typecheck and test commands (see `AGENTS.md` / `CLAUDE.md`); failures are blocking

Separate findings into **actionable** (require a code change: bugs, failing
checks, missing acceptance criteria, security) and **notes** (style
preferences, questions, nice-to-haves). Only actionable findings block.

### 4. Post GitHub review

For each actionable finding, post an inline review comment on the exact line.
Group into a single review submission. Use `line` + `side` (`position` is
deprecated) and `-F` for the numeric field:

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/reviews \
  --method POST \
  -f event="COMMENT" \
  -f body="<overall summary, including non-blocking notes>" \
  -f "comments[][path]"="<file>" \
  -F "comments[][line]"=<line> \
  -f "comments[][side]"="RIGHT" \
  -f "comments[][body]"="<finding>"
```

If no actionable findings: post a `COMMENT` review whose body starts with a
clear "CLEAN" summary (non-blocking notes may go in the body). Never use the
`APPROVE` event — the pipeline authors PRs under the same GitHub identity
that reviews them, and GitHub rejects self-approval (HTTP 422).

### 5. Mark ready

```bash
gh pr ready <PR>
```

## Rules

- Post review even if no findings (COMMENT + "CLEAN" summary; never APPROVE)
- Never push code changes — review only
- One review submission (not individual comments)
- Flag typecheck / test failures as blocking
- Unattended: never ask the user anything; when unsure whether a finding
  blocks, ask "would this stop me merging?" — if not, it's a note
