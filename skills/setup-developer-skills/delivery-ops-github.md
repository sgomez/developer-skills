<!-- Section appended to docs/agents/issue-tracker.md by /setup-developer-skills (GitHub tracker). Drop this comment line. -->

## Delivery operations (/developer pipeline)

The unattended delivery pipeline (`/developer` and its workers) drives this
tracker through the operations below. GitHub is the pipeline's **factory
default**: the delivery skills already carry these `gh` mechanics inline —
this section confirms they apply and adds the sub-issue requirement.

- **Issue ref**: the issue number (`#42` / `42`).
- **Read an issue with comments**: `gh issue view <N> --comments`.
- **Enumerate children of a parent**: the GraphQL sub-issues query (below).
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

When a skill breaks a parent issue (a PRD, a plan) into child issues — e.g. `/to-issues` — each child **must be linked to the parent as a GitHub native sub-issue**, not just referenced in the body text. The `/developer` orchestrator discovers work exclusively through native sub-issue links; a child that is only mentioned in prose is invisible to it.

After creating each child issue, link it:

```bash
# CHILD_ID is the issue *database id*, not the issue number:
CHILD_ID=$(gh api repos/{owner}/{repo}/issues/<CHILD_NUMBER> --jq .id)
gh api repos/{owner}/{repo}/issues/<PARENT_NUMBER>/sub_issues \
  --method POST -F sub_issue_id=$CHILD_ID
```

Keep the `## Parent` and `## Blocked by` sections in the child's body as well — the native link gives machine discovery and the parent's progress panel; the body sections carry the dependency ordering between siblings.

To list a parent's sub-issues:

```bash
gh api graphql -f query='
{
  repository(owner:"{owner}", name:"{repo}") {
    issue(number: <PARENT_NUMBER>) {
      subIssues(first: 50) { nodes { number title state } }
    }
  }
}' --jq '.data.repository.issue.subIssues.nodes'
```
