---
name: developer
description: Orchestrates unattended spec delivery — loops over a spec's child issues in dependency order, dispatching code-author (implement) and diff-reviewer (review) workers per sub-issue — each build's model comes from the sub-issue's own ## Complexity section, with a review→fix cycle until CLEAN, then merging per the repo's merge policy. The orchestration runs as a dynamic workflow (workflow.js next to this file); this skill resolves the run config, launches it and reports. Tracker- and host-agnostic — issues and changes live wherever docs/agents/issue-tracker.md and docs/agents/code-host.md say (GitHub via gh is the factory default). Factory defaults are parallel execution and manual merge; repo defaults live in docs/agents/developer-defaults.md and per-run flags (--parallel/--sequential, --auto-merge/--no-auto-merge) override them. Use when user says "/developer", "deliver this spec" (or "deliver this PRD"), "deliver this sub-issue", or wants the build→review→fix pipeline.
---

# Developer (launcher)

The build → review → fix → merge pipeline runs as a **dynamic workflow**:
`workflow.js`, next to this file. Its control flow — dependency order, the
three-worker cap, fix cycles, the checks gate, serial merges, the conflict
queue, escalation, wrap-up — is code, so no model re-reads a growing context
on every worker result. Your part is small: publish the context docs, resolve
the run config, launch the workflow, report what it returns.

## Invoke

```
/developer <issue>              # spec with sub-issues → deliver them all
                                # plain issue → deliver just that one
/developer <spec> <subissue>    # deliver a single specific sub-issue

Flags (override the repo defaults — see Run configuration):
  --parallel | --sequential       # spec mode: concurrent vs one-at-a-time
  --auto-merge | --no-auto-merge  # merge CLEAN PRs vs leave them ready
```

If no issue number is given, ask for it and stop; never guess one. Accept
the bare words `parallel` / `sequential` as synonyms of the flags.

> **Namespacing.** Installed as a plugin, the workers are
> `developer-skills:code-author` and `developer-skills:diff-reviewer`; the
> workflow names them that way. If your available-agents list shows other
> names, stop and say so — the plugin is not loaded as expected.

## 1. Publish context docs

Workers branch from `origin/main`, so a domain-context file that is not
committed **and pushed** is invisible to them:

```bash
git status --porcelain -- CONTEXT-MAP.md '**/CONTEXT.md' docs/adr docs/agents AGENTS.md CLAUDE.md
```

If anything shows up, stage **only those paths**, commit on the current branch
(must be `main` — if not, stop and tell the user) and push:

```bash
git add CONTEXT-MAP.md '**/CONTEXT.md' docs/adr docs/agents AGENTS.md CLAUDE.md
git commit -m "docs(domain): publish context map and ADR updates"
git push origin main
```

If the push is rejected, stop and report — never rebase or force. A local
tracker or code host changes this step: see `LOCAL-HOST.md`.

## 2. Run configuration

Read, in **one** call, `docs/agents/developer-defaults.md`,
`docs/agents/code-host.md`, the `## Delivery operations` section of
`docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md` — the
annexes (`code-host-ci.md`, `issue-authoring.md`) are not yours to read.
Missing docs → GitHub defaults (suggest `/setup-developer-skills` if that
looks wrong).

Two knobs — CLI flag > repo default > factory default; ignore any other key:

| Knob        | Values                    | Factory default |
|-------------|---------------------------|-----------------|
| `execution` | `parallel` / `sequential` | `parallel`      |
| `merge`     | `auto` / `manual`         | `manual`        |

- **`merge: auto`** — a CLEAN verdict leads to the checks gate and the merge.
  The committed `merge: auto` line is the user's standing authorization.
- **`merge: manual`** — the pipeline stops at CLEAN with the PR marked ready;
  anything blocked by a ready-to-merge sub-issue stays blocked this run.
- A **local code host** supports `manual` only: override `auto` and say so.

State it in one line, e.g.
`Run config: execution=parallel, merge=manual (repo defaults)`.

## 3. Launch the workflow

Call **Workflow** with `scriptPath: "<skill-dir>/workflow.js"` (this skill's
own directory, absolute) and `args`:

| Arg            | Value |
|----------------|-------|
| `spec`, `sub`  | the issue numbers given (`sub` only with two arguments) |
| `execution`, `merge` | the resolved knobs |
| `github`       | `true` when `code-host.md` says the host is GitHub |
| `ci`           | `false` when `code-host.md` says `CI: none`, else `true` |
| `localHost`, `localTracker` | `true` when the respective doc says `local` |
| `scripts`      | `<skill-dir>/scripts`, absolute |
| `root`         | the primary checkout's absolute path (`git rev-parse --show-toplevel`) |
| `label`        | the escalation label from `triage-labels.md` (`ready-for-human` by default) |
| `date`         | today, `YYYY-MM-DD` |

The workflow runs in the background; say in one line that it is running and
that `/workflows` shows its progress, then end your turn. **Do not poll.** Its
completion notification brings the result object; then go to step 4.

Never run a step of the pipeline yourself while the workflow runs — no
builds, reviews, merges or conflict resolution in this context. If the user
asks for something the workflow is already doing, say so.

**Interrupted** (the session was stopped, or the workflow failed midway):
within the same session, relaunch with the same `scriptPath` and `args` plus
`resumeFromRunId` — completed agents return their cached results. In a new
session, run `/developer <spec>` again: the plan asks the code host which
sub-issues already have a PR, and resumes each at review or at the fix cycle
instead of rebuilding it.

**A conflict on the human's own merge** (`merge: manual`, mid-run or after):
never resolve it here. Have them abort the half-merge (`git merge --abort`),
then launch the workflow with the same `args` plus `mergeFix: <PR>` — it runs
only the merge-fix job and its cleanup — and tell them to retry the merge
when it reports.

## 4. Report

Read `WRAP-UP.md` and follow it: push notification, chat summary, escalation
questions, the human's merge queue, proposed doc changes, execution report.

## Rules

- **The agent docs are read-only to this pipeline.** `AGENTS.md`,
  `CLAUDE.md`, `CONTEXT-MAP.md`, `docs/adr/` and `docs/agents/` are
  instructions the run obeys. The exceptions are step 1's commit of edits
  the human already made and the harvest's append to
  `docs/agents/delivery-ledger.md`. Anything else the run learns is
  *proposed* in the report.
- Never run `git checkout`, `git pull` or any state-changing git command
  here, except step 1's scoped commit+push.
- If the Workflow tool is not available, stop and say so: dynamic workflows
  must be enabled (`/config`), and in `-p` mode allowed (`Workflow` in the
  permission allow-list). There is no in-context fallback.
