export const meta = {
  name: 'developer',
  description: 'Deliver a spec unattended: sub-issues built in dependency order, in parallel, onto an integration branch; one whole-spec review and fix; then the merge into main',
  whenToUse: 'Launched by the /developer skill once it has resolved the run config. Not for direct use: the skill publishes the context docs and builds args first.',
  phases: [
    { title: 'Plan', detail: 'sub-issues, blockers, tiers, PRs already open' },
    { title: 'Spec', detail: 'the spec PR: whole-spec review, single fixer, checks gate, merge into main' },
    { title: 'Wrap-up', detail: 'harvest, final sweep, close the spec' },
  ],
}

// The /developer orchestrator as code. The old orchestrator was a model that
// woke up on every worker result and re-read its whole context to decide the
// next step; here the decisions are this script's control flow, and a model
// only runs where judgement or a shell is needed. The script has no shell:
// every gh/git call belongs to an agent. Mechanical steps (plan, gate, merge,
// bookkeeping) run on a small model with a context of one prompt; build,
// review and fix get the real workers.
//
// A spec with sub-issues is delivered on an integration branch,
// developer/spec-<N>: each sub-issue is built from its tip and merged into it
// after the checks gate, with no review of its own. Reviews one PR at a time
// never see how the sub-issues fit together — two of them each adding their
// own version of a shared helper, a confirmation inside a screen from another
// sub-issue. So the review happens once, on the spec PR (the branch into
// main), and a single fixer acts on it with the whole spec in view. A single
// issue, or one sub-issue on its own, is one change: its PR goes to main and
// its own review is the whole-change review. A local code host or tracker
// keeps that per-PR flow for specs too.
//
// args (built by SKILL.md):
//   spec, sub?          spec issue; sub = deliver only that sub-issue
//   execution           'parallel' | 'sequential'
//   merge               'auto' | 'manual'
//   github              code host is GitHub (gate script, gh defaults)
//   ci                  the code host declares CI on changes
//   localHost           code host is local (LOCAL-HOST.md)
//   localTracker        tracker is local
//   scripts             absolute path of this skill's scripts/ directory
//   root                absolute path of the primary checkout
//   label               the escalation label (ready-for-human)
//   date                YYYY-MM-DD, for the ledger rows
//   cap                 concurrent build/review/fix workers (default 3)
//   mergeFix?           PR: run only the merge-fix job on it (the human's
//                       own merge hit a conflict under merge: manual)

const A = args || {}
if (!A.spec || !A.scripts || !A.root || !A.date) throw new Error('args: spec, scripts, root and date are required')
const SPEC = A.spec
const LABEL = A.label || 'ready-for-human'
const CAP = A.execution === 'sequential' ? 1 : A.cap || 3
const AUTO = A.merge === 'auto' && !A.localHost
const GATE = AUTO && A.ci !== false
const MAX_FIX_CYCLES = 3
const MAX_MERGE_FIXES = 4 // backstop on a main that never stops moving
const SMALL = { model: 'haiku', effort: 'low' }
const STRUCTURED = 'Report through the structured output tool, not a RESULT line.'
const BARE = 'Every command goes in its own Bash call, exactly as written: no pipes, no `;`/`&&`, no extra flags — permission rules and the merge hook match the bare command.'
const TRACKER = A.localTracker
  ? 'The tracker is local: make tracker writes per docs/agents/issue-tracker.md in this checkout, scoped to `.scratch/`, committed as `chore(tracker): …` (LOCAL-HOST.md).'
  : A.github ? '' : 'Use the operations in docs/agents/issue-tracker.md and docs/agents/code-host.md wherever they differ from the gh commands below.'
const KEEP = A.localHost ? ' --keep-branches' : ''
const BRANCH = `developer/spec-${SPEC}` // the integration branch

// ── Schemas ─────────────────────────────────────────────────────────────
const REF = { type: ['integer', 'string'], description: 'PR number (the branch name on a local code host)' }
const PR_STATE = {
  type: 'object',
  properties: { number: REF, isDraft: { type: 'boolean' }, unresolved: { type: 'integer' }, base: { type: 'string' } },
  required: ['number', 'unresolved'],
}
const PLAN = {
  type: 'object',
  properties: {
    error: { type: 'string' },
    mode: { enum: ['spec', 'single', 'sub'] },
    integration: {
      type: 'object',
      description: 'spec mode only: the integration branch and its open PR into main',
      properties: { exists: { type: 'boolean' }, pr: PR_STATE },
      required: ['exists'],
    },
    tickets: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          number: { type: 'integer' },
          title: { type: 'string' },
          labels: { type: 'array', items: { type: 'string' } },
          complex: { type: 'boolean' },
          blockers: { type: 'array', items: { type: 'integer' } },
          integrated: { type: 'boolean', description: 'a PR closing it is already merged into the integration branch' },
          prs: { type: 'array', items: PR_STATE },
        },
        required: ['number', 'title', 'labels', 'complex', 'blockers', 'prs'],
      },
    },
  },
}
const WORK = {
  type: 'object',
  properties: {
    status: { enum: ['pr', 'blocked'] },
    pr: REF,
    url: { type: 'string' },
    reason: { type: 'string' },
    held: { type: 'boolean', description: 'blocked because git says the branch is already used by another worktree' },
  },
  required: ['status'],
}
const REVIEW = {
  type: 'object',
  properties: {
    verdict: { enum: ['CLEAN', 'NEEDS_FIXES', 'blocked'] },
    reason: { type: 'string' },
    noNewCommits: { type: 'boolean', description: 'blocked because nothing landed since the last review' },
    held: { type: 'boolean', description: 'blocked because git says the branch is already used by another worktree' },
  },
  required: ['verdict'],
}
const GATE_RESULT = {
  type: 'object',
  properties: {
    verdict: { enum: ['GREEN', 'DIRTY', 'RED_CODE', 'ESCALATE'] },
    url: { type: 'string', description: 'the failing job URL, for RED_CODE' },
    rerunUsed: { type: 'boolean' },
    reason: { type: 'string' },
  },
  required: ['verdict'],
}
const MERGE_RESULT = {
  type: 'object',
  properties: {
    outcome: { enum: ['merged', 'dirty', 'escalate'], description: "the merge command's own result: once it merged, merged — bookkeeping failures go in notes" },
    reason: { type: 'string' },
    notes: { type: 'string', description: 'KEPT / WARN lines from the cleanup, verbatim' },
  },
  required: ['outcome'],
}
const NOTES = {
  type: 'object',
  properties: { notes: { type: 'string', description: 'KEPT / WARN / LEFTOVER lines, verbatim; empty when none' } },
  required: ['notes'],
}

