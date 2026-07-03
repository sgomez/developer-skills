---
name: developer
description: Orchestrates unattended PRD delivery — loops over a PRD's native sub-issues in dependency order, dispatching architect (complexity triage), code-author (implement), and diff-reviewer (review) workers per sub-issue, with a review→fix cycle until CLEAN and auto-merge to main. Use when user says "/developer", "deliver this PRD", "deliver this sub-issue", or wants the build→review→fix pipeline.
---

# Developer (orchestrator)

Drives the triage → build → review → fix → merge pipeline across isolated
subagent workers, looping over every sub-issue of a PRD unattended. Each
worker gets a **clean context** — the only thing it knows is the arguments you
pass in its prompt. You (the orchestrator) hold the state between steps.

## Invoke

```
/developer <issue>              # PRD with sub-issues → deliver them all, in order
                                # plain issue → deliver just that one
/developer <prd> <subissue>     # deliver a single specific sub-issue
```

If no issue number is given, ask for it and stop. Do not guess issue numbers.

> **Namespacing.** Installed as a Claude Code plugin, skills and agents carry
> the plugin prefix: the skills appear as `developer-skills:<name>` and the
> subagents as `developer-skills:architect` / `developer-skills:code-author` /
> `developer-skills:diff-reviewer`. Use the names exactly as they appear in
> your available-skills and available-agents lists; the short names below
> refer to whichever form is installed.

## Workers (subagents)

| Step   | Subagent        | Model                    | Isolation  | Skill it runs     |
|--------|-----------------|--------------------------|------------|-------------------|
| triage | `architect`     | sonnet (pinned)          | —          | (reads the issue) |
| build  | `code-author`   | chosen by triage         | `worktree` | `implement-issue` |
| review | `diff-reviewer` | opus (pinned)            | `worktree` | `review-pr`       |
| fix    | `code-author`   | escalates per cycle      | `worktree` | `fix-pr`          |

Spawn each via the **Agent** tool with the matching `subagent_type`. Pass
`isolation: "worktree"` to every code-author and diff-reviewer spawn. Pass
`model` explicitly to code-author spawns (triage decides the tier). Never run
the skills yourself in the main context — the point is isolation.

## Context economy

The loop may cover many sub-issues; your context must survive all of them.

- **Never read issue or PR bodies yourself.** Workers read them in their own
  disposable contexts. You only run the cheap listing commands below.
- From each worker, keep only its final `RESULT` line.
- Track per sub-issue: number, chosen model, PR number, verdict, fix cycles,
  outcome (merged / escalated / blocked).

## Step 0 — Publish context docs before anything else

Workers branch from `origin/main`, so any domain-context file that is not
committed **and pushed** is invisible to them. Grilling/PRD sessions edit
these files but do not commit them. Before dispatching any worker:

```bash
git status --porcelain -- CONTEXT-MAP.md '**/CONTEXT.md' docs/adr docs/agents
```

If anything shows up, stage **only those paths** (never the user's unrelated
work-in-progress), commit on the current branch (must be `main` — if not,
stop and tell the user), and push:

```bash
git add CONTEXT-MAP.md '**/CONTEXT.md' docs/adr docs/agents
git commit -m "docs(domain): publish context map and ADR updates"
git push origin main
```

If the push is rejected, stop and report — do not rebase or force anything.
This is the flow's start, before going unattended; the user is still there to
resolve it.

## Mode detection

Query native GitHub sub-issues of the given issue (infer OWNER/REPO from
`git remote -v`):

```bash
gh api graphql -f query='
{
  repository(owner:"OWNER", name:"REPO") {
    issue(number: N) {
      subIssues(first: 50) { nodes { number title state } }
    }
  }
}' --jq '.data.repository.issue.subIssues.nodes'
```

- **Open sub-issues exist → PRD mode**: loop over all of them (below).
- **No sub-issues → single mode**: run the delivery pipeline once on the given
  issue, with the issue itself as spec (no separate PRD number).
- **Two arguments given**: run the delivery pipeline once on `<subissue>` with
  `<prd>` as the PRD. Skip the loop.

## PRD loop

Repeat while open sub-issues remain:

1. **Pick the next unblocked sub-issue**: for each open sub-issue (lowest
   number first), check its blockers without reading full bodies:

   ```bash
   gh issue view <N> --json body --jq '.body' | grep -A3 -i "blocked by"
   gh issue view <BLOCKER> --json state --jq '.state'   # must be CLOSED
   ```

   Take the first open sub-issue whose blockers are all closed. Skip
   sub-issues you already escalated this run (and, naturally, anything they
   block stays blocked).

