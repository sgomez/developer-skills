---
name: fix-pr
description: Reads all unresolved review comments and threads on a PR, implements the fixes, pushes, and replies to each thread. Local replacement for the agent-implement-pr GitHub workflow. Use when user says "fix pr comments", "address review", "/fix-pr", or wants to respond to PR review feedback.
---

# Fix PR

Reads review comments, implements fixes, pushes, replies to threads.

## Invoke

```
/fix-pr         # fixes current branch PR
/fix-pr 42      # fixes PR #42
```

## Flow

### 1. Identify and check out the PR

```bash
gh pr view <PR> --json number,title,headRefName,state
```

Refuse if PR is closed or merged.

If the current branch is not the PR branch (the /developer pipeline runs this
in a fresh worktree), check it out first:

```bash
gh pr checkout <PR>
```

Never `git checkout main` — in a linked worktree it fails because `main` is
checked out in the primary worktree.

### 2. Read all feedback

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
- After all fixes are applied: run the project's checks (see `AGENTS.md` / `CLAUDE.md` for the exact commands), typically:

```bash
pnpm typecheck
pnpm test
```

Fix failures before committing.

### 4. Commit and push

```bash
git add <files you changed>   # stage by path — never `git add -p` (interactive) or `git add -A`
git commit -m "fix(pr): address review comments on #<PR>"
git push origin <branch>
```

### 5. Reply to threads

For each thread addressed, reply:

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/comments/<COMMENT_ID>/replies \
  --method POST \
  --field body="Fixed in <commit-sha>: <one-line description of what changed>."
```

### 6. Report

List each comment addressed and what was done. Flag any comment skipped and why.

## Rules

- One commit for all fixes (not one per comment)
- Reply to every thread you address
- If a comment is unclear: make the most reasonable interpretation, implement
  it, and state your interpretation in the thread reply (unattended — there is
  no one to ask). If a comment is wrong, say why in the reply instead of
  implementing it
- If a fix would break tests: report it, do not force-push broken code
- Do not resolve threads — GitHub resolves on push automatically
