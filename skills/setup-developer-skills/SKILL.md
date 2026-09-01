---
name: setup-developer-skills
description: Configure this repo for the /developer unattended spec-delivery pipeline — patches the issue tracker doc with the pipeline's Delivery operations, writes docs/agents/code-host.md (GitHub, GitLab or local first-class; anything else as freeform), installs the dispatcher/code-author/diff-reviewer agents, ensures the triage labels exist, and asks for the run defaults written to docs/agents/developer-defaults.md. Requires /setup-matt-pocock-skills to have run first (refuses otherwise). Run once before first use of /developer.
disable-model-invocation: true
---

# Setup Developer Skills

Scaffold the per-repo configuration that the `/developer` pipeline assumes.
This builds **on top of** Matt Pocock's engineering skills setup — it does not
replace it.

Two independent axes get configured, mirroring how the delivery skills read
the repo:

- **Issue tracker** — where issues live (`docs/agents/issue-tracker.md`,
  created by Matt's setup; this skill appends the pipeline's
  `## Delivery operations` section).
- **Code host** — where changes (PRs/MRs/branches) live
  (`docs/agents/code-host.md`, created here).

They may differ (issues in Linear, code on GitHub). **GitHub, GitLab and
local are first-class** — templates ship with this skill. Anything else
(Jira, Linear, Gitea…) is configured as freeform prose, exactly like Matt's
setup handles "other" trackers.

**This skill is the only writer of these docs.** `/developer` and its workers
read `AGENTS.md`, `CLAUDE.md` and everything under `docs/agents/` as
instructions and never edit them — the one exception is
`docs/agents/delivery-ledger.md`, which the harvest appends to because the
dispatcher reads it back. So a doc that has drifted out of date is fixed here
or by the human, and never as a side effect of a delivery run. Two things
follow for this skill:

- **Update against the templates; leave the repo's own prose alone.** These
  docs accumulate repo-specific text that no template contains — why a knob
  was set the way it was, a build trap, a test lane. Bring the *template*
  parts up to date and carry that text through untouched, even when a
  sentence in it looks stale. If something in it is now wrong, say so in the
  chat summary and let the user decide; correcting it is not what an update
  was asked to do.
- **Prefer facts that do not rot.** When you write prose of your own into
  these docs, describe how the repo works, not what some issue's state is
  today. A claim with a date on it goes out of date silently and invites the
  next session to "fix" it.

This is a prompt-driven skill, not a deterministic script. Explore, present
what you found, confirm with the user, then write.

## Process

### 1. Preconditions

- **Matt Pocock's setup must have run first**: check whether
  `docs/agents/issue-tracker.md` exists. If it does not, **stop — scaffold
  nothing**. Matt's `setup-matt-pocock-skills` declares
  `disable-model-invocation: true`, so you cannot run it on the user's
  behalf; only the user can, as a slash command. Tell them:

  > This repo isn't configured yet. Run `/setup-matt-pocock-skills` first
  > (namespaced as `/mattpocock-skills:setup-matt-pocock-skills` when
  > installed as a plugin), then re-run `/setup-developer-skills`.

  If that skill isn't installed at all, point them at this repo's README
  for the install command instead.
- Read `docs/agents/issue-tracker.md` and note which tracker it describes
  (GitHub / GitLab / local markdown / other) — step 3 patches it
  accordingly.

### 2. Determine the code host

Explore first: `git remote -v`.

