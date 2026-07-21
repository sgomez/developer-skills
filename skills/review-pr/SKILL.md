---
name: review-pr
description: Reviews a change (PR/MR) diff against main, posts inline review comments and a summary, then marks it ready for review. Tracker- and host-agnostic — GitHub via gh is the factory default; docs/agents/code-host.md overrides. Use when user says "review pr", "review this pr", "/review-pr", or wants to run automated review on a pull request.
---

# Review PR

Reviews the change's diff, posts the review, marks it ready.

**Contract doc.** Change mechanics come from the repo's
`docs/agents/code-host.md` — read it first if present. The commands below
are the **GitHub factory defaults** (`gh`), used verbatim when that doc is
absent or confirms GitHub; when it defines a different mechanic for an
operation (checkout, read feedback, post review, mark ready), the doc
wins. "PR" below means whatever the code host calls a reviewable change.

## Invoke

```
/review-pr          # reviews PR for current branch
/review-pr 42       # reviews PR #42
```

## Flow

### 1. Identify and check out the PR

If no ref given, get the current branch's change metadata — GitHub default:
```bash
gh pr view --json number,title,headRefName,baseRefName,state
```

Refuse if PR is closed or merged.

If the current branch is not the PR branch (the /developer pipeline runs this
in a fresh worktree), first confirm **where you are**:

```bash
git rev-parse --path-format=absolute --git-dir --git-common-dir   # two different paths = linked worktree
```

`--path-format=absolute` is not optional. Without it git answers with whatever
form is shortest from your cwd, so in the primary checkout's *root* both print
`.git` (equal, correct) but from any *subdirectory* they print an absolute path
and `../.git` — different strings for the same repo, which reads as "linked
worktree" and lets the checkout below run against the user's checkout.

