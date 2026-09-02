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

### Creating child issues

The rules a splitter (`/to-tickets` and anything like it) must follow when it
**creates** children — the `## Parent` marker and the mandatory
`## Spec extract` section — live in
[`docs/agents/issue-authoring.md`](./issue-authoring.md). **Open that file
only when you are creating or editing issues.** Nothing in the delivery
pipeline — triaging, implementing, reviewing, fixing, merging — needs it: by
then the children already exist.
