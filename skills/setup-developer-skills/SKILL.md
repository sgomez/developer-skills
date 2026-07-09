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

Write `docs/agents/code-host.md` from the matching template bundled in this
skill folder (drop the HTML comment on the first line):

- [code-host-github.md](./code-host-github.md)
- [code-host-gitlab.md](./code-host-gitlab.md)
- [code-host-local.md](./code-host-local.md)

For **Other**, write the doc from scratch based on the user's description.
It must answer, operation by operation, what the delivery skills will ask of
it: change ref format · publish a change (draft) · change metadata (branch,
head sha, state) · check out a change in a linked worktree (read-only
review, and fix-that-pushes) · read the diff · read feedback / unresolved
threads · post a review (inline + summary, the CLEAN convention) · mark
ready · reply to a thread · comment on a change · merge (and whether
unattended merge is supported at all) · issue auto-close on merge (yes/no).
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
terms (issue ref format included).

**Idempotence**: if a `## Delivery operations` heading already exists in
`docs/agents/issue-tracker.md`, replace that section instead of appending a
duplicate. Same for the legacy heading
`## Parent/child issues MUST be native sub-issues` (written by older
versions of this skill) — replace it with the new section.

### 4. Install the agents

**If this skill was installed as a Claude Code plugin** (its name appears as
`developer-skills:setup-developer-skills`), the three agents are already
available, namespaced as `developer-skills:dispatcher`,
`developer-skills:code-author`, `developer-skills:diff-reviewer` — skip this
step.

**If it was installed via `npx skills`** (skills only — that route cannot
install agents), copy the three agent definitions bundled in this skill
folder into the repo's `.claude/agents/` directory (create it if missing):

- [agents/dispatcher.md](./agents/dispatcher.md) — complexity triage (pinned `sonnet`, `effort: low`)
- [agents/code-author.md](./agents/code-author.md) — implements / fixes (model chosen per sub-issue)
- [agents/diff-reviewer.md](./agents/diff-reviewer.md) — review gate before auto-merge (pinned `opus`, `effort: high`)

If a file already exists with different content, show the user the diff and
ask before overwriting — they may have local customizations.

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

Ask the user two questions (AskUserQuestion, one call, both questions):

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

Write the answers to `docs/agents/developer-defaults.md` from the template
[developer-defaults.md](./developer-defaults.md) (drop the HTML comment on
the first line, set the two values in the fenced block).

**Idempotence**: if the file already exists, show the current values, ask
the two questions with the current values as the recommended options, and
rewrite the file.

**If the user chose `merge: auto`**, the merge (and the other code-host
writes) will hit permission prompts — and with nobody at the keyboard a
single denial escalates the sub-issue instead of merging it. Offer to add
the host's block to the repo's `.claude/settings.json` (merge with existing
content).

**GitHub** (replace OWNER/REPO from `git remote -v`):

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
      "Merging pull requests in the OWNER/REPO repository (gh pr merge, or the equivalent gh api merge endpoint) is allowed: the user opted into merge: auto in docs/agents/developer-defaults.md, so the /developer pipeline auto-merges PRs after the diff-reviewer reports CLEAN.",
      "Running the developer-skills cleanup-worktrees.sh script (including --sweep) is allowed: it only removes the pipeline's own linked worktrees and agent/* branches, refuses to touch the primary checkout, and is the sanctioned cleanup path of the /developer pipeline."
    ]
  }
}
```

**GitLab**: the analogous block —
`"Bash(glab mr update:*)"`, `"Bash(glab mr note:*)"`,
`"Bash(glab mr merge:*)"`,
`"Bash(glab api projects/*/merge_requests/*)"`, and the same
`autoMode.allow` sentence with "merge requests", `glab mr merge`, and the
project path substituted.

**Local / Other**: no merge rules apply (local never auto-merges; for other
hosts derive the allowlist from the commands recorded in
`docs/agents/code-host.md`) — but **still offer the cleanup-worktrees
`autoMode.allow` sentence**: the wrap-up's `--sweep` is a pattern-matched
worktree removal, exactly the shape the auto-mode classifier denies, and
local runs hit it like any other.

The `autoMode.allow` sentence matters as much as the allowlist: auto mode
double-checks outward-facing actions like merges in natural language even
when the command is allowlisted, so it needs the plain-English record that
the user authorized merging. With `merge: manual`, offer the same block
minus the merge rules (the ready/comment/review rules still save prompts
during review and fix cycles).

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