// ── Concurrency primitives ──────────────────────────────────────────────
function semaphore(n) {
  let free = n
  const waiting = []
  const release = () => {
    const next = waiting.shift()
    if (next) next()
    else free++
  }
  return {
    async acquire() {
      if (free > 0) free--
      else await new Promise(r => waiting.push(r))
      return release
    },
    async run(fn) {
      const done = await this.acquire()
      try { return await fn() } finally { done() }
    },
  }
}
// Build/review/fix workers share the cap. Gate and merge agents mostly wait
// on CI and do not count — a PR waiting on CI is not a worker.
const workers = semaphore(CAP)
// Merges are strictly serial.
const mergeLock = semaphore(1)
// The conflict queue: at most one merge-fix in flight, and the PR holding the
// queue keeps it until it merges or escalates (MERGE-FIX semantics). FIFO.
const conflictQueue = semaphore(1)
let merges = 0 // this run's merges, to tell a stale base from a wrong resolution

// Agent-written text goes inside double-quoted shell arguments.
const shellSafe = text => String(text).replace(/["`$\\]/g, "'").replace(/\s+/g, ' ').slice(0, 300)
const work = (prompt, opts) => workers.run(() => agent(prompt, opts))
const shortTitle = title => {
  let s = ''
  for (const w of title.split(/\s+/).slice(0, 6)) {
    if ((s + ' ' + w).trim().length > 50) break
    s = (s + ' ' + w).trim()
  }
  return s || title.slice(0, 50)
}

// ── Merge-fix only (the human's conflict under merge: manual) ───────────
// base: the branch the PR merges into. mergeIn: merge the base into the
// branch instead of rebasing — the integration branch is made of merge
// commits, and the spec PR's history is the sub-issues' own.
const MERGE_FIX = (pr, base = 'main', mergeIn = false) => `MERGE-FIX job. PR #${pr} cannot be merged into ${base} (conflict with a previously merged change). In your worktree get the PR branch per the fix-that-pushes checkout in \`docs/agents/code-host.md\` (GitHub default: \`git fetch origin pull/${pr}/head:fix/pr-${pr}\`, then \`git checkout fix/pr-${pr}\` as a separate call — never joined with \`&&\`, which the worktree sandbox refuses; do not use \`gh pr checkout\` or check out the branch by name, another worktree may hold it). If git also refuses \`fix/pr-${pr}\`, use \`fix/pr-${pr}-merge\` in both commands; never any other name, the cleanup matches on \`fix/pr-${pr}*\`.

Then \`git fetch origin ${base}\` and ${mergeIn
  ? `merge \`origin/${base}\` into the branch (\`git merge origin/${base}\`), resolving the conflicts as they come — using the resolving-merge-conflicts skill if it appears in your available skills. A merge, not a rebase: this branch is an integration branch made of merge commits, and its history stays as it is.`
  : `rebase the branch onto \`origin/${base}\` (\`git rebase origin/${base}\`), resolving the conflicts as they come — using the resolving-merge-conflicts skill if it appears in your available skills. Rebase, not a merge of ${base} into the branch: the PR's diff has to stay the PR's own work. If the rebase is the wrong shape for this branch (merge commits of its own, or the same hunk conflicting on every commit of a long chain), \`git rebase --abort\`, merge \`origin/${base}\` in instead, and say which you did in reason.`}

Run the project checks, then push with \`git push --force-with-lease origin HEAD:<pr-branch>\` (without the force flag if you merged). On a local code host rebase onto local \`main\`; committing is publishing, there is nothing to push. ${STRUCTURED}`

if (A.mergeFix) {
  const m = await agent(MERGE_FIX(A.mergeFix), {
    label: `merge-fix #${A.mergeFix}`, agentType: 'developer-skills:code-author', model: 'sonnet', isolation: 'worktree', schema: WORK,
  })
  const c = await agent(
    `Run, as one Bash call, and return its output verbatim in notes:
bash ${A.scripts}/cleanup-worktrees.sh --branch "fix/pr-${A.mergeFix}*"${KEEP} 2>&1 | grep -vE '^(REMOVED|DELETED) '`,
    { label: `cleanup #${A.mergeFix}`, schema: NOTES, ...SMALL },
  )
  return { mergeFix: A.mergeFix, result: m, notes: c?.notes ?? '' }
}

// ── Plan ────────────────────────────────────────────────────────────────
phase('Plan')
const plan = await agent(
  A.github
    ? `Run this one command and return its JSON output as your structured result, field for field (an {"error": …} object goes in error):

bash ${A.scripts}/spec-plan.sh ${SPEC}${A.sub ? ' ' + A.sub : ''}`
    : `Plan /developer's run on issue ${SPEC}${A.sub ? `, sub-issue ${A.sub} only` : ''}, using the Delivery operations in docs/agents/issue-tracker.md and the change operations in docs/agents/code-host.md. Read no more than those operations need.
- mode: "sub" when a sub-issue was given; else "spec" if issue ${SPEC} has sub-issues, "single" if it has none (then the issue itself is the only ticket). More than 50 sub-issues → error "split the spec".
- tickets: each OPEN sub-issue (or the one issue): number, title, labels, complex (its \`## Complexity\` section starts with "complex"), blockers (open issues blocking it, from dependency links and its \`## Blocked by\` section), prs (open changes that close it, each with its count of unresolved review threads and its target branch as base; leave out the change whose source branch is \`${BRANCH}\`), integrated (a change closing it is already merged into \`${BRANCH}\`).
- integration (spec mode only): exists (branch \`${BRANCH}\` exists on the code host), pr (the open change from \`${BRANCH}\` into main, if any, with the same fields as prs).`,
  { label: 'plan', phase: 'Plan', schema: PLAN, ...SMALL },
)
if (!plan) throw new Error('the plan agent died')
if (plan.error) return { spec: SPEC, error: plan.error }

const tickets = plan.tickets || []
// The integration branch: specs only, and only on a remote code host — a
// local host or tracker keeps one change per sub-issue into main.
const INTEG = plan.mode === 'spec' && !A.localHost && !A.localTracker && tickets.length > 0
const LANDED = INTEG ? 'integrated' : 'merged' // what a blocker must reach before its dependents start
const byNum = {}
for (const t of tickets) byNum[t.number] = t

// Dependency depth, for the execution report's waves; cycles are blocked.
const depth = {}
const cyclic = new Set()
function depthOf(n, path) {
  if (depth[n] !== undefined) return depth[n]
  if (path.includes(n)) { path.slice(path.indexOf(n)).forEach(x => cyclic.add(x)); return 0 }
  const deps = byNum[n].blockers.filter(b => byNum[b])
  const d = 1 + Math.max(0, ...deps.map(b => depthOf(b, [...path, n])))
  depth[n] = d
  return d
}
tickets.forEach(t => depthOf(t.number, []))
log(`Spec #${SPEC}: ${tickets.length} open sub-issue(s), execution=${A.execution}, merge=${AUTO ? 'auto' : 'manual'}${INTEG ? `, integration branch ${BRANCH}` : ''}`)

if (INTEG && !plan.integration?.exists) {
  const b = await agent(
    `Create the integration branch \`${BRANCH}\` on the remote from the current main. ${BARE}

git fetch origin main

git push origin refs/remotes/origin/main:refs/heads/${BRANCH}

Report status pr when the push succeeded (no pr number), blocked quoting the error otherwise.`,
    { label: 'branch', phase: 'Plan', schema: WORK, ...SMALL },
  )
  if (!b || b.status !== 'pr') return { spec: SPEC, error: `could not create ${BRANCH}: ${b?.reason ?? 'agent died'}` }
}

// ── Per sub-issue ───────────────────────────────────────────────────────
const results = {} // number -> outcome record
const rows = []

function row(s) {
  return `${A.date} spec=#${SPEC} sub=#${s.n} model=${s.tier} effort=medium pr=${s.pr ? '#' + s.pr : 'none'} verdict=${s.verdict} cycles=${s.cycles} mergefix=${s.mergefix} wave=${A.execution === 'parallel' ? s.wave : '—'} outcome=${s.outcome}`
}
const logRow = r => `mkdir -p ${A.root}/.scratch && echo '${r}' >> ${A.root}/.scratch/developer-run-${SPEC}.log`
const cleanupCmd = s =>
  `bash ${A.scripts}/cleanup-worktrees.sh${s.branch ? ` --branch "${s.branch}"` : ''} --branch "fix/pr-${s.pr ?? 0}*" --branch "agent/issue-${s.n}-*"${s.head ? ` --sha "${s.head}"` : ''}${KEEP} 2>&1 | grep -vE '^(REMOVED|DELETED) '`

async function finish(s, outcome, reason) {
  s.outcome = outcome
  s.reason = reason || ''
  const r = row(s)
  rows.push(r)
  results[s.n] = s
  return s
}

async function escalate(s, reason) {
  log(`#${s.n} escalated: ${reason}`)
  const c = await agent(
    `Escalate sub-issue #${s.n} of spec #${SPEC}. ${BARE} ${TRACKER}

gh issue edit ${s.n} --add-label "${LABEL}"

gh issue comment ${s.n} --body "Escalated by /developer: ${shellSafe(reason)}. PR: ${s.pr ? '#' + s.pr : 'none'}."
${s.n === SPEC ? '' : `
gh issue comment ${SPEC} --body "Sub-issue #${s.n} escalated: ${shellSafe(reason)}."
`}
Then, as one Bash call (local bookkeeping, not a code-host write):
${cleanupCmd(s)}
${logRow(row({ ...s, outcome: 'escalated' }))}

Put the cleanup's KEPT/WARN lines in notes. Leave the PR open.`,
    { label: `escalate #${s.n}`, phase: s.phase, schema: NOTES, ...SMALL },
  )
  s.notes = c?.notes ?? ''
  return finish(s, 'escalated', reason)
}

// Local code host: a worker's worktree holds the branch after it ends, so
// clean up between workers or the next one is refused (LOCAL-HOST.md).
async function localCleanup(s) {
  if (!A.localHost) return
  await agent(`Run as one Bash call and return the output verbatim in notes:\n${cleanupCmd(s)}`, {
    label: `cleanup #${s.n}`, phase: s.phase, schema: NOTES, ...SMALL,
  })
}

const REVIEW_PROMPT = pr => `Review PR #${pr} by running the review-pr skill on it — its step 1 plus the repo's \`docs/agents/code-host.md\` give the exact checkout procedure for your worktree; follow them, not memory. Post the review (inline comments + summary) as a single COMMENT submission — never an approval event — and do not mark the PR ready or merge; those are the orchestrator's. ${STRUCTURED}`

const SPEC_PR_NOTE = `\n\nThis PR delivers spec #${SPEC} whole: its sub-issues were built one by one and merged into \`${BRANCH}\` without a review of their own, so this is the only review the spec gets. Review it against the spec issue and every sub-issue it closes.`

async function review(s, rereview) {
  for (let attempt = 0; ; attempt++) {
    const r = await work(
      (rereview
        ? `${REVIEW_PROMPT(s.pr)}\n\nThis is a re-review after fix cycle ${s.cycles}. The skill's step 2 will scope your diff to what landed since the last review — use that scope, and check every previous finding was really fixed in code.`
        : REVIEW_PROMPT(s.pr)) + (s.isSpec ? SPEC_PR_NOTE : ''),
      {
        label: rereview ? `re-review #${s.pr} (${s.cycles})` : `review #${s.pr}`,
        phase: s.phase,
        agentType: 'developer-skills:diff-reviewer',
        isolation: 'worktree',
        schema: REVIEW,
        // The spec PR's review is the spec's only one: it stays on Opus.
        ...(s.isSpec ? { model: 'opus' } : rereview ? { model: 'sonnet' } : {}),
      },
    )
    await localCleanup(s)
    if (r && r.verdict === 'blocked' && r.held && attempt === 0) {
      await agent(`Run as one Bash call and return the output verbatim in notes:\n${cleanupCmd(s)}`, {
        label: `cleanup #${s.n}`, phase: s.phase, schema: NOTES, ...SMALL,
      })
      continue
    }
    return r || { verdict: 'blocked', reason: 'reviewer died' }
  }
}

// Fix cycles until the re-review says CLEAN. Returns null when clean, or the
// escalation reason. `ci` is a failing job URL when the cycle comes from the
// checks gate rather than a review.
async function fixUntilClean(s, ci) {
  for (;;) {
    if (s.cycles >= MAX_FIX_CYCLES) return `not clean after ${MAX_FIX_CYCLES} fix cycles`
    s.cycles++
    const extra = ci ? `\n\nThe PR's CI is red: ${ci}. Fix the failing checks too; there may be no review threads at all.` : ''
    ci = null
    let f
    for (let attempt = 0; ; attempt++) {
      f = await work(
        `FIX job. PR #${s.pr}. Run the fix-pr skill to address all review threads — its step 1 plus the repo's \`docs/agents/code-host.md\` give the exact checkout procedure for your worktree; follow them, not memory. Pushing the fixes and replying to the review threads are part of your delegated task.${extra} ${STRUCTURED}`,
        {
          label: `fix #${s.pr} (${s.cycles})`, phase: s.phase, agentType: 'developer-skills:code-author',
          model: s.cycles === 1 ? s.tier : 'opus', isolation: 'worktree', schema: WORK,
        },
      )
      await localCleanup(s)
      if (f && f.status === 'blocked' && f.held && attempt === 0) {
        await agent(`Run as one Bash call and return the output verbatim in notes:\n${cleanupCmd(s)}`, {
          label: `cleanup #${s.n}`, phase: s.phase, schema: NOTES, ...SMALL,
        })
        continue
      }
      break
    }
    if (!f || f.status !== 'pr') return `fix cycle ${s.cycles} blocked: ${f?.reason ?? 'worker died'}`
    // A sub-issue on the integration branch has no review: its fix answers a
    // red CI, and the checks gate it goes back to is the verdict.
    if (s.into === BRANCH) return null
    const r = await review(s, true)
    if (r.verdict === 'CLEAN') { s.verdict = 'CLEAN'; return null }
    // No new commits since the last review: the findings stand, which is
    // this cycle's NEEDS_FIXES.
    if (r.verdict === 'blocked' && !r.noNewCommits) return `re-review blocked: ${r.reason ?? ''}`
  }
}

function gate(s, rerunUsed) {
  return agent(
    `You run the checks gate for PR #${s.pr} (${s.isSpec ? 'spec' : 'sub-issue'} #${s.n}). Stay in the current directory — the primary checkout. ${BARE} Never read CI logs: the verdict is the whole diagnosis.

1. \`gh pr ready ${s.pr}\` — "already ready" is fine.
2. \`bash ${A.scripts}/checks-gate.sh ${s.pr} --max-wait 540\`, with the Bash timeout set to 600000. It prints one verdict line and its exit code names it:
   - 0 GREEN → verdict GREEN.
   - 12 PENDING → run the gate again; still PENDING on the 7th run → ESCALATE, reason "CI still running after an hour".
   - 11 BEHIND → \`gh pr update-branch ${s.pr}\`, then the gate again. BEHIND straight after an update → ESCALATE.
   - 10 DIRTY → verdict DIRTY.
   - 20 "RED code run=<id> url=<job>" → ${rerunUsed ? 'the one retry is spent: RED_CODE with url=<job>.' : '`gh run rerun <id> --failed`, set rerunUsed, then the gate again; red again → RED_CODE with url=<job>.'}
   - 20 "RED code url=<link>" → RED_CODE with url=<link> (nothing to retry).
   - ${s.into === BRANCH ? '13 NO_CHECKS → verdict GREEN: the CI does not run on changes into the integration branch, and the spec PR\'s own gate covers this code.\n   - 21 RED infra… → ESCALATE' : '21 RED infra…, 13 NO_CHECKS → ESCALATE'}, reason = the verdict line (the CI cannot run the code).
   - 1 ERROR… → the gate once more; ERROR again → ESCALATE quoting it.
   ${A.github ? '' : 'This host is not GitHub: instead of the script, run the same sequence with the operations in docs/agents/code-host-ci.md (mergeable state, wait for checks to register, wait for them to finish, classify a red), waiting inside an until/for loop — never a command that opens with a bare sleep.'}`,
    { label: `gate #${s.pr}`, phase: s.phase, schema: GATE_RESULT, ...SMALL },
  )
}

// Into the integration branch the sub-issue stays open: the spec PR closes
// it on its way into main. The spec PR closes the spec and every sub-issue.
function merge(s) {
  const into = s.into === BRANCH
  const issues = s.isSpec ? [SPEC, ...s.closes] : [s.n]
  const state = issues.map(n => `gh issue view ${n} --json state --jq '"issue=${n} " + .state'`).join('\n')
  return agent(
    `Merge PR #${s.pr} (${s.isSpec ? 'spec' : 'sub-issue'} #${s.n}) ${into ? `into the integration branch \`${BRANCH}\`` : 'into main'} and close the books. Stay in the current directory — the primary checkout. ${BARE} ${TRACKER}

1. ${A.ci === false ? `\`gh pr ready ${s.pr}\` ("already ready" is fine), then ` : ''}\`gh pr merge ${s.pr} --merge\` — alone, no \`--delete-branch\`. A conflict (not mergeable) → outcome dirty, stop. Denied, or any other failure → outcome escalate quoting it, stop.
**Once step 1 has merged, the outcome is merged, whatever happens below.** A bookkeeping command that is denied or fails is reported in notes, never as escalate or dirty.
2. \`gh pr view ${s.pr} --json headRefName,headRefOid --jq '.headRefName + " " + .headRefOid'\` — prints <branch> <sha>.
3. The bookkeeping, as one Bash call with <branch> and <sha> written in literally (no \`$(…)\`, no variables):
${into ? '' : state + '\n'}bash ${A.scripts}/cleanup-worktrees.sh --branch "<branch>" --branch "fix/pr-${s.pr}*" --branch "agent/issue-${s.n}-*" --sha "<sha>" 2>&1 | grep -vE '^(REMOVED|DELETED) '
git ls-remote --exit-code --heads origin "<branch>" >/dev/null; echo "remote-branch-exit=$?"
${logRow(row({ ...s, verdict: 'CLEAN', outcome: into ? 'integrated' : 'merged' }))}
Denied → run its lines as separate calls; still denied → say so in notes and go on.
4. ${into ? '' : `Every issue= line not CLOSED → check it once more; still open → \`gh issue close <n> --comment "Delivered by PR #${s.pr}."\`. `}remote-branch-exit=0 → \`git push origin --delete <branch>\` as its own call.
Outcome merged; the cleanup's KEPT/WARN lines, and any bookkeeping step that failed, go in notes.`,
    { label: `merge #${s.pr}`, phase: s.phase, schema: MERGE_RESULT, ...SMALL },
  )
}

