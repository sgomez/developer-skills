---
name: implement-issue
description: Implements an issue end-to-end: fetches the spec from the project issue tracker, creates branch, writes code with TDD, runs checks, commits, publishes a draft change (PR/MR), closes issue on merge. Tracker- and host-agnostic — GitHub via gh CLI is the factory default; docs/agents/issue-tracker.md and docs/agents/code-host.md override. Use when user says "implement issue", "work on issue #N", "/implement-issue", or wants to process an issue locally.
---

# Implement Issue

Issue → branch → test-first code → checks → draft PR. One issue per invocation.

**Contract docs.** Issue mechanics come from `docs/agents/issue-tracker.md`
(its `## Delivery operations`), change mechanics from `docs/agents/code-host.md`.
Read those two first if present; where they define an operation, they win over
the `gh` defaults below. "PR" means whatever the code host calls a reviewable
change. Their annexes (`code-host-ci.md`, `issue-authoring.md`) are for later
phases — implementing an issue needs neither.

## What the work is judged on

1. **It does what the issue asks, the way the spec decided.** Every
   acceptance criterion, built to the interfaces and seams the spec's
   Implementation and Testing Decisions fix. Where the issue is part of a
   larger spec, your code has to fit the rest of it: reuse what already exists
   instead of adding a second version of it.
2. **Every behaviour has a test that fails without it.** Proven, not assumed:
   you saw it fail (see *Red before green*).
3. **The change is as small as the issue allows.** Refactor-level cleanups
   belong to the review, not here.

Everything else in this skill is how to get there without wasting the session.

## Red before green

One behaviour at a time: write its test, **run it and watch it fail**, write
only the code that makes it pass, run it green, next behaviour. Never write the
tests in bulk and the code after; never write code before its test has been
seen red.

The red run is the proof the test can fail. A test that passes before the code
exists tests nothing: the behaviour comes by another path, or the test never
reaches it — an assertion that runs before an async result lands, a key
pressed with the focus already on the button so the browser's own handling
passes it, a mock that answers whatever is asked. Rewrite it until it is red
for the right reason (the message names the missing behaviour, not a typo or
an import), then implement.

A good test:
- exercises behaviour through the public seam — what a user or caller sees —
  never internals, so it survives a refactor;
- takes its expected values from the spec or a worked example, never
  recomputed the way the code computes them;
- fails when the behaviour it names breaks, and only then.

When your change moves what an **existing** test exercises (a listener to
another target, a handler to another component), make that test fail once
against a deliberately broken version of your code, then restore it: a test a
refactor left green may no longer be able to fail.

Where no test can come first — pure wiring, config, no harness for it — say so
in the PR's Test plan rather than skipping silently.

## Flow

### 1. Select the issue

**When a caller (e.g. /developer) named the issue, skip this step** — check
it is open and go on.

Interactively: if the given issue has sub-issues (GitHub:
`gh api graphql` on `issue.subIssues(first: 50) { pageInfo { hasNextPage } nodes { number title state } }`),
pick the first open one whose blockers — native dependency links and any
"Blocked by" list in its body — are all closed. Over 50 children: stop and
report, the parent should be split. Nothing unblocked: report and stop. With no
ref, list open issues labelled `ready-for-agent` (or the repo's mapping in
`docs/agents/triage-labels.md`) and pick bugs > tracer bullets > polish >
refactors, or ask.

### 2. Read the issue

Once, with its comments, into a file — GitHub:
`gh issue view <N> --json title,body,comments > /tmp/issue-<N>.json`, then read
the file. (`gh issue view --comments` comes back empty inside a /developer
worktree.)

The issue's `## Spec extract` carries the spec decisions that apply to it;
read the parent spec only when that section is missing — unless the caller
tells you to read it anyway.

### 3. Branch and bootstrap

```bash
git fetch origin main
git checkout -b agent/issue-<N>-<slug> origin/main   # slug: title, lowercased, dashed, ≤50 chars
```