- **No remote → Local, without asking.** A remote host is impossible
  without a remote, so there is no decision to put to the user — announce
  the inference in one line ("No git remote — code host: local branches
  with a committed change file; reviews live in that file; `merge: auto`
  is unavailable, the pipeline always stops at ready-to-merge and you
  merge by hand") and continue. Only if the user objects to that
  announcement, fall through to **Other**.
- **Remote present → propose, and let the user confirm or override** (they
  may track changes somewhere unexpected, e.g. Jira-driven review):
  - Remote on `github.com` → **GitHub** — verify `gh auth status` succeeds.
  - Remote on `gitlab.com` or a self-hosted GitLab → **GitLab** — verify
    `glab auth status` succeeds.
  - Anything else (or the user overrides) → **Other**: ask the user to
    describe, in a paragraph, how changes are published, reviewed, and
    merged there; you will record it as freeform prose.

Then ask **one more question, whatever the host: is there CI on changes, and
how is its status read?** The answer gates two behaviours — the orchestrator
refuses to merge on red checks, and the reviewer skips its own install and
test run when CI already reports green — so a wrong answer costs either a
merged red build or a duplicated suite. Explore before asking (a
`.github/workflows/` or `.gitlab-ci.yml` in the repo is the answer most of the
time) and confirm; where there is genuinely no CI on changes, record
**`CI: none`** and the pipeline behaves exactly as it did before this question
existed.

Write `docs/agents/code-host.md` from the matching template bundled in this
skill folder (drop the HTML comment on the first line, and fill or delete the
`CI` bullet per the answer above):

- [code-host-github.md](./code-host-github.md)
- [code-host-gitlab.md](./code-host-gitlab.md)
- [code-host-local.md](./code-host-local.md)

For **Other**, write the doc from scratch based on the user's description.
It must answer, operation by operation, what the delivery skills will ask of
it: change ref format · publish a change (draft) · change metadata (branch,
head sha, state) · check out a change in a linked worktree (read-only
review, and fix-that-pushes) · read the diff · read feedback / unresolved
threads · post a review (inline + summary, the CLEAN convention) · mark
ready · reply to a thread · comment on a change · read the last reviewed
revision (the sha the previous review was written against, which is how
`review-pr` scopes a re-review to the fix pass — if the host records no such
thing, say so and the reviewer falls back to the full diff every time) ·
merge (and whether unattended merge is supported at all) · issue auto-close
on merge (yes/no) · CI on changes (none, or how to wait for the checks and
how to read the ones recorded for a head sha).
Anything the user's workflow cannot express (e.g. inline comments), record
the degraded form the skills should use instead.

**Idempotence**: if `docs/agents/code-host.md` already exists, show its
current host and content summary, and ask before rewriting.

### 3. Patch the issue tracker doc with Delivery operations

The `/developer` orchestrator and its workers drive the tracker through a
fixed set of operations (read issue, enumerate children, check blocker,
comment, label, close). Append the section that matches the tracker found in
step 1 (drop the HTML comment on the first line):

- [delivery-ops-github.md](./delivery-ops-github.md) — native GitHub
  sub-issues (also instructs `/to-tickets` to create them)
- [delivery-ops-gitlab.md](./delivery-ops-gitlab.md) — `glab` mechanics +
  `Part of #<parent>` markers
- [delivery-ops-local.md](./delivery-ops-local.md) — `.scratch/` file
  conventions

For **other** trackers, write the `## Delivery operations` section from
scratch with the user: same operation list as above, in their tracker's
terms (issue ref format included). Carry over the two requirements the
bundled templates place on whatever splits a spec into tickets: children must
be **discoverable from the parent** by a mechanic the pipeline can query, and
each child must carry a **`## Spec extract`** section with the parent's
Implementation and Testing Decisions that apply to it, copied verbatim — that
section is what lets a builder work from the ticket alone.

**Idempotence**: if a `## Delivery operations` heading already exists in
`docs/agents/issue-tracker.md`, replace that section instead of appending a
duplicate. Same for the legacy heading
`## Parent/child issues MUST be native sub-issues` (written by older
versions of this skill) — replace it with the new section.

### 4. Check the agents are available

The three worker agents ship with the plugin and are already loaded,
namespaced as `developer-skills:dispatcher`, `developer-skills:code-author`
and `developer-skills:diff-reviewer`:

- `dispatcher` — complexity triage (pinned `sonnet`, `effort: low`)
- `code-author` — implements / fixes (model chosen per sub-issue)
- `diff-reviewer` — review gate before auto-merge (pinned `opus`, `effort: high`)

If this skill's own name is not namespaced (it appears as
`/setup-developer-skills`, not `/developer-skills:setup-developer-skills`),
the plugin is not loaded and `/developer` will not find its workers. **Stop
and tell the user to install the plugin**, then re-run this skill:

```
/plugin marketplace add sgomez/developer-skills
/plugin install developer-skills@sgomez
```

(Plugins load at session start — the user must restart the session after
installing.)

### 5. Ensure the triage labels exist

`/developer` applies `ready-for-human` on escalation, and `implement-issue`
lists work by `ready-for-agent`. Respect any label mapping in
`docs/agents/triage-labels.md`. Mechanics per tracker:

- **GitHub**:

  ```bash
  gh label list --json name --jq '.[].name'
  gh label create ready-for-agent --description "Fully specified, an agent can pick it up" --color 0E8A16 2>/dev/null || true
  gh label create ready-for-human --description "Needs human attention" --color D93F0B 2>/dev/null || true
  ```

- **GitLab**: same pair via
  `glab label create --name ready-for-agent --description "..." --color "#0E8A16"`
  (and `ready-for-human` with `#D93F0B`); `glab label list` first.
- **Local markdown**: nothing to create — the roles are `Status:` line
  values, defined by convention in the tracker doc.
- **Other**: whatever the tracker doc's Delivery operations say "apply a
  triage label" means; if labels must pre-exist there, remind the user to
  create the two above.

### 6. Choose the run defaults

Ask the user three questions (AskUserQuestion, one call, all three):

1. **Execution** — should `/developer` build independent sub-issues in
   parallel waves (recommended: faster; sibling-PR conflicts are resolved by
   merge-fix workers) or sequentially (one sub-issue fully delivered before
   the next)?
