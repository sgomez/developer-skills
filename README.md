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

- **Sequential by default, parallel on demand** — sub-issues are delivered
  in `Blocked by` order; each PR branches from a `main` that already contains
  the previous one, so merges never conflict. Pass `--parallel` to build
  independent sub-issues concurrently in waves instead — faster, at the cost
  of merge conflicts between sibling PRs, which an extra opus fix worker
  resolves before each (still serialized) merge.
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
npx skills add mattpocock/skills --skill setup-matt-pocock-skills,to-prd,to-issues,tdd,grill-with-docs,grilling,domain-modeling,resolving-merge-conflicts,ask-matt
```

(or `npx skills add mattpocock/skills` and pick interactively / `--skill '*'`
for everything.)

| Skill | Why it's needed |
|---|---|
| `setup-matt-pocock-skills` | **Required.** Creates `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`, which every skill here reads. |
| `to-prd` | **Required.** Publishes the PRD issue the pipeline consumes. |
| `to-issues` | **Required.** Breaks the PRD into sub-issues with `Parent` / `Blocked by` ordering. |
| `tdd` | Recommended. `implement-issue` follows TDD where tests exist. |
| `grill-with-docs` | Recommended. The PRD interview for repos with a codebase: a `/grilling` session that also writes `CONTEXT.md` and ADRs — exactly the context docs `/developer`'s Step 0 publishes for its workers. Uses `grilling` + `domain-modeling`. |
| `grilling` / `grill-me` | The interview primitive behind `grill-with-docs`; `grill-me` is the stateless variant for when there's no codebase yet. |
| `domain-modeling` | Used by `grill-with-docs` for the glossary / ADR vocabulary. |
| `resolving-merge-conflicts` | Recommended, **strongly with `--parallel`**. The merge-fix worker runs it to resolve conflicts between sibling PRs before merging. |
| `ask-matt` | Optional. A router over the whole mattpocock/skills set — ask it which skill or flow fits your situation. |
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

## Permissions (recommended)

`/developer` runs unattended, but the GitHub writes it performs — posting
reviews, marking PRs ready, commenting, merging — hit permission prompts by
default. With nobody at the keyboard, one denial means the worker reports
blocked and the sub-issue gets escalated instead of merged. Pre-approve those
`gh` calls in the target repo's `.claude/settings.json` (replace
`OWNER/REPO`):

```json
{
  "permissions": {
    "allow": [
      "Bash(gh pr ready:*)",
      "Bash(gh pr comment:*)",
      "Bash(gh pr merge:*)",
      "Bash(gh api repos/OWNER/REPO/pulls/*/reviews*)"
    ]
  },
  "autoMode": {
    "allow": [
      "$defaults",
      "Merging pull requests in the OWNER/REPO repository (gh pr merge, including --auto/--squash/--delete-branch, or the equivalent gh api merge endpoint) is allowed: the /developer pipeline auto-merges PRs after the diff-reviewer reports CLEAN."
    ]
  }
}
```

- **`permissions.allow`** pre-approves exactly the writes the pipeline needs:
  `gh pr ready` and the reviews API (diff-reviewer posts the inline review and
  flips the PR out of draft), `gh pr comment` (fix-pr replies to threads,
  escalation comments), `gh pr merge` (the orchestrator's auto-merge).
- **`autoMode.allow`** only matters if you run with `"defaultMode": "auto"`:
  auto mode double-checks outward-facing actions in natural language even when
  the command is allowlisted, so it needs a plain-English rule stating that
  merging is intended. Keep `"$defaults"` first to preserve the built-in
  rules.

Scoping the reviews-API rule to your repo (rather than `gh api:*`) keeps the
blast radius small; the other three are gh-subcommand-scoped and safe to allow
globally in `~/.claude/settings.json` if you prefer.

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
Antigravity's own models, so the `dispatcher`'s haiku/sonnet/opus triage
doesn't steer which model builds each sub-issue. The unattended loop is
best-effort outside Claude Code.

## Requirements

- GitHub repo + [`gh` CLI](https://cli.github.com/) authenticated
  (`gh auth status`). GitLab / local trackers are not supported.
- Claude Code with subagents and worktree isolation (any recent version).

## Usage

```
/developer <prd-issue>            # deliver every open sub-issue, in order
/developer <prd-issue> --parallel # build independent sub-issues concurrently
/developer <issue>                # plain issue (no sub-issues) → deliver just it
/developer <prd> <subissue>       # deliver one specific sub-issue
/implement-issue 42               # manual: issue → branch → TDD → draft PR
/review-pr 42                     # manual: review a PR, post inline comments
/fix-pr 42                        # manual: address unresolved review threads
```

The intended loop: write PRDs with `/grill-with-docs` + `/to-prd` +
`/to-issues`, then hand each PRD to `/developer` and go write the next one.
(Not sure which skill fits? `/ask-matt`.)

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
