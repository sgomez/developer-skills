<!-- Template written to docs/agents/developer-defaults.md by /setup-developer-skills. Drop this comment line; fill the two values from the user's answers. -->

# /developer defaults

Repo-level defaults for the `/developer` pipeline, chosen at setup. Per-run
flags override them: `--parallel` / `--sequential` and `--auto-merge` /
`--no-auto-merge`.

```
execution: parallel
merge: manual
```

- `execution` — `parallel` builds independent sub-issues concurrently in
  waves; `sequential` delivers one sub-issue fully before the next starts.
- `merge` — `manual` stops at a CLEAN review: the PR is marked ready and the
  merge is left to a human. `auto` means the user has **pre-authorized**
  `gh pr merge` on any PR whose review verdict is CLEAN — the orchestrator
  merges to `main` unattended, and this line is the standing record of that
  authorization.

To change the defaults, edit the values above (or re-run
`/setup-developer-skills`).