2. Run the **delivery pipeline** on it.

3. On **merged** → next iteration. On **escalated/blocked** → record it,
   next iteration.

4. When no deliverable sub-issue remains (all closed, or the rest are blocked
   by escalated ones) → **wrap-up**.

## Delivery pipeline (per sub-issue)

### 1. Triage

Spawn `architect`:

> Triage issue #`<subissue>`. Score its implementation complexity per your
> rubric. End with the `RESULT complexity=… model=… reason=…` line.

Parse `model=<tier>`. On any malformed result, default to `opus`.

### 2. Build

Spawn `code-author` with `model: <tier>` and `isolation: "worktree"`:

> BUILD job. PRD issue #`<prd>`, sub-issue #`<subissue>`.
> Read the PRD for context, then run the implement-issue skill on the
> sub-issue. You are in an isolated worktree — branch from origin/main.
> End with the `RESULT pr=… url=…` line.

- `RESULT blocked …` → **escalate** (see below) and move to the next
  sub-issue.
- `RESULT pr=<PR> url=<URL>` → keep `<PR>`, continue.

### 3. Review

Spawn `diff-reviewer` with `isolation: "worktree"`:

> Review PR #`<PR>`. Check it out with `gh pr checkout` in your worktree, run
> the review-pr skill on it. End with the `RESULT verdict=…` line.

- `verdict=CLEAN` → go to **Merge**.
- `verdict=NEEDS_FIXES` → enter the fix cycle.

### 4. Fix cycle (max 3)

For cycle `c` = 1, 2, 3:

1. Fixer model: cycle 1 uses the build tier, each later cycle escalates one
   tier (haiku → sonnet → opus; opus stays opus).
2. Spawn `code-author` with that model and `isolation: "worktree"`:

   > FIX job. PR #`<PR>`. Check it out with `gh pr checkout` in your worktree,
   > run the fix-pr skill to address all review threads.
   > End with the `RESULT pr=… url=…` line.

   `RESULT blocked …` → **escalate**, next sub-issue.
3. Re-review: spawn `diff-reviewer` again (same prompt as step 3, mention it
   is a re-review after a fix pass).
   - `CLEAN` → **Merge**.
   - `NEEDS_FIXES` and `c < 3` → next cycle.
   - `NEEDS_FIXES` and `c = 3` → **escalate** (do NOT merge), next sub-issue.

### 5. Merge

Never touch local git state — your checkout may be in use by the user. Merge
remotely:

```bash
gh pr merge <PR> --merge --delete-branch
```

`Closes #<subissue>` in the PR body closes the sub-issue on merge — verify:

```bash
gh issue view <subissue> --json state --jq '.state'   # expect CLOSED
```

If the merge fails (conflict with a previous merge), treat it as one extra fix
cycle: spawn a `code-author` FIX job with model `opus` prompting it to update
the branch from origin/main, resolve conflicts, and push — then merge again.
If it still fails, **escalate**.

## Escalation

When a sub-issue is blocked, non-convergent after 3 fix cycles, or unmergeable:

```bash
gh issue edit <subissue> --add-label "ready-for-human"
gh issue comment <subissue> --body "Escalated by /developer: <reason>. PR: <url or none>."
gh issue comment <prd> --body "Sub-issue #<subissue> escalated: <one-line reason>."
```

Leave the PR open (never merge an unclean PR). Continue the loop with the
next unblocked sub-issue.

## Wrap-up

1. **Push notification** (PushNotification tool):
   `PRD #<prd>: <N> merged, <M> escalated, <K> still blocked.`
2. **Chat summary** — one table: sub-issue, model used, PR, fix cycles,
   outcome. List escalated sub-issues with reasons so the user can pick them
   up.

## Rules

- Strict sequential: one sub-issue fully delivered (merged or escalated)
  before the next starts — each PR must branch from a main that already
  contains the previous one.
- Unattended: never stop to ask the user anything mid-loop. Escalate via
  labels/comments and keep going.
- Each worker is stateless: pass everything it needs in its prompt; never
  assume it can see prior steps.
- Never run `git checkout`, `git pull`, or any state-changing git command in
  the main context — the only exception is Step 0's scoped commit+push of
  context docs, before the loop starts.
- Only spawn the fix worker when the review said `NEEDS_FIXES`.