- **A branch name from the caller** replaces `agent/issue-<N>-<slug>`.
- **A base branch from the caller** (e.g. a spec's integration branch)
  replaces `main` everywhere: fetch it, branch from `origin/<base>`, open the
  PR against it.
- Local code host (no `origin`): branch from local `main` / `<base>`.
- Never `git checkout main` — in a linked worktree it is held by the primary
  checkout.
- As a /developer worker, first confirm you are in a linked worktree:
  `git rev-parse --path-format=absolute --git-dir --git-common-dir` must print
  two different paths (keep `--path-format=absolute`). The same path twice
  means you are in the user's checkout: stop and report blocked.

Branch **before** reading any source — a fresh worktree starts from the local
main, which can lag. Then install dependencies quietly
(`pnpm install --reporter=silent` or the project's equivalent; no quiet flag →
redirect to a file and read its tail only on failure) and run any prerequisite
build `AGENTS.md` / `CLAUDE.md` names. All paths stay inside the worktree.

### 4. Implement

Explore first, through the repo's own map: `AGENTS.md` / `CLAUDE.md` and what
they link under `docs/agents/`; where they prescribe a zone map or an index
command (`just outline <path>`, ctags…), that is binding — use it rather than
`cat` on large files, never truncate it or silence its errors, and batch
several lookups in one call. Read each file whole **once**; afterwards use
`grep -n` / `sed -n`. Never re-read a file to check your own edit.

Then the red → green loop above, running **only the test file you are working
on** with the project's quietest reporter (`pnpm test <file> --reporter=dot`
or the project's form). A red run: re-run just that file or test for its
output, never the suite.

### 5. Checks

After the last loop is green, once each:

1. Typecheck and the full suite — **unless the repo's pre-push hook runs
   them** (`lefthook.yml`, `.husky/pre-push`, `.pre-commit-config.yaml`); then
   the push in step 7 is that run.
2. The formatter's **writing** form (`biome check --write .`, `cargo fmt --all`,
   …), always — a hook only checks.
3. The lint gate (the repo's own recipe — `just lint`, a `package.json`
   script…), unless the pre-push hook runs it.

Commands without a quiet reporter: `<cmd> > /tmp/check.log 2>&1; echo "exit=$?"`,
and grep the log only when the exit is non-zero. Never pipe a gate into `tail`:
it throws the exit code away. A green gate is never re-run to confirm it.

Fix every failure. If you cannot, see **Blocked**.

### 6. Commit

One commit, Conventional Commits, body lines ≤ 100 characters:

```
<type>(<scope>): <short description>

Implements #<N>: <issue title>
- <key decision>
```

### 7. Publish

A **draft** PR linked to the issue for closing — GitHub:

```bash
git push origin <branch>

gh pr create --draft --base <base> \
  --title "<type>(<scope>): <short description>" \
  --body "Closes #<N>

## What changed
<brief summary; any judgement call on an ambiguous point>

## Test plan
- [ ] <acceptance criterion> — <test name>, seen red first

## Discoveries
<omit when empty, the normal case>"
```

Run the push alone, bare, with the Bash tool's maximum timeout
(`timeout: 600000`) — a gate-running pre-push hook outlasts the default, and the
worktree sandbox refuses compound shapes. If the hook rejects the push, fix,
amend (nothing was published), push again. Never `--no-verify`.

Keep the body's shape whatever the host — `Closes <ref>`, `## What changed`,
`## Test plan`, optional `## Discoveries`: the orchestrator's harvest reads it.

**Discoveries** are for the next agent: one line each, naming files or
commands, only for something that no repo doc answered **and** that cost you
something (a failed approach, a pattern reverse-engineered from several
files, a doc contradicting the code). Most PRs have none.

### 8. Done

Do not close the issue. `Closes #<N>` closes it on merge where the host
supports that; otherwise whoever merges closes it.

## Blocked

When you cannot finish (missing context, unfixable failures, an external
dependency), comment on the issue — GitHub:
`gh issue comment <N> --body "Blocked: <reason>. <what would unblock it>."` —
and stop. Do not close it. Unattended, do not wait for an answer.

## Rules

- One issue per invocation.
- No code before its test has been seen failing; a test green on its first
  run is rewritten, not kept.
- Never bypass git hooks. A pre-push failure in a package you did not touch:
  suspect missing installs first; genuinely broken on the base branch → Blocked.
- No commented-out code, no TODOs.
