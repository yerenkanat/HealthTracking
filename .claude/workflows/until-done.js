export const meta = {
  name: 'anabala-until-done',
  description: 'Keep building Ana-Bala until the PM reports no spec gap left worth doing: pm → build → audit → fix → commit, repeating',
  phases: [
    { title: 'Decide' },
    { title: 'Build' },
    { title: 'Audit' },
    { title: 'Fix' },
    { title: 'Integrate' },
  ],
}

const ROOT = 'c:/Users/yeren/OneDrive/Desktop/Projects/HealthTracking'

// Charters live on disk so an agent reads its real role rather than a summary
// of one. If a file is missing the agent is told to say so and stop, instead of
// improvising a role.
const charter = (file) => `Read ${ROOT}/.claude/agents/${file} and act as that
role, following it exactly. If that file does not exist, say so and stop rather
than improvising. Work in ${ROOT}.`

const NEXT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['done', 'key', 'brief', 'why'],
  properties: {
    done: { type: 'boolean', description: 'true when no gap worth building remains' },
    key: { type: 'string', description: 'short slug for this unit, or "" when done' },
    brief: { type: 'string', description: 'the full build brief; empty when done' },
    why: { type: 'string', description: 'why this one next, or why nothing remains' },
  },
}

const AUDIT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['blocking', 'suiteGreen', 'findings'],
  properties: {
    blocking: { type: 'boolean' },
    suiteGreen: { type: 'boolean' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['severity', 'file', 'what', 'failure'],
        properties: {
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          file: { type: 'string' },
          what: { type: 'string' },
          failure: { type: 'string' },
        },
      },
    },
  },
}

// Bounded so a confused PM cannot spin forever. Each round is a whole feature,
// so this is a lot of work, not a lot of retries.
const MAX_ROUNDS = 12
const shipped = []
let dryRounds = 0

for (let round = 1; round <= MAX_ROUNDS; round++) {
  phase('Decide')
  const next = await agent(
    `${charter('anabala-pm.md')}

Already shipped this run: ${shipped.length ? shipped.map((s) => s.key).join(', ') : 'nothing yet'}.

Decide the SINGLE next unit of work. Read what the panel and app actually have
before deciding — do not propose something already built.

Set done:true only when nothing remains that is worth building: no wholly
missing spec frame, no finished code without a caller, no backend data that
reaches the client and is never rendered. "Everything is polished" is not the
bar; "nothing left that would change what a user can do" is.`,
    { label: `pm:round-${round}`, phase: 'Decide', schema: NEXT_SCHEMA, agentType: 'general-purpose' },
  )

  if (!next) {
    log(`round ${round}: PM returned nothing — stopping rather than guessing`)
    break
  }
  if (next.done) {
    log(`round ${round}: PM reports nothing left — ${next.why}`)
    break
  }

  log(`▶ round ${round}: ${next.key} — ${next.why}`)

  // App work and backend work have different charters; the PM's brief names
  // which. Dart-only units go to the Flutter specialist.
  const isApp = /^app[-:]|flutter|\bDart\b/i.test(next.key + ' ' + next.brief.slice(0, 400))
  const builderFile = isApp ? 'anabala-app.md' : 'anabala-builder.md'

  phase('Build')
  const built = await agent(
    `${charter(builderFile)}\n\n--- BRIEF ---\n${next.brief}\n\n` +
    `Build it to completion, including tests and the revert-verification. Do NOT commit.`,
    { label: `build:${next.key}`, phase: 'Build', agentType: 'general-purpose' },
  )

  if (!built) {
    dryRounds++
    log(`✕ ${next.key}: builder returned nothing (${dryRounds} dry)`)
    // Two failures in a row means something is wrong with the plan, not with
    // one attempt. Stop rather than burning the budget on a loop.
    if (dryRounds >= 2) { log('two dry rounds — stopping'); break }
    continue
  }
  dryRounds = 0

  phase('Audit')
  const audit = await agent(
    `${charter('anabala-auditor.md')}\n\nAudit what was just built: ${next.key}.\n\n` +
    `The brief was:\n${next.brief}\n\nThe builder reported:\n${built}\n\n` +
    `Assume it is not finished.`,
    { label: `audit:${next.key}`, phase: 'Audit', schema: AUDIT_SCHEMA, agentType: 'general-purpose' },
  )

  if (audit && audit.blocking) {
    const worst = audit.findings
      .filter((f) => f.severity !== 'low')
      .map((f) => `- [${f.severity}] ${f.file}: ${f.what}\n  fails when: ${f.failure}`)
      .join('\n')
    phase('Fix')
    await agent(
      `${charter(builderFile)}\n\nFix these audit findings on ${next.key}. Fix what is ` +
      `named; do not re-architect. Re-run the suites afterwards.\n\n${worst}`,
      { label: `fix:${next.key}`, phase: 'Fix', agentType: 'general-purpose' },
    )
  }

  phase('Integrate')
  const commit = await agent(
    `${charter('anabala-integrator.md')}\n\nIntegrate and commit: ${next.key}.\n\n` +
    `Brief:\n${next.brief}\n\nBuilder:\n${built}\n\n` +
    `Audit: ${audit ? JSON.stringify(audit) : 'no audit returned'}\n\n` +
    `Run every suite first. If anything is red, do not commit — report and stop.`,
    { label: `commit:${next.key}`, phase: 'Integrate', agentType: 'general-purpose' },
  )

  shipped.push({ key: next.key, why: next.why, audit: audit ?? null, commit })
  log(`✔ ${next.key} (${shipped.length} shipped this run)`)
}

return { shipped: shipped.map((s) => s.key), detail: shipped }
