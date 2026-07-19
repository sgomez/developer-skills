---
name: implement-issue
description: Implements an issue end-to-end: fetches the spec from the project issue tracker, creates branch, writes code with TDD, runs checks, commits, publishes a draft change (PR/MR), closes issue on merge. Tracker- and host-agnostic — GitHub via gh CLI is the factory default; docs/agents/issue-tracker.md and docs/agents/code-host.md override. Use when user says "implement issue", "work on issue #N", "/implement-issue", or wants to process an issue locally.
---

# Implement Issue

Full issue → PR → close flow, locally.

**Contract docs.** The issue mechanics come from the repo's
`docs/agents/issue-tracker.md` (its `## Delivery operations` section) and
the change mechanics from `docs/agents/code-host.md` — read both first if
present. The commands below are the **GitHub factory defaults** (`gh`),
used verbatim when those docs are absent or confirm GitHub; when a doc
defines a different mechanic for an operation, the doc wins. "PR" below
means whatever the code host calls a reviewable change (pull request,
merge request, branch + change file).

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
step 2. The checks below are for interactive use, where the given ref may
be a parent. Enumerate its children per the tracker doc — GitHub default:

```bash
gh api graphql -f query='
{
  repository(owner:"OWNER", name:"REPO") {
    issue(number: ISSUE_NUM) {
      subIssues(first: 50) {
        pageInfo { hasNextPage }
        nodes { number title state }
      }
    }
  }
}' --jq '.data.repository.issue.subIssues'
```

If `hasNextPage` is `true`, **stop and report**: a parent with more than 50
children should be split, not worked through — and picking from a truncated
list would silently ignore the rest.

If sub-issues exist, pick the first unblocked one. Blockers may be wired as the tracker's native dependency links, as a "Blocked by" section in the sub-issue body, or both (`/to-tickets` prefers native edges where the tracker has them) — check both, per the tracker doc's blocker-state operation. GitHub default:

```bash
gh api repos/OWNER/REPO/issues/<N> --jq '.issue_dependencies_summary.blocked_by // 0'  # open native blockers; 0 = clear
gh issue view <BLOCKER> --json state --jq '.state'  # each body-listed blocker must be "CLOSED"
```

Pick the first open sub-issue where all blockers are closed. If none are unblocked, report to user and stop.

If no sub-issues exist, implement the issue directly.

**If no ref given**, list open issues carrying the AFK-ready triage label per the tracker doc — GitHub default:

```bash
gh issue list --state open --label "ready-for-agent" --json number,title,labels \
  --jq '.[] | "#\(.number) \(.title)"'
```

(`ready-for-agent` is the triage vocabulary from `docs/agents/triage-labels.md`; use the repo's mapping if it differs.)

Priority order: **bugs > tracer bullets > polish > refactors**. Pick highest-priority unblocked issue, or ask user to confirm.

### 2. Read spec

Read the issue with its comments per the tracker doc — GitHub default:

```bash
gh issue view <N> --comments
```

Read the full body, acceptance criteria, and all comments. Pull the parent spec if referenced (the "Parent" section in the issue body).

### 3. Create branch

```bash
# slug = issue title lowercased, spaces→dashes, max 50 chars
# <N> = the issue ref, slugified if it isn't a plain number
git fetch origin main
git checkout -b agent/issue-<N>-<slug> origin/main
```

(On a local code host there is no `origin` — branch from local `main`
instead: `git checkout -b agent/issue-<N>-<slug> main`. The code-host doc
names the base.)

Never `git checkout main` — when running in a linked worktree (the /developer
pipeline always does), `main` is checked out in the primary worktree and the
command fails. Branching straight from `origin/main` works everywhere.

As a /developer worker, confirm you really are in a linked worktree before
branching: `git rev-parse --path-format=absolute --git-dir --git-common-dir`
prints two different paths there. The same path twice means you escaped into
the user's primary checkout — stop and report blocked instead of branching
there. (Interactive use in the primary checkout is fine.)

Keep `--path-format=absolute`: without it git prints whichever form is
shortest from your cwd, so from a subdirectory of the primary checkout you get
`/abs/path/.git` and `../.git` — two different strings for the same repo, and
the check silently clears you to touch the user's checkout.

**Branch before you explore.** A linked worktree is created from the *local*
main, which can lag `origin/main` — source read before this step may be
missing already-merged work and send you down a stale path.

In a fresh worktree, right after branching:

1. Install dependencies (`pnpm install --reporter=silent` or the project's
   equivalent) — worktrees do not share `node_modules`, and missing deps
   produce misleading typecheck/test failures in packages you never touched.
   Install **quietly**: the log is hundreds of lines you will never read, and
   when the install fails the tail says why. Where the tool has no quiet flag,
   redirect to a file (`> /tmp/install.log 2>&1`) and read only that tail, only
   on failure.
2. Run any prerequisite build the project's agent docs call out (e.g. a shared
   contract package the apps consume from `dist` — check `AGENTS.md` /
   `CLAUDE.md` for the exact command).

