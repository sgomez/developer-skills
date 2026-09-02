<!-- Section appended to docs/agents/issue-tracker.md by /setup-developer-skills (GitHub tracker). Drop this comment line. -->

## Delivery operations (/developer pipeline)

The unattended delivery pipeline (`/developer` and its workers) drives this
tracker through the operations below. GitHub is the pipeline's **factory
default**: the delivery skills already carry these `gh` mechanics inline —
this section confirms they apply and adds the sub-issue query.

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

### Enumerate a parent's sub-issues

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

### Creating child issues

The rules a splitter (`/to-tickets` and anything like it) must follow when it
**creates** children — the native sub-issue link and the mandatory
`## Spec extract` section — live in
[`docs/agents/issue-authoring.md`](./issue-authoring.md). **Open that file
only when you are creating or editing issues.** Nothing in the delivery
pipeline — triaging, implementing, reviewing, fixing, merging — needs it: by
then the children already exist.
