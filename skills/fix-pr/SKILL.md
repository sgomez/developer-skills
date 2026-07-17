---
name: fix-pr
description: Reads all unresolved review comments and threads on a change (PR/MR), implements the fixes, pushes, and replies to each thread. Tracker- and host-agnostic — GitHub via gh is the factory default; docs/agents/code-host.md overrides. Use when user says "fix pr comments", "address review", "/fix-pr", or wants to respond to PR review feedback.
---

# Fix PR

Reads review comments, implements fixes, pushes, replies to threads.

**Contract doc.** Change mechanics come from the repo's
`docs/agents/code-host.md` — read it first if present. The commands below
are the **GitHub factory defaults** (`gh`), used verbatim when that doc is
absent or confirms GitHub; when it defines a different mechanic for an
operation (checkout, read feedback, reply, publish commits), the doc wins.
"PR" below means whatever the code host calls a reviewable change.

## Invoke

```
/fix-pr         # fixes current branch PR
/fix-pr 42      # fixes PR #42
```

## Flow

### 1. Identify and check out the PR

Get the change metadata — GitHub default:

```bash
gh pr view <PR> --json number,title,headRefName,state
```

Refuse if PR is closed or merged.

If the current branch is not the PR branch (the /developer pipeline runs this
in a fresh worktree), first confirm **where you are**:

```bash
git rev-parse --git-dir --git-common-dir   # two different paths = linked worktree
```

As a /developer worker you must be in a linked worktree; if both paths are
equal you are in the user's primary checkout — do not check anything out,
end with `RESULT blocked reason=escaped worktree`. Then check out the
change per the code-host doc's fix-that-pushes checkout. GitHub default:

```bash
gh pr checkout <PR>
```

If that fails with `already used by worktree` (normal under /developer — the
PR branch is checked out in the build worker's worktree):

```bash
git fetch origin pull/<PR>/head:fix/pr-<PR> && git checkout fix/pr-<PR>
```

and push later with `git push origin HEAD:<pr-branch>` instead of a plain
push.

Never `git checkout main` — in a linked worktree it fails because `main` is
checked out in the primary worktree.

### 2. Read all feedback

Per the code-host doc's read-feedback operation. GitHub default:

```bash
# Top-level comments
gh pr view <PR> --comments

# Review threads (inline)
gh api repos/{owner}/{repo}/pulls/<PR>/comments \
  --jq '[.[] | {id, path, line, body, in_reply_to_id}]'

# Review summaries
gh api repos/{owner}/{repo}/pulls/<PR>/reviews \
  --jq '[.[] | select(.body != "") | {id, state, body}]'
```

Collect: unresolved inline threads, review summary comments, top-level PR comments.

Refuse if nothing to act on — no feedback found.

### 3. Implement fixes

- Address every unresolved comment
- Keep changes minimal — only what feedback requests
- Do not refactor unrelated code
- While iterating on a fix, run **only the test file covering it**, with the
  project's quietest reporter: `pnpm test <path/to/the.test.ts> --reporter=dot`
  (or `--silent`, per the project)
- After **all** fixes are applied — once, not per comment — run the project's
  checks (see `AGENTS.md` / `CLAUDE.md` for the exact commands), typically:

```bash
pnpm typecheck
pnpm test --reporter=dot
```

Fix failures before committing; re-run just the failing file or test name to
see why, never the whole suite again.

### 4. Commit and push

```bash
git add <files you changed>   # stage by path — never `git add -p` (interactive) or `git add -A`
git commit -m "fix(pr): address review comments on #<PR>"
git push origin <branch>      # from a local fix/pr-<PR>: git push origin HEAD:<pr-branch>
```

### 5. Reply to threads

For each thread addressed, reply per the code-host doc. GitHub default:

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/comments/<COMMENT_ID>/replies \
  --method POST \
  --field body="Fixed in <commit-sha>: <one-line description of what changed>."
```

### 6. Report

List each comment addressed and what was done. Flag any comment skipped and why.

If the fixes surfaced a genuine discovery — something no repo doc answered
that cost you a failed approach or cross-file reverse-engineering — record it
on the PR (the comment-on-a-change operation) so the docs harvest can pick
it up. GitHub default:

```bash
gh pr comment <PR> --body "## Discoveries
- <one line, written for the next agent>"
```

Same bar as implement-issue's Discoveries section: most fix jobs have none;
skip the comment entirely then.

## Rules

- One commit for all fixes (not one per comment)
- Reply to every thread you address
- If a comment is unclear: make the most reasonable interpretation, implement
  it, and state your interpretation in the thread reply (unattended — there is
  no one to ask). If a comment is wrong, say why in the reply instead of
  implementing it
- If a fix would break tests: report it, do not force-push broken code
- Thread resolution follows the code-host doc: GitHub resolves on push
  automatically (never resolve by hand); other hosts may need an explicit
  resolve after the reply (GitLab does)
