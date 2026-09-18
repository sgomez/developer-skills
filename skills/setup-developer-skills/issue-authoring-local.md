<!-- Template written to docs/agents/issue-authoring.md by /setup-developer-skills (local-markdown tracker). Drop this comment line. -->

# Issue authoring: local markdown files

How child issues must be **created** so the `/developer` pipeline can find and
work them. Annex to [`issue-tracker.md`](./issue-tracker.md), read by whatever
splits a spec into children (`/to-tickets` and the like). **Nothing in the
delivery pipeline reads this file** — by the time an issue is built or
reviewed, the rules below have already been applied or not.

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

### Every child issue MUST carry a `## Complexity` section

The pipeline picks each build's model from this section and nothing else — it
does not re-score tickets. Whoever cut the ticket has just read the whole spec
and decided the split; they know how hard each piece is better than a worker
reading it cold, and it costs one line. So `/to-tickets` **must** state it
twice: once per ticket in the breakdown it proposes for approval, next to the
ticket's description, so the human confirms the rating along with the split;
and once in each child's body:

```markdown
## Complexity

standard — <one line: why>
```

- **`standard`** — follows a pattern the codebase already has, touches a
  handful of files, no new contract or cross-cutting decision. Built at
  `sonnet`.
- **`complex`** — introduces a new pattern, changes a shared contract or a
  migration, spans several modules, or its hard part is subtle logic rather
  than volume. Built at `opus`.

There is no third value for "too big": a ticket that would not fit one
builder's context is a ticket to split now, while the split is being made. A
child without the section is built at `sonnet`.
