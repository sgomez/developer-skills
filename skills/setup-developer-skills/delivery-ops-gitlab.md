<!-- Section appended to docs/agents/issue-tracker.md by /setup-developer-skills (GitLab tracker). Drop this comment line. -->

## Delivery operations (/developer pipeline)

The unattended delivery pipeline (`/developer` and its workers) drives this
tracker through the operations below. The `gh` commands shown inline in the
delivery skills are the GitHub factory defaults — **these `glab` mechanics
override them.**

- **Issue ref**: the issue number (`#42` — GitLab numbers issues and MRs
  separately, so refs are unambiguous per surface).
- **Read an issue with comments**: `glab issue view <N> --comments`.
- **Enumerate children of a parent**: children carry a `## Parent` section
  with `Part of #<PARENT>` in the description. List them with
  `glab issue list --search "Part of #<PARENT>" -F json` and keep only
  issues whose description actually contains that marker (search also
  matches titles). Where the project has native work-item hierarchy or
  linked issues, `glab api "projects/:id/issues/<PARENT>/links"` is the
  richer source — use it when it returns results.
- **Discover a sub-issue's blockers**: the `## Blocked by` body section is
  canonical. Where the project also wires native blocking links (a GitLab
  Premium feature), cross-check with
  `glab api "projects/:id/issues/<N>/links"` and treat any open
  `is_blocked_by` link as blocking too.
- **Check a blocker's state**:
  `glab issue view <N> -F json | jq -r .state` (`closed` = no longer
  blocking).
- **Comment on an issue**: `glab issue note <N> --message "..."` (GitLab
  calls comments "notes").
- **Apply a triage label**: `glab issue update <N> --label "<label>"` /
  `--unlabel` (strings per `docs/agents/triage-labels.md`).
- **Close an issue**: `glab issue close <N>` — it takes no closing comment,
  so post the explanation first with `glab issue note`. Normally not done
  by hand: `Closes #<N>` in the MR description auto-closes the issue on
  merge when issues and MRs live in the same GitLab project (see the code
  host doc).

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