async function readyToMerge(s) {
  const c = await agent(
    `Sub-issue #${s.n}'s PR #${s.pr} is clean and stays for the human to merge. ${BARE}

${A.localHost ? '(Local code host: the reviewer already set `Status: ready`; nothing to mark.)' : `gh pr ready ${s.pr}    ("already ready" is fine)`}

Then, as one Bash call (local bookkeeping):
${cleanupCmd(s)}
${logRow(row({ ...s, verdict: 'CLEAN', outcome: 'ready-to-merge' }))}

Put the cleanup's KEPT/WARN lines in notes.`,
    { label: `ready #${s.pr}`, phase: s.phase, schema: NOTES, ...SMALL },
  )
  s.notes = c?.notes ?? ''
  return finish(s, 'ready-to-merge')
}

// Checks gate → serial merge, with the red-CI retry, the fix cycles a code
// red earns, and the conflict queue for DIRTY.
async function mergePath(s) {
  const base = s.into || 'main'
  // Into the integration branch the gate runs whatever the merge policy.
  const gated = s.into ? A.ci !== false : GATE
  let rerunUsed = false
  let releaseQueue = null
  let fixBase = null // `merges` when the last merge-fix was spawned
  let fixModel = null // the last merge-fix's model: Sonnet first, Opus on a retry
  try {
    for (;;) {
      let v = { verdict: 'GREEN' }
      if (gated) {
        v = await gate(s, rerunUsed)
        if (!v) return escalate(s, 'gate agent died')
        rerunUsed = rerunUsed || !!v.rerunUsed
      }
      if (v.verdict === 'GREEN') {
        const m = await mergeLock.run(() => merge(s))
        if (!m) return escalate(s, 'merge agent died')
        if (m.outcome === 'merged') {
          merges++
          if (!s.into) s.verdict = 'CLEAN'
          s.notes = m.notes ?? ''
          return finish(s, base === BRANCH ? 'integrated' : 'merged')
        }
        if (m.outcome === 'escalate') return escalate(s, m.reason ?? 'merge failed')
        v = { verdict: 'DIRTY' }
      }
      if (v.verdict === 'ESCALATE') return escalate(s, v.reason ?? 'checks gate')
      if (v.verdict === 'RED_CODE') {
        const why = await fixUntilClean(s, v.url ?? 'unknown job')
        if (why) return escalate(s, why)
        continue
      }
      // DIRTY. Join the conflict queue and gate again from its head: the PR
      // that merged before us often carried the conflict away.
      if (!releaseQueue) {
        if (fixBase === null) log(`#${s.n} PR #${s.pr} conflicts — joining the conflict queue`)
        releaseQueue = await conflictQueue.acquire()
        continue
      }
      // Still conflicting with nothing merged since the last merge-fix: the
      // resolution was wrong. Sonnet's earns one Opus retry; Opus's escalates.
      if (fixBase !== null && fixBase === merges && fixModel === 'opus') return escalate(s, `still conflicting after a merge-fix against an unchanged ${base}`)
      if (s.mergefix >= MAX_MERGE_FIXES) return escalate(s, `${base} kept moving through ${MAX_MERGE_FIXES} merge-fixes`)
      s.mergefix++
      fixBase = merges
      fixModel = s.mergefix === 1 ? 'sonnet' : 'opus'
      const f = await work(MERGE_FIX(s.pr, base, !!s.isSpec), {
        label: `merge-fix #${s.pr} (${s.mergefix})`, phase: s.phase, agentType: 'developer-skills:code-author',
        model: fixModel, isolation: 'worktree', schema: WORK,
      })
      if (!f || f.status !== 'pr') {
        if (fixModel === 'opus') return escalate(s, `merge-fix blocked: ${f?.reason ?? 'worker died'}`)
        log(`#${s.n} merge-fix on Sonnet blocked — retrying on Opus`)
      }
    }
  } finally {
    if (releaseQueue) releaseQueue()
  }
}

