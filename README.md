# developer-skills

Unattended spec delivery for [Claude Code](https://claude.com/claude-code):
you write specs, a pipeline of isolated agents implements every sub-issue —
triage → build → review → fix → merge — and pings you when it's done.

```
/developer <spec-issue>
        │
        ▼
   ┌────────────┐  complexity tier    ┌─────────────┐
   │ dispatcher │ ───────────────────▶│ code-author │──▶ draft PR
   │  (sonnet)  │    sonnet/opus      │ (worktree)  │
   └────────────┘                     └─────────────┘
                                            │
                                            ▼
                    NEEDS_FIXES      ┌───────────────┐
        ┌──────────────────────────  │ diff-reviewer │
        ▼                            │    (opus)     │
  ┌─────────────┐    re-review       └───────────────┘
  │ code-author │ ──────────────────▶       │ CLEAN
  │ (fix, ≤3×)  │                           ▼
  └─────────────┘                    merge (auto) or hand
                                     off ready-to-merge,
                                     next sub-issue …
```

- **Configurable defaults** — `/setup-developer-skills` asks how the pipeline
  should run in this repo and writes `docs/agents/developer-defaults.md`;
  per-run flags (`--parallel`/`--sequential`, `--auto-merge`/`--no-auto-merge`)
  override it. Factory defaults: **parallel execution, manual merge**.
- **Parallel by default, sequential on demand** — independent sub-issues
  (per `Blocked by` order) are built concurrently in waves; merge conflicts
  between sibling PRs are resolved by an extra opus fix worker before each
  (always serialized) merge. `sequential` delivers one sub-issue fully before
  the next — with auto-merge, each PR then branches from a `main` that
  already contains the previous one, so merges never conflict.
- **Model-tiered** — a `dispatcher` agent scores each sub-issue
  (trivial/standard → `sonnet`, complex → `opus`); the fixer
  escalates one tier per fix cycle.
- **Unattended with an escape hatch** — max 3 review→fix cycles, then the
  sub-issue is labeled `ready-for-human`, commented on the spec, and the loop
  moves on. Push notification with the tally at the end.
- **Isolated** — every worker runs in its own git worktree; the orchestrator
  never touches your checkout.
- **Two-party by construction** — the `diff-reviewer` posts COMMENT
  reviews only (the CLEAN summary is the pipeline's approval signal), and
  marking ready and merging stay with the orchestrator. No agent holds
  approval authority over agent-authored code.

> By default `/developer` does **not** merge: a CLEAN PR is marked ready and
> handed to you, with the wrap-up listing the merge queue in dependency
> order. Opt into `merge: auto` at setup (or pass `--auto-merge`) and it
> **merges PRs to `main` unattended** when the reviewer verdict is CLEAN —
> the `diff-reviewer` (Opus) is then the only gate.

## Claude Code first

The full pipeline runs **only on Claude Code**. The skills follow the
cross-agent `SKILL.md` convention, but everything that makes the pipeline
work is Claude-specific: the subagent definitions (`agents/*.md` frontmatter
with `model:`/`effort:`), the Agent-tool orchestration with per-spawn model
override and **worktree isolation**, and the push notification at the end.
Other agentic tools (Cursor, Codex, etc.) use different agent file formats
and have no equivalent of these primitives.

The worker agents and skills (not the orchestration) also run on
**Google Antigravity** — see [Antigravity](#antigravity) below.

## Install

### The Claude Code plugin

Installs the skills **and the three subagents** in one step:

```
/plugin marketplace add sgomez/developer-skills
/plugin install developer-skills@sgomez
```

Plugin components are namespaced: the skills appear as
`/developer-skills:developer`, `/developer-skills:setup-developer-skills`,
etc., and the agents as `developer-skills:dispatcher` and friends.

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
| `tdd` | Recommended. `implement-issue` follows TDD where tests exist. |
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
   `docs/agents/code-host.md`.
2. Patch `docs/agents/issue-tracker.md` with the pipeline's **Delivery
   operations** — how `/developer` reads issues, discovers children (native
   sub-issues on GitHub), checks blockers, comments, labels, and closes.
3. Check the three plugin agents are loaded: `dispatcher`, `code-author`,
   `diff-reviewer`.
4. Ensure the `ready-for-agent` / `ready-for-human` labels (or the tracker's
   equivalent) exist.
5. Ask for the repo's run defaults — parallel vs sequential execution,
   auto vs manual merge — and write them to
   `docs/agents/developer-defaults.md`. If you pick auto-merge, it offers to
   pre-approve the needed CLI permissions (see below) so the unattended
   merge doesn't die on a permission prompt.

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
`/setup-developer-skills` offers to write this configuration for you (the
merge rules only when you chose `merge: auto`), adapted to your code host —
split across two files because they are read from different scopes.
Expect a permission prompt when it writes them — `.claude/` settings are
protected paths, so your approval at that prompt is the authorization (on
a denial, the skill prints the blocks for you to paste by hand). The
GitHub version by hand (replace `OWNER/REPO`; GitLab is the same shape
with the `glab` equivalents):

**`.claude/settings.json`** (shared, committable — pre-approves the `gh`
calls; explicit allow rules resolve *before* the auto-mode classifier runs):

```json
{
  "permissions": {
    "allow": [
      "Bash(gh pr ready:*)",
      "Bash(gh pr comment:*)",
      "Bash(gh pr merge:*)",
      "Bash(gh api repos/OWNER/REPO/pulls/*/reviews*)"
    ]
  }
}
```

**`.claude/settings.local.json`** (still per-project, but gitignored —
this rule embeds `<plugin-root>`, the plugin's install path on *this*
machine, which would break for teammates if committed; put it in
`~/.claude/settings.json` instead if you'd rather allow the bundled script
once for every project):

```json
{
  "permissions": {
    "allow": [
      "Bash(bash <plugin-root>/skills/developer/scripts/cleanup-worktrees.sh:*)"
    ]
  }
}
```

- **`permissions.allow`** pre-approves exactly the writes the pipeline needs:
  the reviews API (the diff-reviewer posts the inline review) and
  `gh pr ready` (the orchestrator flips the PR out of draft),
  `gh pr comment` (fix-pr replies to threads, escalation comments),
  `gh pr merge` (the orchestrator's auto-merge), and `cleanup-worktrees.sh`
  (the wrap-up sweep).

Scoping the reviews-API rule to your repo (rather than `gh api:*`) keeps the
blast radius small; the ready/comment/merge rules are gh-subcommand-scoped
and safe to allow globally in `~/.claude/settings.json` if you prefer.

## Antigravity

The Antigravity CLI (`agy`) imports Claude Code plugins natively, so the
whole repo installs straight from GitHub — skills and agents included:

```bash
agy plugin install https://github.com/sgomez/developer-skills
```

It clones the repo into `~/.gemini/config/plugins/developer-skills` and
converts the Claude-format `agents/*.md` and `skills/` on load. Reinstall to
update; `agy plugin list` / `agy plugin uninstall developer-skills` to manage.

Caveats: all five skills are imported, including the `/developer`
orchestrator, and Antigravity does have worktree isolation for agents. What
it lacks is per-spawn model tiers and `effort:` — subagents run on
Antigravity's own models, so the `dispatcher`'s sonnet/opus triage
doesn't steer which model builds each sub-issue. The unattended loop is
best-effort outside Claude Code.

## Requirements

- A configured issue tracker and code host (`/setup-developer-skills` writes
  both docs). First-class: **GitHub** ([`gh` CLI](https://cli.github.com/)
  authenticated), **GitLab** ([`glab` CLI](https://gitlab.com/gitlab-org/cli)
  authenticated), and **local** (markdown issues under `.scratch/`, changes
  as local branches — no remote needed). Other trackers/hosts work as
  freeform configuration.
- Claude Code with subagents and worktree isolation (any recent version).
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
  dispatcher.md             # complexity triage — pinned sonnet, effort: low
  code-author.md            # builder/fixer — model chosen per sub-issue
  diff-reviewer.md          # merge gate — pinned opus, effort: high
skills/
  developer/                # orchestrator: spec loop, fix cycles, merge policy
    LOCAL-HOST.md           # read only when the host/tracker is local
    MERGE-FIX.md            # read at the first merge conflict
    WRAP-UP.md              # read once, when the loop ends
  implement-issue/          # issue → branch → TDD → checks → draft PR
  review-pr/                # diff review → inline review → verdict
  fix-pr/                   # address review threads → push → reply
  setup-developer-skills/   # one-time repo setup (incl. run-defaults template)
    code-host-*.md          # code-host templates (github / gitlab / local)
    delivery-ops-*.md       # issue-tracker Delivery operations templates
```