2. **Merge** — when the review verdict is CLEAN, should `/developer` merge
   the PR to `main` automatically, or mark it ready and leave the merge to a
   human (recommended)? Be explicit that `auto` means unattended merges to
   `main` with the opus diff-reviewer as the only gate, and that with
   `manual` the sub-issues stay open until the human merges, so dependent
   sub-issues wait for those merges.

   **Skip this question when the code host is local** — `merge: auto` is
   unsupported there (the code-host doc says why); record `merge: manual`
   and tell the user.
3. **Oversized sub-issues** — when triage scores a sub-issue too big to fit
   in one context window, should `/developer` hand it back to a human to
   re-cut (recommended: `escalate`, and the re-cut is usually the cheaper
   fix), or build it anyway at `opus` (`build`) using triage's fault lines
   as the builder's order of work? Recommend `build` to a repo whose tickets
   are deliberately cut large — there the round trip costs more than the
   build.

Write the answers to `docs/agents/developer-defaults.md` from the template
[developer-defaults.md](./developer-defaults.md) (drop the HTML comment on
the first line, set the three answered values in the fenced block).

**Idempotence**: if the file already exists, show the current values, ask
the three questions with the current values as the recommended options, and
rewrite the file.

**Regardless of the merge choice**, the pipeline's code-host writes will
hit permission prompts — and with nobody at the keyboard a single denial
escalates the sub-issue instead of delivering it. Offer to add the
allowlist and the auto-mode context, split across two files because they
are read from different scopes (merge with existing content in both):

- **`.claude/settings.json`** (shared, committable) — the
  `permissions.allow` rules for the host CLI. Narrow allow rules (fixed
  subcommands) resolve **before** the auto-mode classifier and keep the
  review / mark-ready / comment writes from being classified. The **merge is
  the exception**: in auto mode the classifier re-evaluates the pipeline's
  unattended `gh pr merge` as a "merge without human approval" pattern and
  denies it *even when* `gh pr merge` is allow-listed. That single command is
  handled deterministically by this plugin's PreToolUse hook
  (`hooks/approve-merge.sh`) — it grants a PreToolUse `allow`, which runs
  before the classifier, and fires only in `merge: auto` repos. The
  `gh pr merge` allow rule below still spares a prompt when the pipeline runs
  outside auto mode.
- **`.claude/settings.local.json`** (per-project too, but gitignored) —
  the allow rule for the bundled cleanup script: it embeds this machine's
  absolute plugin path, which would break for teammates if committed. A
  user who prefers configuring once may put it in `~/.claude/settings.json`
  instead (the plugin path is the same for all their projects).

Write `permissions` rules only — never an `autoMode` block.

**Expect a permission prompt on these writes.** `.claude/` settings files
are protected paths: no allow rule pre-approves writing them. Show the
user the exact JSON before writing; their approval at the prompt is the
authorization. If the write is denied, do **not** retry or route around
it — print the blocks and the target file paths and have the user paste
them in.

**GitHub** (replace OWNER/REPO from `git remote -v`) — in
`.claude/settings.json`:

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

and in `.claude/settings.local.json`, with `<plugin-root>` resolved to this
plugin's installed location (the directory two levels above this SKILL.md):

```json
{
  "permissions": {
    "allow": [
      "Bash(bash <plugin-root>/skills/developer/scripts/cleanup-worktrees.sh:*)"
    ]
  }
}
```

Drop the merge rule when the user chose `merge: manual` (the
ready/comment/review rules still save prompts during review and fix
cycles).

**GitLab**: the analogous rules —
`"Bash(glab mr update:*)"`, `"Bash(glab mr note:*)"`,
`"Bash(glab mr merge:*)"`,
`"Bash(glab api projects/*/merge_requests/*)"` — plus the same
cleanup-worktrees.sh rule in `.claude/settings.local.json`.

**Local / Other**: no merge or review-posting rules apply (local never
auto-merges and its review is a committed file; for other hosts derive the
allowlist from the commands recorded in `docs/agents/code-host.md`) — but
**still offer the cleanup-worktrees.sh rule**: the wrap-up's `--sweep` is a
pattern-matched worktree removal, exactly the shape the auto-mode
classifier denies, and local runs hit it like any other.

### 7. Report

Summarise what was set up — tracker, code host, chosen defaults — and remind
the user of the flow:

1. Grill/discuss a feature → `/to-spec` publishes the spec (PRD) issue.
2. `/to-tickets <spec>` breaks it into child issues discoverable by the
   pipeline (native sub-issues on GitHub; the tracker doc's equivalent
   elsewhere) with `Blocked by` ordering.
3. `/developer <spec>` delivers them all unattended — triage → build → review
   → fix cycles → merge per the chosen policy — and sends a push
   notification when done.

If they chose `merge: auto`, warn them explicitly: **`/developer` will merge
PRs to `main` unattended when the review verdict is CLEAN.** If they chose
`manual` (or the host forces it), remind them the wrap-up summary lists the
ready-to-merge PRs in dependency order, and that per-run flags
(`--auto-merge`, `--sequential`, …) override the defaults.