async function deliver(t) {
  const s = {
    n: t.number, tier: t.complex ? 'opus' : 'sonnet', pr: null, verdict: '—', cycles: 0, mergefix: 0,
    wave: depth[t.number], phase: `#${t.number} ${shortTitle(t.title)}`, title: t.title,
    ...(INTEG ? { into: BRANCH } : {}),
  }
  // Step 0 — resume, never rebuild.
  if (INTEG && t.integrated) {
    results[s.n] = s
    s.outcome = 'integrated'
    return s
  }
  if (t.prs.length > 1) return escalate(s, `${t.prs.length} open PRs claim it; never pick one`)
  let start = 'build'
  if (t.prs.length === 1) {
    s.pr = t.prs[0].number
    s.resumed = true
    if (INTEG && t.prs[0].base && t.prs[0].base !== BRANCH) return escalate(s, `its open PR #${s.pr} targets ${t.prs[0].base}, not the integration branch ${BRANCH}`)
    start = t.prs[0].unresolved > 0 ? 'fix' : 'review'
  }

  if (start === 'build') {
    const b = await work(
      `BUILD job. Spec issue #${SPEC}, sub-issue #${s.n}.
Run the implement-issue skill on the sub-issue. The sub-issue's \`## Spec extract\` section carries the spec decisions that apply to it — read the full spec issue only if that section is missing.${INTEG ? `
Base branch: \`${BRANCH}\`, the spec's integration branch, not main. Fetch it, branch from \`origin/${BRANCH}\` and open the PR with \`${BRANCH}\` as its base: wherever the skill says main, read \`${BRANCH}\`. It already holds the sub-issues this one depends on.` : ''}
Whatever deserves a record goes in the PR body. Report only a PR number you have confirmed exists. ${STRUCTURED}`,
      { label: `build #${s.n}`, phase: s.phase, agentType: 'developer-skills:code-author', model: s.tier, isolation: 'worktree', schema: WORK },
    )
    await localCleanup(s)
    if (!b || b.status !== 'pr' || !b.pr) return escalate(s, `build blocked: ${b?.reason ?? 'worker died'}`)
    s.pr = b.pr
  }

  if (INTEG) {
    // No review per sub-issue: the spec PR's review sees them all together.
    // Threads left by an earlier run's review still get their fix.
    if (start === 'fix') {
      const why = await fixUntilClean(s, null)
      if (why) return escalate(s, why)
    }
    return mergePath(s)
  }

  if (start === 'fix') {
    const why = await fixUntilClean(s, null)
    if (why) return escalate(s, why)
  } else {
    const r = await review(s, false)
    if (r.verdict === 'blocked' && r.noNewCommits && s.resumed) {
      s.verdict = 'CLEAN' // everything it raised before is resolved
    } else if (r.verdict === 'blocked') {
      return escalate(s, `review blocked: ${r.reason ?? ''}`)
    } else if (r.verdict === 'NEEDS_FIXES') {
      s.verdict = 'NEEDS_FIXES'
      const why = await fixUntilClean(s, null)
      if (why) return escalate(s, why)
    } else {
      s.verdict = 'CLEAN'
    }
  }

  if (!AUTO) return readyToMerge(s)
  return mergePath(s)
}