If both paths are equal you are in the **primary checkout** — detaching or
switching it would hijack the user's working state. Never do it: as a
/developer worker end with `RESULT blocked reason=escaped worktree —
refusing to touch the primary checkout`; interactively, stop and tell the
user. Then check out the change head detached, per the code-host doc's
read-only checkout — but **gate the checkout on the worktree check in the
same command**, so that if your cwd ever drifts to the primary checkout the
`git checkout` simply does not run (you get a clean blocked report instead of
hijacking the user's working state). GitHub default:

```bash
[ "$(git rev-parse --path-format=absolute --git-dir)" != "$(git rev-parse --path-format=absolute --git-common-dir)" ] \
  || { echo "escaped worktree — refusing to touch the primary checkout"; exit 1; }
git fetch origin "pull/<PR>/head" && git checkout --detach FETCH_HEAD
```

Never `gh pr checkout` — in a linked worktree it fails with
`fatal: '<branch>' is already used by worktree` because the PR branch is
still checked out in the build worker's worktree. Never `git checkout main`
either — `main` is checked out in the primary worktree.

### 2. Read full diff

```bash
git fetch origin main    # local host: skip the fetch, diff against main
git diff origin/main...HEAD
```

Also read the existing feedback and rendered diff — GitHub default:
```bash
gh pr view --comments   # existing comments
gh pr diff              # rendered diff with context
```

Then locate the **originating spec**: the issue(s) the PR body's
`Closes #N` references (the /developer pipeline guarantees one;
interactively, fall back to issue refs in the branch name or commit
messages). Read each with its comments per the tracker doc — GitHub
default `gh issue view <N> --comments` — including the parent spec/PRD
when the issue's `Parent` section names one. If no spec can be found, say
so in the review summary and skip the spec-fidelity checks below.

### 3. Review

Check for:
- **Correctness bugs** — logic errors, off-by-ones, null/undefined, wrong types
- **Spec fidelity** — requirements or acceptance criteria from the
  originating issue that are missing, partial, or implemented wrong;
  behaviour the issue never asked for (scope creep)
- **Missing tests** — acceptance criteria from issue not covered
- **Security** — injection, unvalidated input, exposed secrets
- **Simplification** — dead code, duplication, over-engineering
- **Refactoring smells** (never blocking) — Fowler's catalogue: mysterious
  name, duplicated code, feature envy, data clumps, primitive obsession,
  repeated switches, shotgun surgery, divergent change, speculative
  generality, message chains, middle man, refused bequest. Each is a
  judgement call — label it as one ("possible Feature Envy"), and skip
  anything a documented repo standard endorses or tooling already enforces
- **Checks** — see below; failures are always blocking

#### Checks — let CI answer where it can

The typecheck and the test suite are the most expensive part of this review,
and on a repo with CI they are the *third* time the same commands run on the
same commit: the builder ran them, the change's CI is running them, and you
would run them again.

So, **before installing anything**: if `docs/agents/code-host.md` declares a
CI system, read the checks recorded for the change's **head sha**, per its
"read the checks" operation. GitHub default:

```bash
gh pr checks <PR> --json name,state,link --jq \
  '[.[] | select(.state != "SUCCESS" and .state != "SKIPPED")]'
```

- **Green** (empty output, at least one check present) → **skip the install
  and the local suite entirely.** Review the diff and spec fidelity only, and
  say in the summary that checks were taken from CI (name the head sha). The
  suite has already answered; re-running it buys nothing and costs the most
  context of anything you do.
- **Red** → check the failing job **actually executed**, per the code-host
  doc's classify-a-red operation (GitHub default: `gh run view <run-id>
  --json jobs`, `<run-id>` from the check's `link` — a failed job with zero
  steps never started). Never started (runner offline, CI minutes
  exhausted) → the red recorded nothing about this change: treat it as **no
  checks recorded** and fall back to the local run below. Executed →
  **NEEDS_FIXES**, with the failing job's **URL** in the finding. Do not
  try to reproduce it locally and do not review around it: the fixer needs
  the job, not your re-run.
- **Still running** → do not wait for it. Fall back to the local run below.
- **No CI declared** (or no checks recorded for the head sha) → the local run
  below, exactly as before.

**Local run** (the fallback): install dependencies quietly, then run the
project's typecheck and test commands once (see `AGENTS.md` / `CLAUDE.md`)
with its quietest reporter (`--reporter=dot`, `--silent`) — a green suite's
per-test output is pure context cost. On a red run, re-run **only** the
failing file or test name to get the detail you need to write the finding.

Separate findings into **actionable** (require a code change: bugs, spec
violations — missing/wrong requirements, scope creep — failing checks,
missing acceptance criteria, security) and **notes** (style preferences,
questions, nice-to-haves, refactoring smells). Only actionable findings
block.

### 4. Post the review

For each actionable finding, post an inline review comment on the exact
line, per the code-host doc's post-review operation; group everything into
one review submission where the host supports it. GitHub default — use
`line` + `side` (`position` is deprecated) and `-F` for the numeric field:

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

If no actionable findings: post a review whose summary starts with a clear
"CLEAN" (non-blocking notes may go in the body). Never use an approval
event (`APPROVE`, `glab mr approve`, …) — the pipeline authors changes
under the same identity that reviews them; on GitHub self-approval is
rejected outright (HTTP 422), and everywhere the CLEAN summary is the
approval signal.

### 5. Mark ready

As a `/developer` worker, skip this step — marking the PR ready is the
orchestrator's job (on a local code host it stays yours: `Status: ready`
goes in the same change-file commit as the review).

Interactively, per the code-host doc — GitHub default:

```bash
gh pr ready <PR>
```

## Rules

- Post review even if no findings ("CLEAN" summary; never an approval event)
- Never push code changes — review only (exception: a local code host's
  review lives in the change file; committing that one file is the review)
- One review submission, not comment-by-comment (where the host can batch)
- Flag typecheck / test failures as blocking, whether they came from CI or
  from your own run — a red check is never a note
- Never run the suite locally when the change's CI already reports green for
  its head sha
- Unattended: never ask the user anything; when unsure whether a finding
  blocks, ask "would this stop me merging?" — if not, it's a note
