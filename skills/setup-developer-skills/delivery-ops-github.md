<!-- Section appended to docs/agents/issue-tracker.md by /setup-developer-skills (GitHub tracker). Drop this comment line. -->

## Delivery operations (/developer pipeline)

The unattended delivery pipeline (`/developer` and its workers) drives this
tracker through the operations below. GitHub is the pipeline's **factory
default**: the delivery skills already carry these `gh` mechanics inline —
this section confirms they apply and adds the sub-issue requirement.

- **Issue ref**: the issue number (`#42` / `42`).
- **Read an issue with comments**: `gh issue view <N> --comments`.
- **Enumerate children of a parent**: the GraphQL sub-issues query (below).
- **Discover a sub-issue's blockers**: check **both** the native dependency
  summary (`gh api repos/{owner}/{repo}/issues/<N> --jq
  '.issue_dependencies_summary.blocked_by // 0'` — the count of *open*
  blockers; 0 or absent = clear) and the `## Blocked by` body section;
  either being non-clear means blocked. Extract that section whole, never a
  fixed window after the heading:

  ```bash
  gh issue view <N> --json body --jq '.body' \
    | awk '/^##[#]* *[Bb]locked by/{f=1;next} /^#/{f=0} f'
  ```
- **Check a blocker's state**: `gh issue view <N> --json state --jq .state`
  (`CLOSED` = no longer blocking).
- **Comment on an issue**: `gh issue comment <N> --body "..."`.
- **Apply a triage label**: `gh issue edit <N> --add-label "<label>"`
  (strings per `docs/agents/triage-labels.md`).
- **Close an issue**: normally never done by hand — `Closes #<N>` in the PR
  body auto-closes the issue on merge (issues and PRs live in the same
  GitHub repo). Close manually (`gh issue close <N> --comment "..."`) only
  when the code host doc says there is no auto-close.

### Parent/child issues MUST be native sub-issues

When a skill breaks a parent issue (a spec/PRD, a plan) into child issues — e.g. `/to-tickets` — each child **must be linked to the parent as a GitHub native sub-issue**, not just referenced in the body text. The `/developer` orchestrator discovers work exclusively through native sub-issue links; a child that is only mentioned in prose is invisible to it.

After creating each child issue, link it:

```bash
# CHILD_ID is the issue *database id*, not the issue number:
CHILD_ID=$(gh api repos/{owner}/{repo}/issues/<CHILD_NUMBER> --jq .id)
gh api repos/{owner}/{repo}/issues/<PARENT_NUMBER>/sub_issues \
  --method POST -F sub_issue_id=$CHILD_ID
```

Keep the `## Parent` and `## Blocked by` sections in the child's body as well — the native link gives machine discovery and the parent's progress panel; the body sections carry the dependency ordering between siblings. Wiring GitHub's native issue dependencies (blocked-by links) in addition is welcome — the pipeline reads them too — but the body sections remain required as the portable fallback.

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

To list a parent's sub-issues:

```bash
gh api graphql -f query='
{
  repository(owner:"{owner}", name:"{repo}") {
    issue(number: <PARENT_NUMBER>) {
      subIssues(first: 50) {
        pageInfo { hasNextPage }
        nodes { number title state labels(first: 10) { nodes { name } } }
      }
    }
  }
}' --jq '.data.repository.issue.subIssues'
```

`labels` feeds the pipeline's escalation gate (`ready-for-human` sub-issues are
skipped). `hasNextPage: true` means the parent has outgrown the pipeline —
stop and ask the user to split it rather than work from a truncated list.