// ── Scheduling ──────────────────────────────────────────────────────────
// A sub-issue starts the moment its blockers inside the spec have merged —
// no waves to wait out. A blocker outside the spec that is still open, a
// dependency cycle, the escalation label, or a blocker that did not merge
// (escalated, ready-to-merge, itself blocked) keeps it out of this run.
const started = {}
function deliverWhenReady(t) {
  if (started[t.number]) return started[t.number]
  started[t.number] = (async () => {
    const n = t.number
    const held = r => { results[n] = { n, title: t.title, outcome: 'blocked', reason: r }; return results[n] }
    if (t.labels.includes(LABEL)) return held(`labelled ${LABEL}`)
    if (cyclic.has(n)) return held('dependency cycle')
    const outside = t.blockers.filter(b => !byNum[b])
    if (outside.length) return held(`blocked by #${outside[0]}`)
    const deps = t.blockers.filter(b => byNum[b])
    const done = await Promise.all(deps.map(b => deliverWhenReady(byNum[b])))
    const stuck = deps.filter((b, i) => done[i].outcome !== LANDED)
    if (stuck.length) return held(`blocked by #${stuck[0]}`)
    return deliver(t)
  })()
  return started[t.number]
}

if (A.execution === 'sequential') {
  // The spec loop: each time, the lowest-numbered sub-issue whose blockers
  // inside the spec are all settled. A cycle is settled by being held.
  const left = [...tickets].sort((a, b) => a.number - b.number)
  while (left.length) {
    const i = left.findIndex(t => cyclic.has(t.number) || t.blockers.every(b => !byNum[b] || results[b]))
    if (i < 0) break
    await deliverWhenReady(left.splice(i, 1)[0])
  }
} else {
  await Promise.all(tickets.map(deliverWhenReady))
}

