---
name: setup-developer-skills
description: Configure this repo for the /developer unattended PRD-delivery pipeline — runs setup-matt-pocock-skills if needed, patches the issue tracker doc so child issues are created as native GitHub sub-issues, installs the dispatcher/code-author/diff-reviewer agents, ensures the triage labels exist, and asks for the run defaults (parallel/sequential execution, auto/manual merge) written to docs/agents/developer-defaults.md. Run once before first use of /developer.
disable-model-invocation: true
---

# Setup Developer Skills

Scaffold the per-repo configuration that the `/developer` pipeline assumes.
This builds **on top of** Matt Pocock's engineering skills setup — it does not
replace it.

This is a prompt-driven skill, not a deterministic script. Explore, present
what you found, confirm with the user, then write.

## Process

### 1. Preconditions

- **GitHub repo**: `git remote -v` must point at GitHub, and `gh auth status`
  must succeed. The `/developer` pipeline works exclusively through the `gh`
  CLI and GitHub native sub-issues — if this repo uses GitLab or a local
  tracker, stop and tell the user `/developer` does not support it.
- **Matt Pocock's setup**: check whether `docs/agents/issue-tracker.md`
  exists.
  - If it does not, check whether the `setup-matt-pocock-skills` skill is
    available. If it is, **invoke it now** (via the Skill tool) and continue
    when it finishes. If it is not installed, stop and tell the user to run
    `npx skills add mattpocock/skills` (see the README of this repo for the
    minimum set) and re-run this skill.
  - If `docs/agents/issue-tracker.md` exists but describes a non-GitHub
    tracker, stop — same reason as above.

### 2. Patch the issue tracker doc for native sub-issues

`/to-issues` (Matt's skill) links children to parents only in body text.
`/developer` discovers work exclusively through **native sub-issue links**,
so the tracker doc must instruct every skill to create them.

Append the contents of [issue-tracker-subissues.md](./issue-tracker-subissues.md)
to `docs/agents/issue-tracker.md` (drop the HTML comment on the first line).

**Idempotence**: if a `## Parent/child issues MUST be native sub-issues`
heading already exists there, replace that section with the template instead
of appending a duplicate.

### 3. Install the agents

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

### 4. Ensure the triage labels exist

`/developer` applies `ready-for-human` on escalation, and `implement-issue`
lists work by `ready-for-agent`. Respect any label mapping in
`docs/agents/triage-labels.md`; with the default vocabulary:

```bash
gh label list --json name --jq '.[].name'
gh label create ready-for-agent --description "Fully specified, an agent can pick it up" --color 0E8A16 2>/dev/null || true
gh label create ready-for-human --description "Needs human attention" --color D93F0B 2>/dev/null || true
```

### 5. Choose the run defaults

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

Write the answers to `docs/agents/developer-defaults.md` from the template
[developer-defaults.md](./developer-defaults.md) (drop the HTML comment on
the first line, set the two values in the fenced block).

**Idempotence**: if the file already exists, show the current values, ask
the two questions with the current values as the recommended options, and
rewrite the file.

**If the user chose `merge: auto`**, the merge (and the other GitHub writes)
will hit permission prompts — and with nobody at the keyboard a single
denial escalates the sub-issue instead of merging it. Offer to add this to
the repo's `.claude/settings.json` (merge with existing content, replace
OWNER/REPO from `git remote -v`):

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
      "Merging pull requests in the OWNER/REPO repository (gh pr merge, or the equivalent gh api merge endpoint) is allowed: the user opted into merge: auto in docs/agents/developer-defaults.md, so the /developer pipeline auto-merges PRs after the diff-reviewer reports CLEAN."
    ]
  }
}
```

The `autoMode.allow` sentence matters as much as the allowlist: auto mode
double-checks outward-facing actions like merges in natural language even
when the command is allowlisted, so it needs the plain-English record that
the user authorized merging. With `merge: manual`, offer the same block
minus the two merge rules (`Bash(gh pr merge:*)` and the autoMode sentence) —
the ready/comment/reviews-API rules still save prompts during review and fix
cycles.

### 6. Report

Summarise what was set up — including the chosen defaults — and remind the
user of the flow:

1. Grill/discuss a feature → `/to-prd` publishes the PRD issue.
2. `/to-issues <prd>` breaks it into **native sub-issues** with `Blocked by`
   ordering.
3. `/developer <prd>` delivers them all unattended — triage → build → review
   → fix cycles → merge per the chosen policy — and sends a push
   notification when done.

If they chose `merge: auto`, warn them explicitly: **`/developer` will merge
PRs to `main` unattended when the review verdict is CLEAN.** If they chose
`manual`, remind them the wrap-up summary lists the ready-to-merge PRs in
dependency order, and that per-run flags (`--auto-merge`, `--sequential`, …)
override the defaults.
