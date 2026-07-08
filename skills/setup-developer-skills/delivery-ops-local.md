<!-- Section appended to docs/agents/issue-tracker.md by /setup-developer-skills (local-markdown tracker). Drop this comment line. -->

## Delivery operations (/developer pipeline)

The unattended delivery pipeline (`/developer` and its workers) drives this
tracker through the operations below. The `gh` commands shown inline in the
delivery skills are the GitHub factory defaults — **these file conventions
override them.** They build on this tracker's layout: one feature per
`.scratch/<feature-slug>/` directory, the PRD at `PRD.md`, child issues at
`issues/<NN>-<slug>.md`.

- **Issue ref**: the issue file's repo-relative path
  (`.scratch/<feature>/issues/<NN>-<slug>.md`); the bare `<NN>` works once
  the feature directory is established in context.
- **Read an issue with comments**: read the file — the body plus its
  `## Comments` section.
- **Enumerate children of a parent**: list `.scratch/<feature>/issues/*.md`
  next to the parent `PRD.md`, in numeric order. State comes from each
  file's `Status:` line — `closed` means done; any other value (the triage
  strings from `docs/agents/triage-labels.md`) means open.
- **Check a blocker's state**: the `Blocked by: NN, NN` line near the top
  of the issue file names sibling issue numbers; a blocker is cleared when
  its file's `Status:` is `closed`.
- **Comment on an issue**: append to the file under its `## Comments`
  heading (create the heading if missing), prefixed with a date and the
  author role, e.g. `**2026-07-08, /developer:** …`.
- **Apply a triage label**: set the `Status:` line to the role string
  (e.g. `Status: ready-for-human`).
- **Close an issue**: set `Status: closed` and append a closing comment
  naming the change that delivered it. There is **no auto-close on merge**
  — after a change merges, whoever merged it closes the issue this way
  (the orchestrator does it under `merge: auto`; the human otherwise).

Issue files live on `main` in the primary checkout. Workers in linked
worktrees read them via their own checkout; **writes** (comments, `Status:`
changes) that must survive the run are made by the orchestrator in the
primary checkout — scoped to `.scratch/` paths only — and committed as
`chore(tracker): …`.
