# developer-skills

Unattended spec delivery for [Claude Code](https://claude.com/claude-code):
you write specs, a pipeline of isolated agents implements every sub-issue —
build → review → fix → merge — and pings you when it's done.

```
/developer <spec-issue>
        │
        ▼
   sub-issue's ## Complexity          ┌─────────────┐
   standard → sonnet ────────────────▶│ code-author │──▶ PR into
   complex  → opus                    │ (worktree)  │    agent/developer/spec-<N>
                                      └─────────────┘
                                            │ merge (no CI wait)
                                            ▼
                                  integration branch ◀── next sub-issue …
                                            │ all sub-issues in
                                            ▼
                    NEEDS_FIXES      ┌───────────────┐
        ┌──────────────────────────  │ diff-reviewer │  spec PR, reviewed
        ▼                            │    (opus)     │  whole
  ┌─────────────┐    re-review       └───────────────┘
  │ code-author │ ──────────────────▶       │ CLEAN
  │ (fix, ≤3×)  │                           ▼
  └─────────────┘                    merge into main (auto) or
                                     hand off ready-to-merge
```

- **Configurable defaults** — `/setup-developer-skills` asks how the pipeline
  should run in this repo and writes `docs/agents/developer-defaults.md`;
  per-run flags (`--parallel`/`--sequential`, `--auto-merge`/`--no-auto-merge`)
  override it. Factory defaults: **parallel execution, manual merge**.
- **Orchestrated in code** — the pipeline runs as a Claude Code dynamic
  workflow (`skills/developer/workflow.js`): dependency order, worker cap,
  fix cycles, checks gate and merges are the script's control flow, not a
  model re-reading a growing context on every worker result. Requires
  dynamic workflows enabled in `/config`.
- **One integration branch, one whole-spec review** — sub-issues are built
  from the tip of `agent/developer/spec-<N>` and merged into it with no review of
  their own; the spec PR into `main` is reviewed once, whole, and fixed by a
  single worker — the blocking findings and the `[fix]` ones the review asks
  for even when nothing blocks. Reviewed one PR at a time, sub-issues each grow their own
  copy of a shared helper and nobody sees how their screens interact. A
  single issue gets its own PR and its own review.
- **Parallel by default, sequential on demand** — up to three build and fix
  workers run at once, and a sub-issue starts the moment its `Blocked by`
  sub-issues are integrated; merge conflicts between sibling PRs are resolved
  one at a time by an extra worker (Sonnet, then Opus on a retry) before each
  (always serialized) merge. `sequential` delivers one sub-issue fully before
  the next, so each branches from a tip that already holds the previous one.
- **Model-tiered** — `/to-tickets` rates each sub-issue as it cuts the spec
  (a `## Complexity` section: standard → `sonnet`, complex → `opus`; missing
  → `sonnet`), so no worker is spent scoring tickets; the fixer escalates
  one tier per fix cycle.
- **Unattended with an escape hatch** — max 3 review→fix cycles, then the
  sub-issue is labeled `ready-for-human`, commented on the spec, and the loop
  moves on. Push notification with the tally at the end.
- **Isolated** — every worker runs in its own git worktree; the orchestrator
  never touches your checkout.
- **Two-party by construction** — the `diff-reviewer` posts COMMENT
  reviews only (the CLEAN summary is the pipeline's approval signal), and
  marking ready and merging stay with the orchestrator. No agent holds
  approval authority over agent-authored code.

> By default `/developer` does **not** merge into `main`: the CLEAN spec PR
> is marked ready and handed to you (sub-issues are merged into the
> integration branch either way). Opt into `merge: auto` at setup (or pass
> `--auto-merge`) and it **merges to `main` unattended** when the reviewer
> verdict is CLEAN — the `diff-reviewer` (Opus) is then the only gate.

## Claude Code only

developer-skills is a Claude Code plugin and runs only on Claude Code. The
pipeline is built on Claude-specific pieces: the plugin's subagents
(`agents/*.md` with `model:` and `effort:`), the dynamic workflow that
orchestrates them, per-spawn model tiers, worktree isolation, the plugin's
PreToolUse hooks and the push notification at the end. Other agentic tools —
Cursor, Codex, Gemini or Antigravity — have no equivalent, and are not
supported.

## Install

### The Claude Code plugin

Installs the skills, **the two subagents** and the hooks in one step:

```
/plugin marketplace add sgomez/developer-skills
/plugin install developer-skills@sgomez
```

Plugin components are namespaced: the skills appear as
`/developer-skills:developer`, `/developer-skills:setup-developer-skills`,
etc., and the agents as `developer-skills:code-author` and
`developer-skills:diff-reviewer`.

Restart the session afterwards: plugins load at session start.

### The `next` branch (early access)

Development lands on `next` before it's released. Point the marketplace at the
branch instead of the default one — no checkout needed, same command on any
machine:

```
/plugin marketplace add https://github.com/sgomez/developer-skills.git#next
/plugin install developer-skills@sgomez
```

Restart the session afterwards: plugins load at session start.

**`/plugin update` will not update it.** `next` carries one version for the
whole cycle, so the installer sees nothing new and skips. To pick up new
commits, uninstall and install again. A `next` build names itself in
`claude plugin list`: its version is a pre-release of the release it's working
toward (`0.16.0-next` and the like), never a bare number.

Go back to the published releases by re-adding the marketplace without the ref:

```
/plugin marketplace add sgomez/developer-skills
```

Contributors with a checkout have `scripts/plugin-mode.sh` for all of this —
`dev` (this working tree, uncommitted edits included), `next`, `prod`,
`refresh`, `status`.

### Dependencies

This repo depends on [mattpocock/skills](https://github.com/mattpocock/skills)
(v1.1+) for spec authoring and repo configuration. Install the ones the
pipeline needs with `--skill`:

```bash
npx skills add mattpocock/skills --skill setup-matt-pocock-skills,to-spec,to-tickets,tdd,grill-with-docs,grilling,domain-modeling,resolving-merge-conflicts,wayfinder,ask-matt
```

(or `npx skills add mattpocock/skills` and pick interactively / `--skill '*'`
for everything.)

| Skill | Why it's needed |
|---|---|
| `setup-matt-pocock-skills` | **Required.** Creates `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`, which every skill here reads. |
| `to-spec` | **Required.** Publishes the spec (PRD) issue the pipeline consumes. Replaces `to-prd` (renamed in mattpocock/skills v1.1). |
| `to-tickets` | **Required.** Breaks the spec into sub-issues with `Parent` / `Blocked by` ordering (native sub-issue and blocking links where the tracker has them). Replaces `to-issues` / `to-plan`. |
| `tdd` | Optional. `implement-issue` carries its own red-before-green loop; `tdd` is for when you build by hand. |
| `grill-with-docs` | Recommended. The spec interview for repos with a codebase: a `/grilling` session that also writes `CONTEXT.md` and ADRs — exactly the context docs `/developer`'s Step 0 publishes for its workers. Uses `grilling` + `domain-modeling`. |
| `grilling` / `grill-me` | The interview primitive behind `grill-with-docs`; `grill-me` is the stateless variant for when there's no codebase yet. |
| `domain-modeling` | Used by `grill-with-docs` for the glossary / ADR vocabulary. |
| `resolving-merge-conflicts` | Recommended, **strongly with parallel execution (the default)**. The merge-fix worker runs it to resolve conflicts between sibling PRs before merging. |
| `ask-matt` | Optional. A router over the whole mattpocock/skills set — ask it which skill or flow fits your situation. |
| `wayfinder` | Optional. For plans too big for one session: charts a shared map of investigation tickets on the tracker, resolved one session at a time — then feed the result to `to-spec`. |
| `triage` | Optional. Shares the same label vocabulary. |

## Setup (once per repo)

Two commands, **in this order** — the second builds on the first:

```
/setup-matt-pocock-skills    # 1. Matt's setup: issue tracker, triage labels, domain docs
/setup-developer-skills      # 2. this plugin: code host, delivery ops, agents, run defaults
```

The order is enforced, not just recommended: Matt's setup skill declares
`disable-model-invocation`, so ours cannot run it for you —
`/setup-developer-skills` **refuses to start** when the repo isn't
configured yet (no `docs/agents/issue-tracker.md`) and asks you to run
Matt's first.

`/setup-developer-skills` will:

1. Determine the **code host** (GitHub, GitLab, or local branches — anything
   else as freeform prose) and write its mechanics to
   `docs/agents/code-host.md`, with the CI mechanics in the deferred annex
   `docs/agents/code-host-ci.md`.
2. Patch `docs/agents/issue-tracker.md` with the pipeline's **Delivery
   operations** — how `/developer` reads issues, discovers children (native
   sub-issues on GitHub), checks blockers, comments, labels, and closes — and
   write `docs/agents/issue-authoring.md`, the rules `/to-tickets` follows
   when it *creates* children.
3. Check the two plugin agents are loaded: `code-author`, `diff-reviewer`.
4. Ensure the `ready-for-agent` / `ready-for-human` labels (or the tracker's
   equivalent) exist.
5. Ask for the repo's run defaults — parallel vs sequential execution,
   auto vs manual merge — and write them to
   `docs/agents/developer-defaults.md`.
6. Recommend the Claude Code settings the unattended run needs, for the
   project or globally, and list the entries an earlier version had you add
   that nothing uses any more (see below). It never edits your settings: you
   do.

**Issues and code are independent axes**: issues can live on GitHub, GitLab,
local markdown under `.scratch/` (all first-class), or anywhere you can
describe (Jira, Linear, …); changes can live on GitHub PRs, GitLab MRs, or
local branches. The skills carry the GitHub `gh` mechanics inline as the
factory default and defer to the two docs for everything else. A local code
host runs with `merge: manual` only.

## Permissions (recommended)

`/developer` runs unattended, but the code-host writes it performs — posting
reviews, marking PRs ready, commenting, merging — hit permission prompts by
default. With nobody at the keyboard, one denial means the worker reports
blocked and the sub-issue gets escalated instead of merged.

`/setup-developer-skills` recommends the rules below, adapted to your code
host, and **you add them yourself** — it never writes a settings file. Pick
the scope:

| File | Scope | Good for |
|---|---|---|
| `.claude/settings.json` | This project, committed | The host CLI rules and `Workflow`, for the whole team |
| `.claude/settings.local.json` | This project, only you (gitignored) | The same rules if you'd rather not commit them; the scripts' rules |
| `~/.claude/settings.json` | Every project on this machine | Configure once: the scripts, the `gh pr` rules and `Workflow` |

The GitHub rules (replace `OWNER/REPO`, or use `repos/*/pulls/*/reviews*` in
the global file; GitLab is the same shape with the `glab` equivalents):

```json
{
  "permissions": {
    "allow": [
      "Bash(gh pr ready:*)",
      "Bash(gh pr comment:*)",
      "Bash(gh pr merge:*)",
      "Bash(gh api repos/OWNER/REPO/pulls/*/reviews*)",
      "Bash(git push origin refs/remotes/origin/main:refs/heads/agent/developer/spec-*)",
      "Workflow"
    ]
  }
}
```

The bundled scripts. `<plugin-root>` is the plugin's install path on your
machine; put `*` where its version goes
(`~/.claude/plugins/cache/sgomez/developer-skills/*`), or the rule stops
matching at the next update:

```json
{
  "permissions": {
    "allow": [
      "Bash(bash <plugin-root>/skills/developer/scripts/cleanup-worktrees.sh:*)",
      "Bash(bash <plugin-root>/skills/developer/scripts/checks-gate.sh:*)",
      "Bash(bash <plugin-root>/skills/developer/scripts/spec-plan.sh:*)"
    ]
  }
}
```

What each rule is for:

- **The reviews API and `gh pr ready` / `comment` / `merge`:** the review
  worker posts its review, the orchestrator marks the PR ready, the fixer
  replies to threads and the orchestrator merges.
- **The `git push`:** creates a spec's integration branch from `main`, with
  that exact command and nothing wider.
- **`Workflow`:** launches the orchestration without a prompt. It is
  required in headless (`-p`) runs.
- **The scripts:** the read-only planning call, the CI gate before each
  merge, and the wrap-up's worktree cleanup.

In auto mode the classifier would deny the unattended merge and the fixer's
push onto a PR's branch, even when they are on the allow list. The plugin's
PreToolUse hooks (`hooks/approve-merge.sh` and `hooks/approve-push.sh`)
approve exactly the pipeline's own forms of those two commands, so no
`autoMode` block is needed.

**Remove from earlier versions** — `/setup-developer-skills` lists them if it
finds them:

- An `autoMode` block that authorizes merging PRs for `/developer`, from
  0.4 and 0.9–0.10. The merge hook replaced it.
- Script rules pinned to one plugin version, or pointing at a path that no
  longer exists.
- `Bash(git push origin refs/remotes/origin/main:refs/heads/developer/spec-*)`,
  from pre-release builds. The branch now lives under `agent/developer/`.
- `.claude/agents/dispatcher.md`, `code-author.md` and `diff-reviewer.md`,
  copied into the repo by versions up to 0.15. The plugin ships its own.

## Requirements

- A configured issue tracker and code host (`/setup-developer-skills` writes
  both docs). First-class: **GitHub** ([`gh` CLI](https://cli.github.com/)
  authenticated), **GitLab** ([`glab` CLI](https://gitlab.com/gitlab-org/cli)
  authenticated), and **local** (markdown issues under `.scratch/`, changes
  as local branches — no remote needed). Other trackers/hosts work as
  freeform configuration.
- Claude Code with subagents, worktree isolation and dynamic workflows enabled in `/config`.
- **git ≥ 2.31.** Workers run in linked worktrees and check they are really in
  one — via `git rev-parse --path-format=absolute` — before checking anything
  out. Without that flag the check cannot tell a worktree from a subdirectory
  of your own checkout, and a worker can detach your HEAD.

## Usage

```
/developer <spec-issue>           # deliver every open sub-issue (repo defaults)
/developer <spec-issue> --sequential --auto-merge
                                  # per-run overrides of the repo defaults
/developer <issue>                # plain issue (no sub-issues) → deliver just it
/developer <spec> <subissue>      # deliver one specific sub-issue
/implement-issue 42               # manual: issue → branch → TDD → draft PR
/review-pr 42                     # manual: review a PR, post inline comments
/fix-pr 42                        # manual: address unresolved review threads
```

The intended loop: write specs with `/grill-with-docs` (or `/wayfinder` when
the plan is too big for one session) + `/to-spec` + `/to-tickets`, then hand
each spec to `/developer` and go write the next one.

The division of labour: Matt's skills **plan** (grilling → spec → tickets,
with you in the loop) and offer a hands-on endpoint (`/implement` +
`/code-review` on your current branch). This pipeline is the **AFK
counterpart** of that endpoint: `/developer` launches isolated agents in
clean contexts to build (`implement-issue`), review (`review-pr`) and
validate each ticket unattended, gated by the CLEAN verdict instead of by
you. (Not sure which skill fits? `/ask-matt`.)

## What's in the box

```
.claude-plugin/
  plugin.json               # plugin manifest
  marketplace.json          # lets you /plugin marketplace add sgomez/developer-skills
agents/                     # subagents, auto-loaded by the plugin route
  code-author.md            # builder/fixer — model from the sub-issue's complexity
  diff-reviewer.md          # merge gate — pinned opus, effort: high
hooks/                      # PreToolUse hooks, auto-loaded by the plugin
  approve-merge.sh          # lets the pipeline's own merge past auto mode
  approve-push.sh           # lets a fixer push onto the PR it was sent to fix
  no-ci-logs-in-orchestrator.sh  # keeps raw CI logs out of the orchestrator
  require-background-workers.sh  # refuses foreground worker spawns
skills/
  developer/                # launcher: run config, then the workflow, then the report
    workflow.js             # the orchestrator: dependency order, fix cycles, gate, merges
    LOCAL-HOST.md           # read only when the host/tracker is local
    WRAP-UP.md              # read once, when the workflow reports
    scripts/                # spec-plan.sh, checks-gate.sh (GitHub), cleanup-worktrees.sh
  implement-issue/          # issue → branch → TDD → checks → draft PR
  review-pr/                # diff review → inline review → verdict
  fix-pr/                   # address review threads → push → reply
  setup-developer-skills/   # one-time repo setup (incl. run-defaults template)
    code-host-*.md          # code-host templates (github / gitlab / local)
    code-host-ci-*.md       # deferred CI annex for workers (and non-GitHub gates)
    delivery-ops-*.md       # issue-tracker Delivery operations templates
    issue-authoring-*.md    # deferred annex, read only when creating issues
```
