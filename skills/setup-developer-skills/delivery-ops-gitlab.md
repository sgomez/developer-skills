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

When a skill breaks a parent issue (a PRD/spec, a plan) into child issues —
e.g. `/to-tickets` — each child **must** have a `## Parent` section containing
`Part of #<PARENT>` at the top of its description, and a `## Blocked by`
section naming its sibling blockers. That marker is how the `/developer`
orchestrator discovers work; a child without it is invisible to the
pipeline. Additionally wire GitLab's native blocking links where available
(`/blocked_by #<n>` quick action posted as a note) — the body sections
remain the canonical fallback.

> Best-effort: this mapping is maintained without a live GitLab pipeline to
> test against. If a command's shape has drifted, `glab <cmd> --help` is
> authoritative — fix the command here in this doc, not in the skills.
