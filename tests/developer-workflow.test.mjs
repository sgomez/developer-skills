// Regression tests for skills/developer/workflow.js — the scheduler, not the
// agents. Runs the workflow script with fake agent()/phase()/log() whose
// answers come from per-scenario rules, and records what was spawned, in what
// order, and how many ran at once. No network, no model. Run directly:
//
//   node tests/developer-workflow.test.mjs
//
// Exits 0 with a PASS summary, or 1 listing every failed assertion.
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(join(here, '..', 'skills', 'developer', 'workflow.js'), 'utf8')
  .replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = new AsyncFunction('args', 'agent', 'phase', 'log', source)

let checks = 0, fails = 0, T = ''
const ok = (cond, msg) => { checks++; if (!cond) { fails++; console.error(`FAIL [${T}] ${msg}`) } }

const WORKER = /^(build|review|re-review|fix|merge-fix) /
const sleep = ms => new Promise(r => setTimeout(r, ms))

// run(scenario) — scenario.tickets: plan tickets; scenario.mode: the plan's
// mode ('spec' by default: the integration-branch flow; 'single' runs the
// per-PR flow); scenario.integration: the plan's integration object;
// scenario.on(label, prompt, state, opts) may return an answer to override
// the defaults below. The spec PR is #900.
async function run(name, scenario) {
  T = name
  const st = { spawned: [], active: 0, maxActive: 0, merging: 0, maxMerging: 0, mergeFixing: 0, maxMergeFixing: 0, n: {}, logs: [] }
  const agent = async (prompt, opts = {}) => {
    const label = opts.label || ''
    st.spawned.push(label)
    st.n[label] = (st.n[label] || 0) + 1
    const worker = WORKER.test(label)
    if (worker) { st.active++; st.maxActive = Math.max(st.maxActive, st.active) }
    if (label.startsWith('merge ')) { st.merging++; st.maxMerging = Math.max(st.maxMerging, st.merging) }
    if (label.startsWith('merge-fix ')) { st.mergeFixing++; st.maxMergeFixing = Math.max(st.maxMergeFixing, st.mergeFixing) }
    try {
      await sleep(scenario.delay?.(label) ?? 2)
      const custom = scenario.on?.(label, prompt, st, opts)
      if (custom !== undefined) return custom
      const num = Number((label.match(/#(\d+)/) || [])[1])
      if (label === 'plan') return { mode: scenario.mode || 'spec', integration: scenario.integration || { exists: true }, tickets: scenario.tickets }
      if (label === 'branch') return { status: 'pr' }
      if (label === 'open spec PR') return { status: 'pr', pr: 900 }
      if (label.startsWith('build ')) return { status: 'pr', pr: 100 + num }
      if (label.startsWith('review ') || label.startsWith('re-review ')) return { verdict: 'CLEAN' }
      if (label.startsWith('fix ') || label.startsWith('merge-fix ')) return { status: 'pr', pr: num }
      if (label.startsWith('gate ')) return { verdict: 'GREEN' }
      if (label.startsWith('merge ')) return { outcome: 'merged' }
      if (label === 'harvest') return { status: 'pr', reason: 'discoveries=0 ledger=appended' }
      return { notes: '' }
    } finally {
      if (worker) st.active--
      if (label.startsWith('merge ')) st.merging--
      if (label.startsWith('merge-fix ')) st.mergeFixing--
    }
  }
  const args = {
    spec: 1, execution: 'parallel', merge: 'auto', github: true, ci: true,
    scripts: '/s', root: '/r', date: '2026-10-07', ...scenario.args,
  }
  const result = await body(args, agent, () => {}, m => st.logs.push(m))
  const out = Object.fromEntries((result.subIssues || []).map(s => [s.number, s]))
  return { result, out, st, at: label => st.spawned.indexOf(label), spec: result.specPr }
}

const t = (number, extra = {}) => ({ number, title: `Ticket ${number}`, labels: [], complex: false, blockers: [], prs: [], ...extra })

// ── parallel, independent ──────────────────────────────────────────────
{
  const { out, st, result, spec } = await run('cap-and-serial-merges', {
    tickets: [t(2), t(3), t(4), t(5), t(6)],
    delay: l => (l.startsWith('gate') ? 15 : l.startsWith('merge ') ? 5 : 3),
  })
  ok([2, 3, 4, 5, 6].every(n => out[n].outcome === 'integrated'), 'all five integrated')
  ok(st.maxActive <= 3, `at most 3 workers at once (saw ${st.maxActive})`)
  ok(st.maxActive === 3, `the cap is used (saw ${st.maxActive})`)
  ok(st.maxMerging === 1, `merges strictly serial (saw ${st.maxMerging})`)
  ok(result.rows.filter(r => /outcome=integrated/.test(r)).length === 5, 'one integrated row each')
  ok(spec.outcome === 'merged' && spec.pr === 900 && spec.branch === 'developer/spec-1', 'the spec PR merged into main')
  ok(st.n['harvest'] === 1 && st.n['sweep'] === 1, 'harvest and sweep once')
}

// ── sequential ─────────────────────────────────────────────────────────
{
  const { out, st, at } = await run('sequential', {
    tickets: [t(3), t(2, { blockers: [3] }), t(4)],
    args: { execution: 'sequential' },
  })
  ok(st.maxActive === 1, `one worker at a time (saw ${st.maxActive})`)
  ok(at('merge #103') < at('build #2'), '#3 integrated before #2 builds')
  ok(at('merge #102') < at('build #4'), 'one sub-issue fully delivered before the next')
  ok(out[4].outcome === 'integrated', '#4 integrated')
  ok(at('merge #104') < at('review #900'), 'the spec review comes after every sub-issue')
}

// ── dependencies ───────────────────────────────────────────────────────
{
  const { out, at } = await run('dependency-waits-for-merge', {
    tickets: [t(2), t(3, { blockers: [2] }), t(4)],
  })
  ok(at('merge #102') < at('build #3'), '#3 builds only after #2 integrated')
  ok(at('build #4') < at('merge #102'), '#4 does not wait for #2')
  ok(out[3].wave === 2 && out[2].wave === 1, 'waves from dependency depth')
}
{
  const { out, st, spec } = await run('escalated-blocker-blocks-dependents', {
    tickets: [t(2), t(3, { blockers: [2] }), t(4, { blockers: [3] })],
    on: l => (l === 'build #2' ? { status: 'blocked', reason: 'spec contradiction' } : undefined),
  })
  ok(out[2].outcome === 'escalated', '#2 escalated')
  ok(st.n['escalate #2'] === 1, 'escalation agent ran')
  ok(out[3].outcome === 'blocked' && /#2/.test(out[3].reason), '#3 blocked by #2')
  ok(out[4].outcome === 'blocked' && /#3/.test(out[4].reason), '#4 blocked by #3')
  ok(!st.n['build #3'] && !st.n['build #4'], 'nothing built on top of it')
  ok(spec === undefined && !st.n['open spec PR'], 'nothing integrated → no spec PR')
}
{
  const { out, st, spec } = await run('outside-blocker-label-and-cycle', {
    tickets: [t(2, { blockers: [99] }), t(3, { labels: ['ready-for-human'] }), t(4, { blockers: [5] }), t(5, { blockers: [4] }), t(6)],
  })
  ok(out[2].outcome === 'blocked' && /#99/.test(out[2].reason), 'open blocker outside the spec holds #2')
  ok(out[3].outcome === 'blocked' && /ready-for-human/.test(out[3].reason), 'escalation label holds #3')
  ok(out[4].outcome === 'blocked' && out[5].outcome === 'blocked', 'a dependency cycle is blocked, not deadlocked')
  ok(out[6].outcome === 'integrated' && st.spawned.filter(l => l.startsWith('build')).length === 1, 'only #6 built')
  ok(spec.outcome === 'draft' && st.n['open spec PR'] === 1, 'a partial spec gets a draft spec PR')
  ok(!st.n['review #900'] && !st.n['merge #900'], 'and no review, no merge')
}

// ── the integration branch ─────────────────────────────────────────────
{
  const { st, at } = await run('creates-the-integration-branch', {
    tickets: [t(2)], integration: { exists: false },
    on: (l, p) => {
      if (l === 'branch') ok(/refs\/heads\/developer\/spec-1/.test(p), 'pushes developer/spec-1')
      if (l === 'build #2') ok(/Base branch: `developer\/spec-1`/.test(p), 'the build is told its base')
      if (l === 'gate #102') ok(/NO_CHECKS → verdict GREEN/.test(p), 'no CI into the integration branch is green')
      if (l === 'gate #900') ok(/13 NO_CHECKS → ESCALATE/.test(p), 'no CI on the spec PR escalates')
      if (l === 'merge #102') ok(!/gh issue close/.test(p) && /into the integration branch/.test(p), 'integrating closes no issue')
      if (l === 'merge #900') ok(/issue=1 /.test(p) && /issue=2 /.test(p) && /gh issue close/.test(p), 'the spec merge closes the spec and its sub-issues')
      if (l === 'open spec PR') ok(/--base main --head developer\/spec-1/.test(p) && /Closes #1\nCloses #2/.test(p), 'spec PR closes the spec and every sub-issue')
      return undefined
    },
  })
  ok(at('branch') >= 0 && at('branch') < at('build #2'), 'branch created before any build')
  ok(!st.n['review #102'], 'no review per sub-issue')
}
{
  const { st } = await run('branch-exists', { tickets: [t(2)] })
  ok(!st.n['branch'], 'an existing integration branch is reused')
}
{
  const { result, st } = await run('branch-push-fails', {
    tickets: [t(2)], integration: { exists: false },
    on: l => (l === 'branch' ? { status: 'blocked', reason: 'denied' } : undefined),
  })
  ok(/developer\/spec-1/.test(result.error) && !st.n['build #2'], 'no branch → stop before building')
}
{
  const models = {}
  const { st, spec } = await run('spec-review-and-single-fixer', {
    tickets: [t(2), t(3)],
    on: (l, p, _s, o) => {
      models[l] = o.model
      if (l === 'review #900') { ok(/delivers spec #1 whole/.test(p), 'the spec review knows what it reviews'); return { verdict: 'NEEDS_FIXES' } }
      return undefined
    },
  })
  ok(st.n['fix #900 (1)'] === 1 && st.n['re-review #900 (1)'] === 1, 'one fixer, one re-review')
  ok(models['review #900'] === 'opus' && models['fix #900 (1)'] === 'opus' && models['re-review #900 (1)'] === 'opus', 'the spec review, fix and re-review on Opus')
  ok(spec.outcome === 'merged' && spec.cycles === 1, 'then merged')
  ok(st.n['gate #900'] === 1 && st.n['merge #900'] === 1, 'through the gate')
}
{
  const { st, spec } = await run('spec-pr-resumed', {
    tickets: [t(2, { integrated: true }), t(3)],
    integration: { exists: true, pr: { number: 900, unresolved: 0 } },
  })
  ok(!st.n['build #2'] && !st.n['merge #102'], 'an integrated sub-issue is not rebuilt')
  ok(!st.n['open spec PR'] && st.n['review #900'] === 1, 'the open spec PR is reviewed, not reopened')
  ok(spec.outcome === 'merged', 'and merged')
}
{
  const { st } = await run('spec-pr-resumed-with-threads', {
    tickets: [t(2, { integrated: true })],
    integration: { exists: true, pr: { number: 900, unresolved: 3 } },
  })
  ok(!st.n['review #900'] && st.n['fix #900 (1)'] === 1, 'unresolved threads on the spec PR → fix first')
}
{
  const { out, st } = await run('resume-on-the-integration-branch', {
    tickets: [
      t(2, { prs: [{ number: 50, unresolved: 0, base: 'developer/spec-1' }] }),
      t(3, { prs: [{ number: 60, unresolved: 2, base: 'developer/spec-1' }] }),
      t(4, { prs: [{ number: 70, unresolved: 0 }, { number: 71, unresolved: 0 }] }),
      t(5, { prs: [{ number: 80, unresolved: 0, base: 'main' }] }),
    ],
  })
  ok(!st.n['build #2'] && !st.n['review #50'] && st.n['merge #50'] === 1, 'open PR → straight to the gate and merge')
  ok(st.n['fix #60 (1)'] === 1 && !st.n['re-review #60 (1)'] && out[3].outcome === 'integrated', 'old threads → fix, no re-review')
  ok(out[4].outcome === 'escalated', 'two open PRs → escalate')
  ok(out[5].outcome === 'escalated' && /targets main/.test(out[5].reason), 'a PR into main → escalate, never retarget')
}
{
  const { out, st } = await run('integration-red-code-fix-without-review', {
    tickets: [t(2)],
    on: (l, _p, s) => (l === 'gate #102' && s.n[l] === 1 ? { verdict: 'RED_CODE', url: 'https://job/1', rerunUsed: true } : undefined),
  })
  ok(st.n['fix #102 (1)'] === 1 && !st.n['re-review #102 (1)'] && st.n['gate #102'] === 2, 'red → fix → gate again, no review')
  ok(out[2].outcome === 'integrated', 'then integrated')
}
{
  const { out, spec, st } = await run('spec-escalation', {
    tickets: [t(2)],
    on: (l, p) => {
      if (l === 'review #900') return { verdict: 'NEEDS_FIXES' }
      if (l.startsWith('re-review #900')) return { verdict: 'NEEDS_FIXES' }
      if (l === 'escalate #1') ok(/gh issue edit 1 /.test(p) && (p.match(/gh issue comment/g) || []).length === 1, 'the spec is labelled and commented once')
      return undefined
    },
  })
  ok(out[2].outcome === 'integrated' && spec.outcome === 'escalated' && spec.cycles === 3, 'spec escalated after 3 cycles')
  ok(st.n['escalate #1'] === 1 && !st.n['merge #900'], 'never merged')
}

// ── merge: manual ──────────────────────────────────────────────────────
{
  const { out, st, spec } = await run('manual-merge', {
    tickets: [t(2), t(3, { blockers: [2] })],
    args: { merge: 'manual' },
  })
  ok(out[2].outcome === 'integrated' && out[3].outcome === 'integrated', 'sub-issues still integrate on their own')
  ok(st.n['merge #102'] === 1 && st.n['merge #103'] === 1, 'merged into the integration branch')
  ok(spec.outcome === 'ready-to-merge' && st.n['ready #900'] === 1 && !st.n['merge #900'], 'the spec PR waits for the human')
  ok(!st.n['gate #900'], 'no gate on the spec PR')
  ok(st.n['gate #102'] === 1 && st.n['gate #103'] === 1, 'sub-issues still pass the checks gate')
}
{
  const { out, st } = await run('manual-merge-single', {
    mode: 'single', tickets: [t(2)], args: { merge: 'manual' },
  })
  ok(out[2].outcome === 'ready-to-merge', 'a single issue is ready-to-merge')
  ok(!st.spawned.some(l => l.startsWith('gate') || l.startsWith('merge ')), 'no gate, no merge')
  ok(st.n['ready #102'] === 1 && st.n['review #102'] === 1, 'reviewed and marked ready')
}
{
  const { out, st, spec } = await run('local-host-keeps-the-per-pr-flow', {
    tickets: [t(2)],
    args: { merge: 'auto', localHost: true, github: false },
  })
  ok(out[2].outcome === 'ready-to-merge', 'a local code host never merges')
  ok(st.n['review #102'] === 1 && spec === undefined, 'reviewed per PR, no integration branch')
  ok(st.n['cleanup #2'] >= 2, 'cleanup between workers on a local host')
}

// ── resume (per-PR flow) ───────────────────────────────────────────────
{
  const { out, st } = await run('resume', {
    mode: 'single',
    tickets: [
      t(2, { prs: [{ number: 50, unresolved: 0 }] }),
      t(3, { prs: [{ number: 60, unresolved: 2 }] }),
      t(4, { prs: [{ number: 70, unresolved: 0 }, { number: 71, unresolved: 0 }] }),
      t(5, { prs: [{ number: 80, unresolved: 0 }] }),
    ],
    on: l => (l === 'review #80' ? { verdict: 'blocked', noNewCommits: true } : undefined),
  })
  ok(!st.n['build #2'] && st.n['review #50'] === 1, 'open PR, no threads → review, no build')
  ok(!st.n['build #3'] && !st.n['review #60'] && st.n['fix #60 (1)'] === 1, 'unresolved threads → fix cycle 1')
  ok(out[4].outcome === 'escalated' && !st.n['build #4'], 'two open PRs → escalate')
  ok(out[5].outcome === 'merged', 'resumed PR with nothing new to review → clean')
}

// ── fix cycles (per-PR flow) ───────────────────────────────────────────
{
  const { out, st } = await run('three-fix-cycles-then-escalate', {
    mode: 'single',
    tickets: [t(2, { complex: true })],
    on: l => (l.startsWith('review') || l.startsWith('re-review') ? { verdict: 'NEEDS_FIXES' } : undefined),
  })
  ok(out[2].outcome === 'escalated' && out[2].cycles === 3, 'escalated after 3 cycles')
  ok(st.spawned.filter(l => l.startsWith('fix')).length === 3, 'exactly 3 fixers')
}
{
  const models = []
  const { out } = await run('fixer-model-escalates', {
    mode: 'single',
    tickets: [t(2)],
    on: (l, _p, _s, o) => {
      if (l.startsWith('fix')) models.push(o.model)
      if (l === 'review #102' || l === 're-review #102 (1)') return { verdict: 'NEEDS_FIXES' }
      return undefined
    },
  })
  ok(out[2].outcome === 'merged' && out[2].cycles === 2, 'clean on the second cycle')
  ok(models.join() === 'sonnet,opus', `fixer tier sonnet then opus (saw ${models})`)
}
{
  const { out, st } = await run('no-new-commits-is-needs-fixes', {
    mode: 'single',
    tickets: [t(2)],
    on: l => {
      if (l === 'review #102') return { verdict: 'NEEDS_FIXES' }
      if (l === 're-review #102 (1)') return { verdict: 'blocked', noNewCommits: true }
      return undefined
    },
  })
  ok(st.n['fix #102 (2)'] === 1 && out[2].outcome === 'merged', 'findings stand → next cycle')
}
{
  const { out, st } = await run('held-branch-cleans-and-retries-once', {
    mode: 'single',
    tickets: [t(2)],
    on: (l, _p, s) => (l === 'review #102' && s.n[l] === 1 ? { verdict: 'blocked', held: true } : undefined),
  })
  ok(st.n['review #102'] === 2 && st.n['cleanup #2'] === 1 && out[2].outcome === 'merged', 'cleanup + one re-spawn')
}

// ── checks gate ────────────────────────────────────────────────────────
{
  const { out, st } = await run('red-code-earns-a-fix-cycle', {
    mode: 'single',
    tickets: [t(2)],
    on: (l, p, s) => {
      if (l === 'gate #102' && s.n[l] === 1) {
        ok(/gh run rerun/.test(p), 'first gate may retry')
        return { verdict: 'RED_CODE', url: 'https://job/1', rerunUsed: true }
      }
      if (l === 'gate #102') ok(/retry is spent/.test(p), 'second gate may not retry')
      if (l === 'fix #102 (1)') ok(/https:\/\/job\/1/.test(p), 'fixer gets the job URL')
      return undefined
    },
  })
  ok(st.n['fix #102 (1)'] === 1 && st.n['re-review #102 (1)'] === 1, 'fix + re-review')
  ok(out[2].outcome === 'merged', 'then merged')
}
{
  const { out, st } = await run('infra-red-escalates', {
    tickets: [t(2)],
    on: l => (l === 'gate #102' ? { verdict: 'ESCALATE', reason: 'RED infra run=9 reason=startup_failure' } : undefined),
  })
  ok(out[2].outcome === 'escalated' && !st.spawned.some(l => l.startsWith('fix')), 'no fixer on infra-red')
  ok(!st.n['merge #102'], 'never merged on red')
}
{
  const { st } = await run('no-ci-no-gate', { tickets: [t(2)], args: { ci: false } })
  ok(!st.spawned.some(l => l.startsWith('gate')) && st.n['merge #102'] === 1 && st.n['merge #900'] === 1, 'CI: none merges without a gate')
}

// ── conflict queue ─────────────────────────────────────────────────────
{
  // #3 and #4 conflict until each gets its merge-fix. The queue fixes one at
  // a time; #2 and #5 (green throughout) integrate while a merge-fix runs.
  const models = []
  const { out, st } = await run('conflict-queue', {
    tickets: [t(2), t(3), t(4), t(5)],
    delay: l => (l.startsWith('merge-fix') ? 60 : l === 'gate #105' ? 40 : 5),
    on: (l, p, s, o) => {
      const pr = Number((l.match(/#(\d+)/) || [])[1])
      if (l.startsWith('merge-fix')) {
        models.push(o.model)
        ok(/git merge origin\/developer\/spec-1/.test(p) && !/--force/.test(p.replace(/never `--force`[^.]*/, '')), 'a sub-issue merges the integration branch in, no force-push')
      }
      if (l.startsWith('gate ') && (pr === 103 || pr === 104)) {
        const fixes = s.n[`merge-fix #${pr} (1)`] || 0
        return fixes ? { verdict: 'GREEN' } : { verdict: 'DIRTY' }
      }
      return undefined
    },
  })
  ok([2, 3, 4, 5].every(n => out[n].outcome === 'integrated'), 'everything integrated')
  ok(st.maxMergeFixing === 1, `one merge-fix alive at most (saw ${st.maxMergeFixing})`)
  ok(st.spawned.filter(l => l.startsWith('merge-fix')).length === 2, 'one merge-fix per conflicting PR')
  ok(models.every(m => m === 'sonnet'), `first merge-fixes on Sonnet (saw ${models})`)
  const fixStart = st.spawned.indexOf('merge-fix #103 (1)')
  ok(fixStart >= 0 && st.spawned.indexOf('merge #105') > fixStart, 'the green sibling integrated while the queue was busy')
  ok(st.logs.some(m => /conflict queue/.test(m)), 'the switch is said out loud')
}
{
  const models = []
  const { out, st } = await run('wrong-resolution-retries-on-opus-then-escalates', {
    tickets: [t(2)],
    on: (l, _p, _s, o) => {
      if (l.startsWith('merge-fix')) models.push(o.model)
      return l === 'gate #102' ? { verdict: 'DIRTY' } : undefined
    },
  })
  ok(models.join() === 'sonnet,opus', `Sonnet, then one Opus retry (saw ${models})`)
  ok(out[2].outcome === 'escalated' && /unchanged developer\/spec-1/.test(out[2].reason), 'then escalate')
}
{
  const models = []
  const { out } = await run('blocked-sonnet-merge-fix-retries-on-opus', {
    tickets: [t(2)],
    on: (l, _p, s, o) => {
      if (l.startsWith('merge-fix')) { models.push(o.model); return o.model === 'sonnet' ? { status: 'blocked', reason: 'lost' } : undefined }
      if (l === 'gate #102') return s.n['merge-fix #102 (2)'] ? { verdict: 'GREEN' } : { verdict: 'DIRTY' }
      return undefined
    },
  })
  ok(models.join() === 'sonnet,opus' && out[2].outcome === 'integrated', `blocked on Sonnet → Opus → integrated (saw ${models})`)
}
{
  const { spec } = await run('spec-pr-conflict-merges-main-in', {
    tickets: [t(2)],
    on: (l, p, s) => {
      if (l.startsWith('merge-fix #900')) ok(/git merge origin\/main/.test(p) && !/git rebase origin/.test(p), 'the spec PR merges main in, never rebases')
      if (l === 'gate #900') return s.n['merge-fix #900 (1)'] ? { verdict: 'GREEN' } : { verdict: 'DIRTY' }
      return undefined
    },
  })
  ok(spec.outcome === 'merged' && spec.mergefix === 1, 'then merged')
}
{
  const { out, st } = await run('failed-merge-is-a-conflict', {
    tickets: [t(2)],
    on: (l, _p, s) => (l === 'merge #102' && s.n[l] === 1 ? { outcome: 'dirty' } : undefined),
  })
  ok(st.n['merge #102'] === 2 && out[2].outcome === 'integrated', 'gate again from the queue, then integrated')
}

// ── merge-fix mode, plan errors ────────────────────────────────────────
{
  const { result, st } = await run('merge-fix-mode', {
    tickets: [], args: { mergeFix: 77 },
    on: (l, _p, _s, o) => { if (l === 'merge-fix #77') ok(o.model === 'sonnet', 'on Sonnet'); return undefined },
  })
  ok(st.spawned.join() === 'merge-fix #77,cleanup #77' && result.mergeFix === 77, 'only the merge-fix job and its cleanup')
}
{
  const { result, st } = await run('plan-error', {
    tickets: [],
    on: l => (l === 'plan' ? { error: 'more than 50 sub-issues: split the spec' } : undefined),
  })
  ok(/split the spec/.test(result.error) && st.spawned.length === 1, 'stops on a plan error')
}

console.log(fails ? `${fails}/${checks} checks FAILED` : `PASS ${checks} checks`)
process.exit(fails ? 1 : 0)
