export const meta = {
  name: 'ultra-fanout',
  description: 'Flat fan-out: per-subtask explore → implement → verify-in-worktree; merge and global verify stay in the main loop',
  whenToUse: 'Only via the /ultra command, after its gates pass and the user has seen the plan',
  phases: [
    { title: 'Research', detail: 'explorer per subtask (read-only)' },
    { title: 'Implement', detail: 'implementer per subtask, worktree isolation' },
    { title: 'Verify', detail: 'verifier per subtask, inside its worktree' },
  ],
}

// 由 /ultra 指令在 planner 產出計畫、使用者看過後傳入:
// args = { subtasks: [{ id, goal, files: [..], criteria, needsResearch, highRisk }] }
// 互動點與跨 subtask 的整合(展示計畫、merge、全域驗證、修復迴圈)都留在主對話層,不在本 script 內

if (!args || !Array.isArray(args.subtasks) || args.subtasks.length === 0) {
  throw new Error('ultra-fanout requires args.subtasks — run it via the /ultra command')
}

const VERDICT = {
  type: 'object',
  properties: {
    pass: { type: 'boolean' },
    failures: { type: 'array', items: { type: 'string' } },
    evidence: { type: 'string' },
    worktree: { type: 'string' },
  },
  required: ['pass', 'worktree'],
}

// implementer 在隔離 worktree 中作業,後續 verifier 與主 Agent 的 merge 都需要知道路徑
const REPORT_PATH_RULE =
  'Your report MUST include a line `Worktree: <absolute path of your working directory>` — run `pwd` to get it.'

const normal = args.subtasks.filter(s => !s.highRisk)
const risky = args.subtasks.filter(s => s.highRisk)
log(`fan-out width: ${normal.length} parallel, ${risky.length} sequential (high-risk)`)

// 一般 subtask:各自流過三個 stage,互不等待(A 在 implement 時 B 可能還在 research)
const results = await pipeline(
  normal,
  s => s.needsResearch
    ? agent(
        `Research for subtask ${s.id}: ${s.goal}\n` +
        'Read-only. Report invariants, relevant code locations, and existing conventions only, under 300 words.',
        { agentType: 'explorer', phase: 'Research', label: `explore:${s.id}` })
    : '',
  (research, s) => agent(
    [
      `Subtask ${s.id}: ${s.goal}`,
      `Files you own (do not touch others): ${s.files.join(', ')}`,
      `Acceptance criteria: ${s.criteria}`,
      research ? `Research notes:\n${research}` : '',
      'Project-scoped build/tests only — never the full solution build or full suite.',
      REPORT_PATH_RULE,
    ].filter(Boolean).join('\n'),
    { agentType: 'implementer', phase: 'Implement', label: `impl:${s.id}`, isolation: 'worktree' }),
  (report, s) => agent(
    `Verify subtask ${s.id} against these acceptance criteria: ${s.criteria}\n` +
    `Implementer report:\n${report}\n` +
    'The changes live in the worktree path stated in the report (`Worktree:` line) — inspect the diff and run the checks INSIDE that directory, not the main working tree. ' +
    'Re-run the checks yourself — do not trust the report. Return that worktree path in the `worktree` field.',
    { agentType: 'verifier', phase: 'Verify', label: `verify:${s.id}`, schema: VERDICT })
    .then(v => ({ id: s.id, files: s.files, verdict: v }))
)

// 高風險 subtask:單一 writer、嚴格串行,不進平行池;同樣在隔離 worktree 中作業
const riskyResults = []
for (const s of risky) {
  const report = await agent(
    [
      `Subtask ${s.id} (HIGH RISK — sole writer, no other implementer is running): ${s.goal}`,
      `Files you own: ${s.files.join(', ')}`,
      `Acceptance criteria: ${s.criteria}`,
      'Project-scoped build/tests only.',
      REPORT_PATH_RULE,
    ].join('\n'),
    { agentType: 'implementer', phase: 'Implement', label: `impl-risky:${s.id}`, isolation: 'worktree' })
  const v = await agent(
    `Verify high-risk subtask ${s.id} against: ${s.criteria}\nImplementer report:\n${report}\n` +
    'The changes live in the worktree path stated in the report — run the checks INSIDE that directory. ' +
    'Re-run everything yourself. Return that worktree path in the `worktree` field.',
    { agentType: 'verifier', phase: 'Verify', label: `verify-risky:${s.id}`, schema: VERDICT })
  riskyResults.push({ id: s.id, files: s.files, verdict: v })
}

// merge 與全域 build/test barrier 由主 Agent 在 script 結束後執行(見 commands/ultra.md 階段 5-7)
const perItem = [...results.filter(Boolean), ...riskyResults]
return {
  perItem,
  failed: perItem.filter(r => !r.verdict?.pass).map(r => r.id),
  worktrees: perItem.map(r => ({ id: r.id, path: r.verdict?.worktree })),
}