const all = tickets.map(t => results[t.number])

// ── The spec PR ─────────────────────────────────────────────────────────
// Every sub-issue on the integration branch → open (or resume) the PR into
// main, review it whole, one fixer, then the gate and the merge per policy.
// Anything short of that → the PR stays a draft with no review: reviewing a
// half-delivered spec reports what is missing, which the escalations already
// say.
let spec = null
if (INTEG && all.some(s => s.outcome === 'integrated')) {
  phase('Spec')
  const complete = all.every(s => s.outcome === 'integrated')
  const open = plan.integration?.pr
  spec = {
    n: SPEC, isSpec: true, tier: 'opus', pr: open?.number ?? null, verdict: '—', cycles: 0, mergefix: 0,
    wave: '—', phase: 'Spec', title: `spec #${SPEC}`, closes: tickets.map(t => t.number),
  }
  if (!spec.pr) {
    const o = await agent(
      `Open the spec PR: integration branch \`${BRANCH}\` into main, as a draft. ${BARE}

gh issue view ${SPEC} --json title --jq .title

gh pr create --draft --base main --head ${BRANCH} --title "<that title>" --body "Delivers spec #${SPEC}.

${[SPEC, ...spec.closes].map(n => `Closes #${n}`).join('\n')}"

Use the title as printed, with any double quote replaced by a single one. Report status pr with the new PR's number.`,
      { label: 'open spec PR', phase: 'Spec', schema: WORK, ...SMALL },
    )
    if (o && o.status === 'pr' && o.pr) spec.pr = o.pr
  }
  if (!spec.pr) {
    spec.outcome = 'blocked'
    spec.reason = 'could not open the spec PR'
  } else if (!complete) {
    spec.outcome = 'draft'
    spec.reason = 'sub-issues still undelivered: no review, no merge'
  } else {
    await (async () => {
      if (open && open.unresolved > 0) {
        const why = await fixUntilClean(spec, null)
        if (why) return escalate(spec, why)
      } else {
        const r = await review(spec, false)
        if (r.verdict === 'blocked' && !(r.noNewCommits && open)) return escalate(spec, `review blocked: ${r.reason ?? ''}`)
        if (r.verdict === 'NEEDS_FIXES') {
          spec.verdict = 'NEEDS_FIXES'
          const why = await fixUntilClean(spec, null)
          if (why) return escalate(spec, why)
        }
        spec.verdict = 'CLEAN'
      }
      return AUTO ? mergePath(spec) : readyToMerge(spec)
    })()
  }
}

