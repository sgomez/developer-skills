<!-- Template written to docs/agents/issue-authoring.md by /setup-developer-skills (GitLab tracker). Drop this comment line. -->

# Issue authoring: GitLab

How child issues must be **created** so the `/developer` pipeline can find and
work them. Annex to [`issue-tracker.md`](./issue-tracker.md), read by whatever
splits a spec into children (`/to-tickets` and the like). **Nothing in the
delivery pipeline reads this file** — by the time an issue is triaged,
implemented or reviewed, the rules below have already been applied or not.

### Parent/child issues MUST carry the parent marker

When a skill breaks a parent issue (a spec/PRD, a plan) into child issues —
e.g. `/to-tickets` — each child **must** have a `## Parent` section containing
`Part of #<PARENT>` at the top of its description, and a `## Blocked by`
section naming its sibling blockers. That marker is how the `/developer`
orchestrator discovers work; a child without it is invisible to the
pipeline. Additionally wire GitLab's native blocking links where available
(`/blocked_by #<n>` quick action posted as a note) — the body sections
remain the canonical fallback.

### Every child issue MUST carry a `## Spec extract` section

A child issue is read by a builder with a **clean context**: the sub-issue is
all it gets for free. If the decisions it must honour live only in the parent
spec, every builder re-reads that whole spec — a spec with ten children pays
for its own body ten times, competing with the code exploration the builder
cannot cut.

So `/to-tickets` (or whatever splits a spec) **must** give each child a
`## Spec extract` section holding the parent's **Implementation Decisions** and
**Testing Decisions that apply to this child**, copied **verbatim** — not
summarised, not rewritten. Two or three of them is the normal size; a child
that seems to need all of them is a sign the split is wrong.

```markdown
## Spec extract

Implementation Decisions (from #<PARENT>):
- <decision, verbatim>
- <decision, verbatim>

Testing Decisions (from #<PARENT>):
- <decision, verbatim>
```

The bar is the same one that makes any agent brief work: durable and
behavioural, with verifiable criteria, and no file paths that go stale. A
child with this section is **self-sufficient** — the pipeline reads the parent
spec only as a fallback, when the section is missing.

> Best-effort: this mapping is maintained without a live GitLab pipeline to
> test against. If a command's shape has drifted, `glab <cmd> --help` is
> authoritative — fix the command here in this doc, not in the skills.
