# Local host / local tracker

Read this file when `docs/agents/issue-tracker.md` or `docs/agents/code-host.md`
says the tracker or the code host is **local** (files in the repo, no
remote). The workflow handles the rest once it gets `localHost` /
`localTracker` in its args: unattended merge is off, every worker is followed
by a cleanup that keeps branches (git lets a branch live in one worktree
only), there is no mark-ready call, tracker writes are scoped `.scratch/`
commits, and the harvest leaves its commit on `agent/harvest-<spec>`.

A run on a remote host (GitHub, GitLab) never needs this file.

## Publishing context docs (SKILL.md, step 1)

- **Local tracker** — add `.scratch` to the paths of both the
  `git status --porcelain` check and the `git add`: the tracker and change
  files live there and workers read them through their own checkout. Exclude
  the run's own artifacts from both with the pathspecs
  `':!.scratch/developer-*' ':!.scratch/archive'` — the workflow copy
  (`developer-workflow.js`), the run log and the discoveries file are never
  committed.
- There is no remote, so there is no push: the commit alone publishes, since
  linked worktrees share the repo.

## Run configuration

A local code host supports `merge: manual` only. If the resolved config says
`auto`, override it and say so in the run-config line.

## Report

The human's merge queue uses the local commands, per change:

```bash
git merge --no-ff <branch>
git branch -d <branch>
# then close the issue per the tracker ops (no auto-close on a local host)
```

List the harvest branch `agent/harvest-<spec>` as one more item in that
queue: a local host never moves `main` unattended.