// ── Wrap-up ─────────────────────────────────────────────────────────────
phase('Wrap-up')
const prs = [...all, ...(spec ? [spec] : [])].filter(s => s.pr).map(s => s.pr)

let harvest = null
if (prs.length && rows.length) {
  harvest = await agent(
    `HARVEST job. This run delivered PRs ${prs.map(p => '#' + p).join(', ')}. Create branch \`agent/harvest-${SPEC}\` from origin/main, then do two things on it:

**(a) Record the run in the ledger.** The rows are the \`outcome=\` lines of \`${A.root}/.scratch/developer-run-${SPEC}.log\` (\`grep 'outcome=' <that file>\`) — they include rows of an earlier run on this spec that died before its wrap-up. If the file is missing, use this run's rows:

\`\`\`
${rows.join('\n')}
\`\`\`

Append them verbatim to the \`## Run log\` section of \`docs/agents/delivery-ledger.md\`, creating the file if it does not exist (with a one-line title and a \`## Run log\` section).

\`docs/agents/delivery-ledger.md\` is the **only** file you may write, and its \`## Run log\` section is the only part of it you may touch. Not \`AGENTS.md\`, not any other doc under \`docs/agents/\` — those belong to /setup-developer-skills and to the human. Step (b) is how anything else gets proposed.

**(b) Propose discoveries — do not apply them.** For each PR read its body and comments per the repo's \`docs/agents/code-host.md\` (GitHub default: \`gh pr view <PR> --json body,comments\`) and collect the \`## Discoveries\` entries. Compare them against the repo's agent docs (\`AGENTS.md\` and everything under \`docs/agents/\`), read-only. Keep only entries that repeat across PRs, correct a doc the code has outgrown, or would clearly have saved another worker real work. Write the survivors to \`${A.root}/.scratch/developer-discoveries-${SPEC}.md\` — absolute, outside your worktree on purpose — one entry each as:

\`\`\`
### <one-line title>
Doc: <path the change belongs in, or "new doc: <suggested path>">
Evidence: PR #<n> (and #<n>…)
Proposed: <the edit, concretely enough to apply without re-reading the PRs>
\`\`\`

Nothing qualifies → do not create the file.

Commit **only** \`docs/agents/delivery-ledger.md\`, as \`docs(agents): record spec #${SPEC} run\`, and ${A.localHost ? 'leave the commit on the branch — a local host never moves main unattended; say so in reason.' : 'push with `git push origin HEAD:main` — never check out main. Rejected → fetch and rebase once, push again; still failing → status blocked.'} ${STRUCTURED} Put "discoveries=<n> ledger=<appended|failed>" in reason.`,
    { label: 'harvest', phase: 'Wrap-up', agentType: 'developer-skills:code-author', model: 'sonnet', isolation: 'worktree', schema: WORK },
  )
}
const appended = !!harvest && /ledger=appended/.test(harvest.reason ?? '')