All file reads and edits use paths inside the worktree (relative to cwd) —
never absolute paths into the primary checkout.

### 4. Implement

- Before grepping for prior art, check the repo's agent docs (`AGENTS.md` /
  `CLAUDE.md` and anything they link under `docs/agents/` — e.g. pattern
  recipes naming golden files to copy). Only explore for what the docs
  don't already answer.
- Explore relevant source files before writing any code
- Follow the parent spec's **Implementation Decisions** and **Testing
  Decisions** where present: build to the interfaces it fixes, write tests
  at the pre-agreed seams (external behaviour, not implementation details),
  and reuse the prior-art tests it names
- Use TDD where tests exist: write failing test → implement → pass (red →
  green). Leave refactor-level cleanups to the review phase — the reviewer
  flags them; don't overload the implementation session
- Keep change as small as possible — only what the issue requires

**Run the tests you are working on, not all of them.** Each red → green loop
runs **only the affected test file**, with the project's quietest reporter:

```bash
pnpm test <path/to/the.test.ts> --reporter=dot   # or --silent, per the project
```

The full suite runs **once**, at the end of this step, after the last loop is
green — together with the typecheck:

```bash
pnpm typecheck
pnpm test --reporter=dot
```

(See `AGENTS.md` / `CLAUDE.md` for this project's exact commands and its quiet
reporter.) The suite printed after every loop is what actually exhausts a
worker's context — far more than any source file — and it tells you nothing the
one file didn't. When a run comes back red, re-run **just the failing file or
test name** for its output; never the suite.

Fix all failures before proceeding. If you cannot fix them, see **Blocked** below.

### 5. Commit

Single commit, conventional format:

```
<type>(<scope>): <short description>

Implements #<N>: <issue title>
- <key decision 1>
- <key decision 2>
```

Wrap body lines at 100 characters — commitlint's conventional config rejects
longer lines (`body-max-line-length`).

### 6. Publish the change (push + open PR)

Publish a **draft** change per the code-host doc, linked to the issue for
closing. GitHub default:

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
- [ ] <acceptance criterion 2>

## Discoveries
<see below — omit the section when empty, the normal case>"
```

Whatever the host, the change body keeps this shape — `Closes <ref>`,
`## What changed`, `## Test plan`, optional `## Discoveries` — the
orchestrator's harvest depends on it. Use the issue's tracker ref in
`Closes`; whether that auto-closes anything is the code-host doc's call.

**Discoveries** is how hard-won knowledge outlives your context: an
orchestrator harvests these sections across PRs and promotes what repeats
into the repo's agent docs. List only things that meet **both** bars:

- no repo doc (`AGENTS.md` / `CLAUDE.md`, `docs/agents/`, `docs/stack-notes`,
  `CONTEXT.md`) answered it, **and**
- it actually cost you something — a failed approach, reverse-engineering a
  pattern from several files, or finding that a doc contradicts the code.

One line each, written for the next agent (name files/commands, not your
journey). Everyday exploration does not qualify; most PRs should have **no**
Discoveries section.

### 7. Done

Do **not** close the issue manually. If the code host auto-closes linked issues on merge (GitHub/GitLab with issues in the same repo — see the code-host doc), `Closes #<N>` handles it; otherwise closing after the merge belongs to whoever merges (the orchestrator under /developer, the human interactively). The parent issue stays open until all sub-issues are merged.

## Blocked

If you cannot implement (missing context, unfixable failures, external dependency), comment on the issue per the tracker doc — GitHub default:

```bash
gh issue comment <N> --body "Blocked: <specific reason>. <what is needed to unblock>."
```

Do **not** close the issue. Stop and report. When running unattended, do not
wait for an answer — the blocking comment plus your final report is the output.

## Rules

- One sub-issue per invocation — always check for sub-issues before treating an issue as standalone
- Never bypass git hooks (`--no-verify`, `-n`). If a pre-push check fails in a package your change didn't touch, first suspect missing installs in the worktree (`pnpm install`); if it is genuinely broken on `origin/main`, report **Blocked** instead of pushing around the gate
- No commented-out code or TODO comments in committed code
- Do not modify files unrelated to the issue
- Never close the issue manually — closing happens on merge (auto-close where the host supports it, otherwise by whoever merges)
