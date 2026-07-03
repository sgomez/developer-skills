<!-- Section appended to docs/agents/issue-tracker.md by /setup-developer-skills -->

## Parent/child issues MUST be native sub-issues

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
