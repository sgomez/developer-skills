# developer-skills

Unattended PRD delivery for [Claude Code](https://claude.com/claude-code):
you write PRDs, a pipeline of isolated agents implements every sub-issue —
triage → build → review → fix → merge — and pings you when it's done.

```
/developer <prd-issue>
        │
        ▼
   ┌────────────┐  complexity tier    ┌─────────────┐
   │ dispatcher │ ───────────────────▶│ code-author │──▶ draft PR
   │  (sonnet)  │  haiku/sonnet/opus  │ (worktree)  │
   └────────────┘                     └─────────────┘
                                            │
                                            ▼
                    NEEDS_FIXES      ┌───────────────┐
        ┌──────────────────────────  │ diff-reviewer │
        ▼                            │    (opus)     │
  ┌─────────────┐    re-review       └───────────────┘
  │ code-author │ ──────────────────▶       │ CLEAN
  │ (fix, ≤3×)  │                           ▼
  └─────────────┘                    auto-merge to main,
                                     next sub-issue …
```

- **Sequential and dependency-aware** — sub-issues are delivered in
  `Blocked by` order; each PR branches from a `main` that already contains
  the previous one.
- **Model-tiered** — a `dispatcher` agent scores each sub-issue
  (trivial → `haiku`, standard → `sonnet`, complex → `opus`); the fixer
  escalates one tier per fix cycle.
- **Unattended with an escape hatch** — max 3 review→fix cycles, then the
  sub-issue is labeled `ready-for-human`, commented on the PRD, and the loop
  moves on. Push notification with the tally at the end.
- **Isolated** — every worker runs in its own git worktree; the orchestrator
  never touches your checkout.

> ⚠️ `/developer` **auto-merges PRs to `main`** when the reviewer verdict is
> CLEAN. The `diff-reviewer` (Opus) is the only gate. If you want a human
> merge gate, edit the Merge step in `skills/developer/SKILL.md`.

## Claude Code only

This pipeline runs **only on Claude Code**. The skills follow the
cross-agent `SKILL.md` convention, but everything that makes the pipeline
work is Claude-specific: the subagent definitions (`agents/*.md` frontmatter
with `model:`/`effort:`), the Agent-tool orchestration with per-spawn model
override and **worktree isolation**, and the push notification at the end.
Other agentic tools (Cursor, Codex, etc.) use different agent file formats
and have no equivalent of these primitives.

## Install

### Option A — Claude Code plugin (recommended)

Installs the skills **and the three subagents** in one step:

```
/plugin marketplace add sgomez/developer-skills
/plugin install developer-skills@sgomez
```

Plugin components are namespaced: the skills appear as
`/developer-skills:developer`, `/developer-skills:setup-developer-skills`,
etc., and the agents as `developer-skills:dispatcher` and friends.

### Option B — `npx skills` (skills only)

```bash
npx skills add sgomez/developer-skills
```

This route cannot install agents — `/setup-developer-skills` copies them into
`.claude/agents/` for you (they're bundled inside the setup skill).

### Dependencies (both options)

This repo depends on [mattpocock/skills](https://github.com/mattpocock/skills)
for PRD authoring and repo configuration. Install the ones the pipeline needs
with `--skill`:

```bash
npx skills add mattpocock/skills --skill setup-matt-pocock-skills,to-prd,to-issues,tdd,grilling
```

(or `npx skills add mattpocock/skills` and pick interactively / `--skill '*'`
for everything.)

| Skill | Why it's needed |
|---|---|
| `setup-matt-pocock-skills` | **Required.** Creates `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`, which every skill here reads. |
| `to-prd` | **Required.** Publishes the PRD issue the pipeline consumes. |
| `to-issues` | **Required.** Breaks the PRD into sub-issues with `Parent` / `Blocked by` ordering. |
| `tdd` | Recommended. `implement-issue` follows TDD where tests exist. |
| `grilling` / `grill-me` | Recommended. Interview yourself into a solid PRD before `/to-prd`. |
| `triage` | Optional. Shares the same label vocabulary. |

## Setup (once per repo)

```
/setup-developer-skills
```

It will:

1. Run `/setup-matt-pocock-skills` first if the repo isn't configured yet.
2. Patch `docs/agents/issue-tracker.md` so child issues are created as
   **GitHub native sub-issues** (that's how `/developer` discovers work —
   body-text references are invisible to it).
3. Install three agents into `.claude/agents/`: `dispatcher`, `code-author`,
   `diff-reviewer`.
4. Ensure the `ready-for-agent` / `ready-for-human` labels exist.

## Requirements

- GitHub repo + [`gh` CLI](https://cli.github.com/) authenticated
  (`gh auth status`). GitLab / local trackers are not supported.
- Claude Code with subagents and worktree isolation (any recent version).

## Usage

```
/developer <prd-issue>            # deliver every open sub-issue, in order
/developer <issue>                # plain issue (no sub-issues) → deliver just it
/developer <prd> <subissue>       # deliver one specific sub-issue
/implement-issue 42               # manual: issue → branch → TDD → draft PR
/review-pr 42                     # manual: review a PR, post inline comments
/fix-pr 42                        # manual: address unresolved review threads
```

The intended loop: write PRDs with `/grilling` + `/to-prd` + `/to-issues`,
then hand each PRD to `/developer` and go write the next one.

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
  developer/                # orchestrator: PRD loop, fix cycles, auto-merge
  implement-issue/          # issue → branch → TDD → checks → draft PR
  review-pr/                # diff review → inline GitHub review → verdict
  fix-pr/                   # address review threads → push → reply
  setup-developer-skills/   # one-time repo setup
    agents/                 # copy of agents/ bundled for the npx-skills route
```

Contributor note: `agents/` and `skills/setup-developer-skills/agents/` must
stay identical — the first serves the plugin route, the second travels with
the setup skill on the `npx skills` route (which only copies skill folders).
