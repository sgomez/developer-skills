<!-- Section appended to docs/agents/issue-tracker.md by /setup-developer-skills (local-markdown tracker). Drop this comment line. -->

## Delivery operations (/developer pipeline)

The unattended delivery pipeline (`/developer` and its workers) drives this
tracker through the operations below. The `gh` commands shown inline in the
delivery skills are the GitHub factory defaults — **these file conventions
override them.** They build on this tracker's layout: one feature per
`.scratch/<feature-slug>/` directory, the spec at `PRD.md`, child issues at
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

### Tickets are per-issue files, never a root `tickets.md`

When a skill breaks a spec into tickets — e.g. `/to-tickets`, whose
local-files default is a single `tickets.md` in the repo root — this
tracker's layout **overrides that default**: publish one file per ticket at
`.scratch/<feature>/issues/<NN>-<slug>.md` next to the parent `PRD.md`,
each with its own `Status:` line and `Blocked by: NN, NN` line. A single
root `tickets.md` is invisible to the pipeline.

### Every issue file MUST carry a `## Spec extract` section

An issue file is read by a builder with a **clean context**: that file is all
it gets for free. If the decisions it must honour live only in the parent
`PRD.md`, every builder re-reads the whole PRD — a spec with ten issues pays
for its own body ten times, competing with the code exploration the builder
cannot cut.

So `/to-tickets` (or whatever splits the PRD) **must** give each issue file a
`## Spec extract` section holding the PRD's **Implementation Decisions** and
**Testing Decisions that apply to this issue**, copied **verbatim** — not
summarised, not rewritten. Two or three of them is the normal size; an issue
that seems to need all of them is a sign the split is wrong.

```markdown
## Spec extract

Implementation Decisions (from PRD.md):
- <decision, verbatim>
- <decision, verbatim>

Testing Decisions (from PRD.md):
- <decision, verbatim>
```

The bar is the same one that makes any agent brief work: durable and
behavioural, with verifiable criteria, and no file paths that go stale. An
issue file with this section is **self-sufficient** — the pipeline reads
`PRD.md` only as a fallback, when the section is missing.

Issue files live on `main` in the primary checkout. Workers in linked
worktrees read them via their own checkout; **writes** (comments, `Status:`
changes) that must survive the run are made by the orchestrator in the
primary checkout — scoped to `.scratch/` paths only — and committed as
`chore(tracker): …`.
