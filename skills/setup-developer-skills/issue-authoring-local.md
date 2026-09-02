<!-- Template written to docs/agents/issue-authoring.md by /setup-developer-skills (local-markdown tracker). Drop this comment line. -->

# Issue authoring: local markdown files

How child issues must be **created** so the `/developer` pipeline can find and
work them. Annex to [`issue-tracker.md`](./issue-tracker.md), read by whatever
splits a spec into children (`/to-tickets` and the like). **Nothing in the
delivery pipeline reads this file** — by the time an issue is triaged,
implemented or reviewed, the rules below have already been applied or not.

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