const closeSpec = (plan.mode === 'spec' && (!INTEG || spec?.outcome === 'merged')) || (plan.mode === 'sub' && all.some(s => s.outcome === 'merged'))
const sweep = await agent(
  `Close out /developer's run on spec #${SPEC}. ${BARE}

1. One Bash call:
bash ${A.scripts}/cleanup-worktrees.sh --sweep${KEEP} 2>&1 | grep -vE '^(REMOVED|DELETED) '
${appended ? `mkdir -p .scratch/archive && mv .scratch/developer-run-${SPEC}.log ".scratch/archive/developer-run-${SPEC}-$(date +%Y%m%dT%H%M%S).log"` : ''}
   Denied → do not retry; report it in notes with \`git worktree list\` output.
${closeSpec ? `2. ${A.github ? `\`gh issue view ${SPEC} --json state --jq .state\` and the state of every sub-issue of #${SPEC} (the GraphQL subIssues listing, or \`gh api repos/{owner}/{repo}/issues/${SPEC}/sub_issues --jq '[.[] | .state]'\`).` : `Per docs/agents/issue-tracker.md: the state of #${SPEC} and of every sub-issue.`} If #${SPEC} is open and **every** sub-issue is closed → close it: \`gh issue close ${SPEC} --comment "Closed by /developer: all sub-issues delivered and merged."\` (or the tracker's operation). ${TRACKER} Say in notes whether it was closed, and which sub-issues are still open.` : ''}

notes: the sweep's final line, every LEFTOVER/KEPT/WARN/HELD/ABORT/WOULD-DELETE line verbatim, then the spec line.`,
  { label: 'sweep', phase: 'Wrap-up', schema: NOTES, ...SMALL },
)

return {
  spec: SPEC,
  mode: plan.mode,
  config: { execution: A.execution, merge: AUTO ? 'auto' : 'manual' },
  subIssues: all.map(s => ({
    number: s.n, title: s.title, blockers: byNum[s.n].blockers, outcome: s.outcome, reason: s.reason || undefined, pr: s.pr || undefined,
    model: s.tier, cycles: s.cycles, mergefix: s.mergefix, wave: s.wave, notes: s.notes || undefined,
  })),
  specPr: spec ? {
    pr: spec.pr || undefined, branch: BRANCH, outcome: spec.outcome, reason: spec.reason || undefined,
    cycles: spec.cycles, mergefix: spec.mergefix, notes: spec.notes || undefined,
  } : undefined,
  rows,
  harvest: harvest ? { status: harvest.status, reason: harvest.reason } : null,
  wrapUp: sweep?.notes ?? 'sweep agent died',
}
