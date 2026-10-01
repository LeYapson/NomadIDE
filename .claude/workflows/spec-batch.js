export const meta = {
  name: 'spec-batch',
  description: 'Run /skills-v8:spec-write across every page whose spec is missing or stale, in throttled waves, then apply the deferred shared-file writes in one merge pass. Plans first and writes nothing until confirmed. Resumable: progress is checkpointed per wave, so an interrupted campaign costs at most the wave in flight.',
  phases: [
    { title: 'Preflight', detail: 'Resolve the workspace and capture the authoritative page inventory from t_bas_page. A filesystem walk cannot tell a page from a non-page, so without this the plan carries false targets.', model: 'haiku' },
    { title: 'Plan',      detail: 'plan_specs.mjs: bucket every page as generate/update/current, group into waves, chunk against the agent budget. Writes nothing.', model: 'haiku' },
    { title: 'Write',     detail: 'Per wave, in parallel: /skills-v8:spec-write <target> --page-only (or --object-only) --no-review. Each target touches only its own page files and journals anything shared. Requires confirmed:true; a dry run spawns no target agent at all.' },
    { title: 'Review',    detail: 'The review gate for every greenfield spec this chunk wrote, run at depth 1 rather than inside the target -- a reviewer spawned from inside a target deadlocks until a watchdog kills it. Updates each result file with its verdict so the report can flag anything unreviewed.' },
    { title: 'Merge',     detail: 'merge_deferred.mjs: apply every journalled index row, utility contract, platform-spec addition and producer note ONCE, single-threaded. Idempotent, so re-running a chunk is safe.', model: 'haiku' },
    { title: 'Report',    detail: 'batch_results.mjs: results.json, run-report.md and the _failed.txt retry list.', model: 'haiku' },
  ],
}

// -- SOURCE OF TRUTH -------------------------------------------------------------
// Canonical copy lives in the skills-v8 marketplace plugin (plugins/skills-v8/workflows/).
// Mirrored into the consumer project's .claude/workflows/ by the sync-workflows SessionStart hook.
// Edit it HERE - a project-local copy is overwritten on the next session.
//
// The sync is NOT optional and cannot be replaced by scriptPath. The Workflow tool refuses a
// scriptPath outside the working directory ("must be a script path this tool returned, or a file
// you can already read"), and a marketplace plugin lives outside every consumer workspace. So the
// file has to be inside the project before it can be invoked at all, by name or by path.

// -- Why the child is an agent, not a nested workflow ----------------------------
// iva-object-batch drives iva-object-skill via workflow(), which returns a rich structured result.
// There is no spec-write WORKFLOW - spec-write is a skill - so each target runs as an agent() that
// invokes the skill. Two consequences shape everything below:
//   1. Nothing is returned unless we ask for it, hence TARGET_SCHEMA and the instruction to marshal
//      spec-write's own Phase 3 summary into it.
//   2. Each target agent spawns spec-write's OWN agents (A/B/C, review, Explore). The harness's
//      min(16, cpus-2) cap counts only this workflow's agent() calls, so 16 in flight means ~64
//      real agents against one database. That is why waves are small and set by the planner rather
//      than by handing every target to one parallel() call.
//
// runTarget() therefore passes an explicit `agentType: 'general-purpose'`, and that argument is
// LOAD-BEARING - do not drop it to "use the default". An agent() call with no agentType gets the
// built-in `workflow-subagent`, whose definition is tools:["*"] but disallowedTools:[SendUserMessage,
// Agent, Workflow]. The Agent deny is silent: the target can still invoke the spec-write Skill, but
// every step INSIDE it that spawns a subagent turns into a no-op that reports success. Measured on a
// real run with the default type: the Phase 3 review gate never ran on any greenfield target (it
// self-reported "skipped", and the run report still read 3/3 clean), the A/B/C extraction collapsed
// to one inline single-threaded context, and the nested-agent figure that consequence 2 above and
// the planner's AGENTS_PER_* constants are both premised on was actually 0. general-purpose carries
// no Agent deny, so the fan-out and the gate work as designed.

// -- Args ------------------------------------------------------------------------
// pages        (optional string) - path to a page inventory file already on disk. When absent -- the
//                            normal path -- Preflight captures one itself and ABORTS if it cannot,
//                            because the planner's fallback is a filesystem walk whose target list
//                            includes non-pages (css/*, template_pages/*) and misses virtual pages.
// confirmed    (optional bool)   - FALSE BY DEFAULT. Without it the run stops after Plan and writes
//                            nothing. `--full` rewrites hundreds of files; the count is confirmed
//                            by a human before the first write, and a workflow cannot prompt.
//                            NOTHING bypasses this gate -- dry_run does not either.
// run_id       (optional string) - default `full-<mode>`, or `full-<mode>-dry` under dry_run. Stable
//                            across invocations so resume works.
// resume       (optional string) - a previous run dir; targets it finished are dropped from the plan.
// wave_size    (optional number) - targets per wave. Default 6, set in the planner. A value that is
//                            not a positive integer ABORTS the run; it is never defaulted silently.
// agent_budget (optional number) - chunk boundary in estimated agents. Default 700, set in the
//                            planner. Same validation as wave_size.
// pass         (optional 'pages'|'objects'|'both') - default both.
// mode         (optional 'rnd'|'project') - overrides workspace detection. Layers derive from it.
// only         (optional string) - comma-separated `module/page`, `module/otype` or bare `module`.
//                            NARROWS the plan; it is not a new scope. Two things need it: the
//                            documented `_failed.txt` retry list has to be consumable by
//                            something, and a smoke run on a handful of targets is the only way
//                            to validate the pipeline before committing to hundreds of writes.
// dry_run      (optional bool)   - plan, plus a merge dry-run. Spawns NO target agent at all, so no
//                            spec-write invocation exists to go wrong. Still requires
//                            confirmed:true to get past the gate, and runs under its own `-dry` run
//                            directory so nothing it records can be read by a real run's --resume.
// script_agent (optional string) - agentType for the command runners. Defaults to this plugin's
//                            skills-v8:script-runner, auto-falling back to general-purpose when
//                            that is not registered in the session (see the note above runScript).
// script_model (optional string) - model for the command runners. Default 'haiku'; 'inherit' uses
//                            the session model. Relays of unbounded nested data opt out of it.
// include_current (optional bool) - also queue pages whose spec is CURRENT, as `update` targets.
//                            Expensive (a full update pass per spec) and normally pointless, but it
//                            is the only batch route to a virtual page that already has a spec,
//                            which a file-mtime check can never call stale.
// skill_dir    (optional string) - absolute path to the spec-write skill directory. The skill
//                            invoking this workflow KNOWS its own directory (the harness prints
//                            "Base directory for this skill" when it loads) and batch-full.md tells
//                            it to pass that here, so the runners never have to guess. When it is
//                            omitted the runners resolve the installed plugin cache themselves with
//                            a deterministic node one-liner (see RESOLVE_SKILL). A maintainer can
//                            also point it at a dev checkout.
//
// args arrives as an object from Workflow({args:{...}}), but as PROSE from the Skill and
// slash-command path ("pages=.tmp/pages.json, confirmed=true"). A bare JSON.parse throws on that
// prose at line 1, before any phase runs, and the harness surfaces it as an opaque "JSON Parse
// error". Accept all three shapes. NO argument is required, so an unparseable string degrades to {}
// and the run behaves as an argument-less invocation: Preflight captures the inventory and the run
// stops at the confirmation gate having written nothing. The one class of malformed argument that
// aborts is a numeric one -- see numArg below -- because both numbers bound real concurrency.
// @prose-args-parser-start
const _args = (() => {
  if (args && typeof args === 'object') return args
  const s = String(args ?? '').trim()
  if (!s) return {}
  try { return JSON.parse(s) } catch { /* not JSON - fall through to the prose path */ }
  const o = {}
  // Locate key positions, then take each value as everything up to the NEXT key. Matching
  // key/value pairs directly would end a value at the first comma, silently truncating a path
  // or a comma-separated list. The leading [,{s] (or start-of-string) anchors a key to a
  // token boundary; without it the scan would also match mid-key.
  const hits = [...s.matchAll(/(?:^|[,{\s])\s*([a-z0-9_]+)\s*[=:]\s*/gi)]
  for (let i = 0; i < hits.length; i++) {
    const start = hits[i].index + hits[i][0].length
    const end = i + 1 < hits.length ? hits[i + 1].index : s.length
    const val = s.slice(start, end).trim().replace(/[,;}\s]+$/, '').replace(/^["']|["']$/g, '')
    if (!val) continue
    o[hits[i][1]] = val === 'true' ? true : val === 'false' ? false : val
  }
  return o
})()
// @prose-args-parser-end

// Raw, straight off the argument object. The `_IN` names are deliberate: everything that reaches
// a command line is re-declared below through shellArg(), and keeping the raw value under a
// different name means a later edit cannot interpolate the unchecked one by reflex.
const PAGES_IN = _args.pages || null
const CONFIRMED = _args.confirmed === true || _args.confirmed === 'true'
const RESUME_IN = _args.resume || null
const PASS_IN = _args.pass || null
const MODE_IN = _args.mode || null
const ONLY_IN = Array.isArray(_args.only) ? _args.only.join(',') : (_args.only || null)
const DRY_RUN = _args.dry_run === true || _args.dry_run === 'true'
const INCLUDE_CURRENT = _args.include_current === true || _args.include_current === 'true'
const SCRIPT_MODEL = _args.script_model === 'inherit' ? undefined : (_args.script_model || 'haiku')

// The outcomes that mean a target is finished. ONE list, used by both the failure filter and the
// stall detector below, and kept in step with DONE_OUTCOMES in plan_specs.mjs / DONE in
// batch_results.mjs minus `clean`, which TARGET_SCHEMA does not allow a target to report. A third
// hand-copied list here had already drifted from the other two.
const TARGET_DONE = ['written', 'skipped-current']

// `Number('abc')` is NaN and NaN is FALSY, so the previous `x ? Number(x) : null` shape turned a
// malformed number into "flag omitted": the planner quietly applied its own default while this
// script logged "waves of up to NaN". Both numbers bound real concurrency against one database, so
// a value that cannot be read is named and aborts rather than being guessed at. Collected here and
// reported once Preflight has a phase to log into.
const badArgs = []
function numArg(name, raw, integer) {
  if (raw === undefined || raw === null || raw === '') return null
  if (typeof raw === 'boolean') { badArgs.push(`${name}: given as a bare flag; it needs a number`); return null }
  const n = Number(raw)
  if (!Number.isFinite(n) || n < 1 || (integer && !Number.isInteger(n))) {
    badArgs.push(`${name}: '${raw}' is not a positive ${integer ? 'integer' : 'number'}`)
    return null
  }
  return n
}
const WAVE_SIZE = numArg('wave_size', _args.wave_size, true)
const AGENT_BUDGET = numArg('agent_budget', _args.agent_budget, false)

// -- Values that get interpolated into a command line ----------------------------
// Every command below is a STRING handed to a runner agent, which executes it in bash or in
// PowerShell. So each interpolated value is live shell text, and the set of characters that ends
// an argument or starts a substitution differs per shell: `"` closes the argument in both, a
// backtick and `$` substitute in PowerShell (and `$` in bash too), and a trailing `\` inside bash
// double quotes escapes the closing quote and swallows the rest of the line.
//
// The Report phase already handles this with argSafe(), which REPLACES those characters -- correct
// there, because those values are log text where legibility beats fidelity. It is the wrong tool
// here: `pagesPath` and `RUN_DIR` are Windows paths full of backslashes, and replacing them would
// silently point the command at a different file. Nothing that has to round-trip byte-exact may be
// mangled.
//
// So these REFUSE instead. A refusal lands in badArgs and aborts in Preflight, before any write,
// which is the same trade numArg makes: a value that cannot be passed safely is named rather than
// guessed at. A path containing `"`, a backtick or `$` is vanishingly rare (`$` appears in an
// admin UNC share, `\\host\C$\...`) and telling the operator beats corrupting the run.
//
// `--pass` and `--mode` are quoted below as well. They were bare, so a value with a space split
// into two argv entries and the planner consumed the second as a positional and discarded it.
const SHELL_UNSAFE = /["`$]/
const PATH_GRAMMAR = /^[A-Za-z0-9 _.:,\\/'()[\]{}@+=!#%^~-]+$/
// module/page, module/otype or a bare module, comma-separated, optionally `project/`-prefixed.
const TARGET_GRAMMAR = /^[A-Za-z0-9_./, -]+$/

function shellArg(name, raw, grammar, grammarHint) {
  if (raw === undefined || raw === null || raw === '') return null
  const v = String(raw)
  if (/[\r\n\t\0]/.test(v)) {
    badArgs.push(`${name}: contains a newline, tab or NUL. That would end the command line mid-argument.`)
    return null
  }
  if (SHELL_UNSAFE.test(v)) {
    badArgs.push(`${name}: '${v}' contains a double quote, backtick or '$'. Those are live syntax inside the double quotes this value is passed in (PowerShell substitutes a backtick and '$'; bash substitutes '$'), and the value has to reach the script byte-exact, so it is refused rather than rewritten. Re-invoke with a value free of those characters.`)
    return null
  }
  if (!grammar.test(v)) {
    badArgs.push(`${name}: '${v}' is outside the accepted grammar (${grammarHint}).`)
    return null
  }
  return v
}

const PAGES = shellArg('pages', PAGES_IN, PATH_GRAMMAR, 'a filesystem path')
const RESUME = shellArg('resume', RESUME_IN, PATH_GRAMMAR, 'a previous run directory path')
const PASS = shellArg('pass', PASS_IN, /^[a-z]+$/, 'pages, objects or both')
const MODE = shellArg('mode', MODE_IN, /^[a-z]+$/, 'rnd or project')
const ONLY = shellArg('only', ONLY_IN, TARGET_GRAMMAR, "comma-separated 'module/page', 'module/otype' or bare 'module'")

// A dry run must never share a run directory with a real run. Both default to `full-<mode>`, and
// anything a dry run left in that directory would be read straight back by the real run's --resume.
// plan_specs.mjs already suffixes ANY un-suffixed run id with `-dry`, default or explicit. This
// suffix is therefore belt-and-braces rather than the only guard -- it keeps the id the workflow
// logs and returns consistent with the directory the planner chose, instead of reporting a bare id
// while writing to a `-dry` path. Both are idempotent, so a caller echoing back a previous dry
// run's id does not get `-dry-dry`.
//
// Checked against plan_specs.mjs's own RUN_ID_RE (/^[A-Za-z0-9][A-Za-z0-9._-]*$/) rather than the
// looser path grammar: run_id is spliced into the run DIRECTORY path there, so '/', '\' or '..'
// would escape .tmp/spec-batch/ entirely. The planner refuses those too; checking here as well
// means the message names `run_id` in this script's own abort list instead of surfacing as an
// opaque planner exit 2 one phase later.
const RUN_ID_IN = shellArg('run_id', _args.run_id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/, 'a single path component: letters, digits, dot, underscore, hyphen') || null
const RUN_ID = RUN_ID_IN && DRY_RUN && !/-dry$/.test(RUN_ID_IN) ? `${RUN_ID_IN}-dry` : RUN_ID_IN

// Where the runners look for the skill's scripts. The skill that invokes this workflow knows its
// own directory and passes it as `skill_dir` (batch-full.md, step 1) -- that is the NORMAL path,
// and it is also how a maintainer points a run at a dev checkout without one machine's path being
// baked into what every consumer installs (it used to be `c:/net/rnd-claude-plugins/...`).
//
// The fallback, for a caller that omitted it, is a deterministic `node -e` one-liner rather than
// prose asking the runner to glob and compare versions. Three things it gets right that the prose
// versions did not, each measured:
//   - it anchors on os.homedir(), not `C:/Users/*` (which matched ANY account's cache on a shared
//     machine) and not `~` (which the Glob tool never expands, and which Git Bash expands to an
//     MSYS `/c/Users/...` path that node.exe and PowerShell cannot open);
//   - it prints a forward-slashed DRIVE-LETTER path, which both shells the runner may pick accept;
//   - it sorts versions numerically (7.10.0 after 7.9.0) instead of leaving that to the model.
// It is written to be identical text under Bash and PowerShell: no `$`, no backtick, no `!`, no
// backslash (bash would eat it inside double quotes), single quotes inside the double-quoted arg.
//
// SKILL_DIR is QUOTED in every command template below. Unquoted, a home directory with a space in
// it (`C:\Users\Some One`) split the path into two arguments and node reported MODULE_NOT_FOUND --
// and the runner is told to change nothing else, so it could not add the quotes itself.
const SKILL_DIR_OVERRIDE = shellArg('skill_dir', _args.skill_dir, PATH_GRAMMAR, 'an absolute path to the spec-write skill directory')

const RESOLVE_SKILL_CMD = "node -e \"const fs=require('fs'),p=require('path'),os=require('os');const r=p.join(os.homedir(),'.claude','plugins','cache','rnd-claude-plugins','skills-v8');const v=fs.existsSync(r)?fs.readdirSync(r).filter(d=>fs.existsSync(p.join(r,d,'skills','spec-write','scripts','plan_specs.mjs'))):[];v.sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));console.log(v.length?p.join(r,v[v.length-1],'skills','spec-write').split(p.sep).join('/'):'NOT FOUND')\""

const RESOLVE_SKILL = SKILL_DIR_OVERRIDE
  ? `## The spec-write skill directory (given to you)

SKILL_DIR=${SKILL_DIR_OVERRIDE}. Every command below is written against SKILL_DIR. Do not go
looking for another copy: this one was passed in deliberately.`
  : `## Resolve the spec-write skill directory (do this first, once)

Run this exactly as written, in Bash or PowerShell -- it prints ONE line, the absolute path of the
newest installed spec-write skill directory (or the literal NOT FOUND):

    ${RESOLVE_SKILL_CMD}

SKILL_DIR is the printed path. It is already a drive-letter path with forward slashes, so use it
verbatim in the commands below. If it prints NOT FOUND, report that and stop -- do not guess a
path and do not search with any other tool.`

// -- Schemas ---------------------------------------------------------------------
//
// Two rules govern every schema below, both learned the hard way.
//
// 1. NOTHING A SCRIPT'S ERROR PATH DOES NOT PRINT MAY BE `required`. Each of these scripts has a
//    `fail()` that prints a short object and exits 2 -- plan_specs.mjs prints only
//    {exit_code, error, total, waves}. Requiring run_dir/counts/first_chunk_waves there left the
//    relay agent with a choice between violating the schema and INVENTING three fields, on exactly
//    the path the planner is most careful about (bad args, and the truncated-inventory refusal).
//    So `exit_code` is the only required field anywhere: it is the one thing every path prints, and
//    it is what this script branches on.
// 2. `additionalProperties` STAYS OPEN on every relay schema. The runner is told to report the
//    script's JSON verbatim; a closed schema turns a field somebody adds to a script into a
//    validation failure of the whole phase, which is the opposite of what "verbatim" is for. The
//    named properties are still worth listing -- they tell a small model which fields matter -- but
//    they are a floor, not a fence. TARGET_SCHEMA is the exception: nothing relays into it, the
//    target agent AUTHORS it, so there it is a real contract and stays closed.

const INVENTORY_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['exit_code'],
  properties: {
    // This step is several actions, not one command, so exit_code reports the STEP -- see the note
    // in its `extra` block. command_exit_code carries the raw process code of the printed command.
    exit_code: { type: 'number', description: 'Whole-step outcome: 0 only if every numbered step succeeded, non-zero otherwise.' },
    command_exit_code: { type: 'number', description: 'Exit code of the node command itself, separate from the step outcome.' },
    saved_to: { type: 'string', description: "ABSOLUTE path of the file holding the query result, copied from the MCP's own saved_to field -- NOT the path that was requested, which the MCP may not have honoured. Omit it if the query never ran -- never guess a path." },
    entries: { type: 'number', description: 'How many page_url values the result contains. Report the real number -- the plan is validated against it. Omit it if you could not count them.' },
    db: { type: 'string', description: 'DB_NAME() of the database that answered, so a wrong-database run is visible in the log rather than only in the results.' },
    error: { type: 'string', description: 'What went wrong, verbatim, if anything did.' },
  },
}

const PLAN_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['exit_code'],
  properties: {
    exit_code: { type: 'number', description: 'plan_specs.mjs exit code: 0 work planned | 3 nothing to do (NORMAL) | 2 bad args or an incomplete page inventory.' },
    run_id: { type: 'string' },
    run_dir: { type: 'string' },
    plan_path: { type: 'string' },
    workspace: { type: 'string' },
    mode: { type: 'string' },
    pass: { type: 'string' },
    wave_size: { type: 'number' },
    // Confirms the planner saw --dry-run, so the isolation check below is not taking it on trust.
    dry_run: { type: 'boolean' },
    // On exit 3 the planner says WHICH kind of nothing this is. Relay it verbatim: "every spec is
    // current" and "nothing was enumerated at all" are opposite situations with the same exit code.
    nothing_to_do_reason: { type: ['string', 'null'] },
    // Everything enumeration saw and did not queue, as numbers. Nested; relay it whole.
    coverage_counts: { type: 'object' },
    only: { type: ['array', 'null'], items: { type: 'string' }, description: 'The --only filter the planner applied, or null. Report null as a JSON null literal.' },
    layers: { type: 'array', items: { type: 'string' } },
    // Printed by plan_specs.mjs fail() on the exit-2 path INSTEAD of counts/first_chunk_waves.
    total: { type: 'number' },
    waves: { type: 'array', description: 'Always empty on the exit-2 path; the real grouping is in first_chunk_waves.' },
    counts: {
      type: 'object',
      properties: {
        generate: { type: 'number' }, update: { type: 'number' }, objects: { type: 'number' },
        current_skipped: { type: 'number' }, resume_skipped: { type: 'number' }, total: { type: 'number' },
      },
    },
    first_chunk_waves: {
      type: 'array',
      description: 'Waves of the FIRST CHUNK ONLY, in order. Report VERBATIM -- the grouping is the concurrency bound, not a formatting choice, and a dropped member is a target that never runs.',
      items: { type: 'array', items: { type: 'object', properties: { target: { type: 'string' }, kind: { type: 'string', description: "'page' or 'object'. Load-bearing: it selects the spec-write flags, and the wrong one sends the target down the wrong pipeline." }, layer: { type: 'string' }, action: { type: 'string' }, spec: { type: 'string', description: 'Exact spec path the target must write. Relay verbatim - the writer is told not to re-derive it.' } } } },
    },
    first_chunk_targets: { type: 'number' },
    first_chunk_est_agents: { type: 'number' },
    chunks: { type: 'number' },
    est_agents: { type: 'number' },
    over_budget: { type: 'boolean' },
    deferred_targets: { type: 'number' },
    escalations: { type: 'array', items: { type: 'string' } },
    coverage_boundary: { type: 'array', items: { type: 'string' } },
    warnings: { type: 'array', items: { type: 'string' } },
    error: { type: 'string' },
  },
}

// Only `review` is required, for the same reason `exit_code` is the only required field on the
// script schemas: it is the one thing every path can produce, including a reviewer that got
// nowhere. Requiring the counts would force an agent whose review failed to choose between
// violating the schema and inventing numbers.
const REVIEW_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['review'],
  properties: {
    review: {
      type: 'string',
      description: "One-line verdict. MUST start with 'PASSED' when no ISSUE and no GAP remain (e.g. 'PASSED 2 passes'); otherwise lead with what remains (e.g. '2 ISSUE remaining'). batch_results.mjs keys the Unreviewed section off the PASSED prefix.",
    },
    findings: { type: 'string', description: 'Counts raised and fixed, per severity. Free text.' },
    error: { type: 'string' },
  },
}

const TARGET_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  // `action` is required despite rule 1 above (nothing a failure path omits may be required),
  // because it is supplied by the ORCHESTRATOR in the prompt, not read off spec-write's summary --
  // the agent copies a literal it was handed, so every path can produce it, including a failure.
  // It was optional and unmentioned in Step 4, so no result file ever carried it and the
  // "Unreviewed greenfield specs" section keyed on it could never render.
  required: ['target', 'action', 'outcome'],
  properties: {
    target: { type: 'string' },
    outcome: {
      type: 'string',
      enum: ['written', 'skipped-current', 'failed', 'unknown'],
      description: "written = spec-write wrote content. skipped-current = it reported the spec already current (normal, not a failure). failed = it errored or refused. unknown = it finished but its summary could not be read.",
    },
    action: { type: 'string', description: 'generate or update, as the plan assigned it.' },
    files: { type: 'array', items: { type: 'string' }, description: 'Spec/tech files written, from spec-write\u0027s own Files-written summary.' },
    deferred: { type: 'number', description: 'Journal entries written for the merge phase. 0 is normal.' },
    review: { type: 'string', description: "spec-write's Review line verbatim, e.g. 'PASSED 1 pass' or 'skipped'." },
    error: { type: 'string' },
  },
}

const MERGE_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['exit_code'],
  properties: {
    exit_code: { type: 'number' },
    dry_run: { type: 'boolean' },
    journals: { type: 'number' },
    targets: { type: 'number' },
    files_written: { type: 'number' },
    // Makes files_written interpretable: a file every entry skipped is unchanged, not written.
    files_unchanged: { type: 'number' },
    applied: { type: 'number' },
    skipped: { type: 'number' },
    // merge_deferred.mjs prints these too, and they are the durable record of WHICH shared writes
    // landed. Omitting them from the schema made a verbatim relay a validation failure.
    applied_detail: { type: 'array', items: { type: 'string' } },
    skipped_detail: { type: 'array', items: { type: 'string' } },
    // LOAD-BEARING, not decorative. This is where the applier reports a LOST WRITE that it could
    // not prevent: two targets supplying the same utility-contract heading in one pass, where the
    // second replaces the first. It is not an `errors` entry because the merge itself succeeded --
    // which is exactly why it must not be dropped. Relay it, always.
    warnings: { type: 'array', items: { type: 'string' }, description: 'Merge warnings. Report every one verbatim: a lost cross-target contribution is reported here and nowhere else.' },
    // Printed instead of the counters when the run deferred nothing at all (no journal directory).
    note: { type: 'string' },
    // Printed by its fail() path, which prints {exit_code, error, applied} and nothing else.
    error: { type: 'string' },
    errors: { type: 'array', items: { type: 'string' } },
  },
}

const REPORT_SCHEMA = {
  type: 'object',
  additionalProperties: true,
  required: ['exit_code'],
  properties: {
    exit_code: { type: 'number' },
    run_dir: { type: 'string' },
    results_path: { type: 'string' },
    failed_list_path: { type: 'string' },
    report_path: { type: 'string' },
    targets: { type: 'number' },
    clean: { type: 'number' },
    failed: { type: 'number' },
    failed_targets: { type: 'array', items: { type: 'string' } },
    warnings: { type: 'array', items: { type: 'string' } },
    // batch_results.mjs prints {exit_code: 2, error} when --run-dir is missing, and nothing else.
    error: { type: 'string' },
  },
}

// -- One agent = one command -----------------------------------------------------
// `model` is passed explicitly because Agent's model option takes precedence over an agentType's
// own frontmatter default; omitting it would pin every runner to script-runner.md's haiku and make
// script_model:'inherit' a silent no-op. forceSessionModel opts a call OUT of SCRIPT_MODEL, for
// relays of unbounded nested data where a small model has been observed to blank a field with no
// parse error - valid JSON, wrong data.
// The preferred runner ships with this plugin, but a plugin's agents are registered from the
// INSTALLED CACHE at session start -- not from a dev checkout, and not mid-session. So a freshly
// added agents/script-runner.md is absent until the plugin is republished and a new session
// starts, and agent() throws outright on an unknown agentType. That killed a run on its first
// call with "agent type 'skills-v8:script-runner' not found".
//
// Hard-failing a 900-target campaign because a helper agent is not registered yet is the wrong
// trade, so the first such failure downgrades to general-purpose (always present) for the rest of
// the run and says so once. Behaviour is identical; general-purpose simply carries a broader
// toolset and a larger prompt than the minimal runner.
let SCRIPT_AGENT = _args.script_agent || 'skills-v8:script-runner'
let agentFellBack = false

function isMissingAgentType(e) {
  return /agent type .* not found/i.test(String(e?.message ?? e))
}

function runScript(command, opts) {
  return runScriptWith(SCRIPT_AGENT, command, opts).catch((e) => {
    if (!isMissingAgentType(e) || SCRIPT_AGENT === 'general-purpose') throw e
    log(`NOTE: agent type '${SCRIPT_AGENT}' is not registered in this session (a plugin's agents come from the installed cache, not a dev checkout). Falling back to general-purpose for the rest of this run.`)
    SCRIPT_AGENT = 'general-purpose'
    agentFellBack = true
    return runScriptWith(SCRIPT_AGENT, command, opts)
  })
}

function runScriptWith(agentType, command, { label, phase, schema, extra, forceSessionModel = false }) {
  return agent(`
Run one command and report its output. Nothing else.

${RESOLVE_SKILL}

## The command (run from the workspace root - the directory holding environment_web.config)

\`\`\`
${command}
\`\`\`

## Rules

1. Substitute the literal \`SKILL_DIR\` with the directory you resolved above, keeping the double
   quotes that already surround it in the command. That one substitution is REQUIRED - the command
   cannot run with the placeholder still in it. Change nothing else: no altered argument, no added
   flag, no other path rewritten. If any path other than SKILL_DIR looks wrong, report that; do not
   correct it.
2. It prints ONE JSON object on stdout. Return that object's fields as your structured result,
   verbatim. If a field's schema type allows "null", report a JSON null literal for it. Report
   every field the JSON contains, including ones not named in the schema.
3. Report the process EXIT CODE in exit_code. The exit code is load-bearing - the orchestrator
   branches on it. Never report 0 for a command that failed. If the task text below defines
   exit_code differently (a multi-step task does), follow the task text: it is more specific.
4. On a non-zero exit, do NOT retry, do NOT try a different invocation, and do NOT attempt to fix
   the underlying problem. Report what happened and stop. The orchestrator decides what follows.
5. Do not run any other command, query the database directly, or edit any file, unless the task
   text below explicitly asks for additional steps and names each one.
${extra ? `\n${extra}\n` : ''}`,
    { label, phase, schema, agentType, model: forceSessionModel ? undefined : SCRIPT_MODEL })
}

// -- Phase: Preflight ------------------------------------------------------------

phase('Preflight')

const RUN_LABEL = !CONFIRMED
  ? 'PLAN ONLY (no writes until confirmed:true)'
  : DRY_RUN ? 'CONFIRMED + DRY RUN (plan and merge dry-run only; no target agent is spawned)' : 'CONFIRMED (will write)'
log(`spec-batch -- ${RUN_LABEL}${RESUME ? ` | resuming from ${RESUME}` : ''}${ONLY ? ` | NARROWED to: ${ONLY}` : ''}`)
if (ONLY) log('  NOTE: --only narrows this plan. It is NOT the full tree -- do not read the counts below as full-tree coverage.')

// Reported here rather than at parse time so it lands inside a phase and is visible in the log.
if (badArgs.length) {
  for (const b of badArgs) log(`ABORT: ${b}`)
  log('Nothing was planned and nothing was written. Re-invoke with a valid value.')
  return { aborted: true, reason: 'unreadable numeric argument', bad_args: badArgs }
}

let pagesPath = PAGES
if (!pagesPath) {
  // The page inventory is what separates a real target from a directory that merely contains
  // .view.cs files. Captured here rather than required as an argument so a first run works without
  // the caller having to know the query.
  const inv = await runScript(
    `node "SKILL_DIR/scripts/plan_specs.mjs" --print-sql`,
    {
      label: 'page-inventory', phase: 'Preflight', schema: INVENTORY_SCHEMA,
      extra: `This command PRINTS a SQL query; it does not run it. Do all of the following:

1. Run the command to get the query text. Report ITS exit code in \`command_exit_code\`.
2. Run \`SELECT DB_NAME() AS db\` through the mssql MCP (find it with ToolSearch, query
   "select:mcp__plugin_skills-v8_mssql__execute_query") and report the answer in \`db\`.
3. Execute the printed query through that same tool with \`save_to\` set to an ABSOLUTE path ending
   \`.tmp/spec-batch-pages.json\`. WHICH \`.tmp/\` IS THE MCP'S DECISION, NOT YOURS. It confines
   every save_to to \`<its own repo root>/.tmp/\`, and it resolves that root as the nearest
   directory holding a \`.sln\` or \`buyer.slnx\`, walking up from CLAUDE_PROJECT_DIR, then from its
   own executable, then from its cwd. That is frequently NOT the workspace being specced -- the
   file often lands in the plugins repo instead, which is fine, because step 4 relays wherever it
   actually went. If the write is refused, the error names the scratch directory it will accept:
   retry ONCE with the same filename inside that directory. Do not invent another location, and do
   not fall back to a session scratchpad or a system temp directory -- neither can be found again
   by a later invocation.
4. Report in \`saved_to\` the path the MCP RETURNED in its own \`saved_to\` field, copied exactly.
   Never report the path you asked for: the two can differ, and every later step reads this file.
   Then read that file and count the page_url values in it, reporting the count in \`entries\`.

The query aggregates to ONE row on purpose: the MCP truncates a result set at 1000 rows and there
are far more pages than that. If you rewrite it into one-row-per-page the inventory is truncated,
and a truncated inventory silently drops every page past the cut from the whole campaign. Run it
exactly as printed.

THIS STEP OVERRIDES RULE 3 ABOVE, because it is four actions rather than one command: \`exit_code\`
reports the WHOLE step - 0 only if every numbered step above succeeded, non-zero otherwise - and the
command's own code goes in \`command_exit_code\`. Step 1 exits 0 merely by printing the query, so
reporting that as \`exit_code\` would announce success for a run whose database step failed. If any
step failed, report a non-zero \`exit_code\` with the failure text in \`error\`, and OMIT \`saved_to\`
and \`entries\` rather than filling them in with a path or a count you did not obtain.`,
    })

  if (!inv || inv.exit_code !== 0 || !inv.saved_to) {
    log(`ABORT: could not capture the page inventory${inv?.error ? `: ${inv.error}` : ''}`)
    return { aborted: true, reason: 'no page inventory -- the plan would carry non-page targets', inventory: inv ?? null }
  }
  log(`Page inventory: ${inv.entries} page URLs from ${inv.db || 'the configured database'} -> ${inv.saved_to}`)
  // This path is the ONE command-line value in the pipeline that no human typed: it is whatever
  // the MCP chose, relayed back through an agent. So it gets the same refusal the typed arguments
  // get, and it gets it HERE rather than at parse time, where it did not exist yet. A relay that
  // came back with a quote or a `$` in the path would otherwise be spliced straight into the Plan
  // command below.
  pagesPath = shellArg('page inventory path (relayed from the MCP)', inv.saved_to, PATH_GRAMMAR, 'a filesystem path')
  if (pagesPath === null) {
    for (const b of badArgs) log(`ABORT: ${b}`)
    return { aborted: true, reason: 'the relayed page-inventory path cannot be passed to a command safely', inventory: inv }
  }
}

// -- Phase: Plan -----------------------------------------------------------------

phase('Plan')

// Every string-valued flag is QUOTED. --run-id and --only were not, and --only is the one argument
// a human is invited to paste a list into (`_failed.txt` is documented as paste-ready). Unquoted,
// `--only ord/basket_browse, sup/supplier_browse` reaches the planner as two argv entries, the
// second of which does not start with `--`, so it is consumed as a positional and discarded: the
// filter became `ord/basket_browse,` and the second target vanished without a word in the log.
// --pages and --resume were already quoted; these two now match.
const plan = await runScript(
  `node "SKILL_DIR/scripts/plan_specs.mjs" --workspace . --pages "${pagesPath}"`
  + `${RUN_ID ? ` --run-id "${RUN_ID}"` : ''}${RESUME ? ` --resume "${RESUME}"` : ''}`
  + `${WAVE_SIZE ? ` --wave-size ${WAVE_SIZE}` : ''}${AGENT_BUDGET ? ` --agent-budget ${AGENT_BUDGET}` : ''}`
  + `${PASS ? ` --pass "${PASS}"` : ''}${MODE ? ` --mode "${MODE}"` : ''}`
  + `${ONLY ? ` --only "${ONLY}"` : ''}${INCLUDE_CURRENT ? ' --include-current' : ''}`
  // Tells the planner this is a dry run so it suffixes the DEFAULT run id with `-dry`. That is what
  // keeps a dry run's run directory -- and therefore its results.json -- out of the real run's, so
  // a later --resume cannot read a dry run's records as finished work.
  + `${DRY_RUN ? ' --dry-run' : ''}`,
  {
    label: 'plan-specs', phase: 'Plan', schema: PLAN_SCHEMA,
    // first_chunk_waves is unbounded nested data and its grouping IS the concurrency bound, so
    // this relay never runs on a small model: a silently dropped wave member is a target that
    // never runs, and it produces valid JSON that nothing downstream complains about.
    forceSessionModel: true,
    extra: `Exit code 3 means there is nothing to do - a normal outcome (every spec current), not an
error to work around. Exit code 2 with an "inventory is incomplete" message means the page
inventory was truncated; report it and stop, do not retry with a different query.
Report first_chunk_waves EXACTLY as printed, preserving the grouping.`,
  })

if (!plan) return { aborted: true, reason: 'plan agent returned no result' }

if (plan.exit_code === 2) {
  log(`ABORT: ${plan.error || 'the planner rejected its inputs'}`)
  return { aborted: true, reason: 'planner rejected its inputs', plan }
}

const counts = plan.counts || {}
log(`Plan [${plan.mode} | ${(plan.layers || []).join(' + ')}]: ${counts.total ?? 0} target(s) -- ${counts.generate ?? 0} generate, ${counts.update ?? 0} update, ${counts.objects ?? 0} object spec(s). ${counts.current_skipped ?? 0} already current.`)
if (counts.resume_skipped) log(`  resume: ${counts.resume_skipped} target(s) already finished by a previous run`)
if (counts.excluded_by_pass) log(`  pass filter: ${counts.excluded_by_pass} target(s) excluded by --pass ${plan.pass ?? PASS ?? 'both'}`)
log(`  ${plan.chunks ?? 1} chunk(s), est ${plan.est_agents ?? 0} agents; this chunk ${plan.first_chunk_targets ?? 0} target(s) / ~${plan.first_chunk_est_agents ?? 0} agents.`)
if (plan.over_budget) log('  WARNING: one wave exceeds the agent budget on its own. It runs whole -- a wave is the checkpoint unit and splitting it would leave a half-run wave that cannot be resumed cleanly.')
for (const e of (plan.escalations || [])) log(`  ESCALATION: ${e}`)
for (const c of (plan.coverage_boundary || [])) log(`  COVERAGE: ${c}`)
for (const w of (plan.warnings || [])) log(`  PLAN WARNING: ${w}`)

// "Nothing to do" has several causes and exit 3 does not distinguish them, so the reason comes from
// the planner rather than from a sentence here. This line used to assert "every page spec in scope
// is current", which is only one of the possibilities -- an empty enumeration reads identically and
// means the opposite.
if (plan.exit_code === 3 || !(counts.total ?? 0)) {
  log(`Nothing to do -- ${plan.nothing_to_do_reason || 'the planner queued no target and gave no reason.'}`)
  return { stopped: true, reason: plan.nothing_to_do_reason || 'nothing to do', plan }
}

const waves = plan.first_chunk_waves || []
// Also agent-relayed, and it reaches TWO command lines (merge, report) plus every target prompt.
// The planner confines it to the workspace and validates the run id it is built from, but that
// guarantee is enforced in another process and arrives here through a relay, so it is re-checked
// rather than trusted -- the same reason DRY_RUN_ISOLATED below re-checks the `-dry` suffix
// instead of assuming the planner applied it.
const RUN_DIR = shellArg('run_dir (relayed from the planner)', plan.run_dir, PATH_GRAMMAR, 'a filesystem path')
if (RUN_DIR === null) {
  for (const b of badArgs) log(`ABORT: ${b}`)
  return { aborted: true, reason: 'the relayed run directory cannot be passed to a command safely', plan }
}

// Keeping a dry run's records out of a real run's directory has two halves: this script suffixes an
// explicitly passed run_id with `-dry`, and plan_specs.mjs suffixes the DEFAULT one. The second half
// lives in another file, so it is CHECKED here rather than assumed -- an unmarked run id means the
// dry run is sharing a directory with a real run, and the Report phase (the only thing a dry run
// still runs that writes anything) must not overwrite that run's record.
const DRY_RUN_ISOLATED = /-dry$/.test(String(plan.run_id ?? ''))
if (DRY_RUN && !DRY_RUN_ISOLATED) {
  log(`  DRY RUN WARNING: the planner returned run_id '${plan.run_id}', which carries no '-dry' marker, so this dry run shares ${RUN_DIR} with a real run of the same id. The Report phase is SKIPPED below rather than allowed to overwrite that run's record.`)
}
if (DRY_RUN && plan.dry_run === false) {
  log('  DRY RUN WARNING: the planner reports dry_run false while this invocation is a dry run. The --dry-run flag did not reach it; treat the run directory as shared.')
}

// The confirmation gate. `--full` rewrites hundreds of files and a workflow cannot prompt, so the
// first invocation always stops here with the plan in hand. The skill presents these counts and
// re-invokes with confirmed:true. Making this the DEFAULT rather than an opt-out means a
// mis-typed invocation costs a plan, not 600 rewritten specs.
//
// The condition is CONFIRMED AND NOTHING ELSE. It used to read `!CONFIRMED && !DRY_RUN`, which made
// dry_run:true a way THROUGH the gate: the run walked into the Write phase and spawned one agent per
// target, and the only thing standing between that and a real rewrite was a sentence in the target
// prompt asking it not to invoke the skill. Prose is not a gate. `dry_run` now narrows what the
// Write phase DOES (see below) and has no say in whether it is reached.
if (!CONFIRMED) {
  log('')
  log(`STOPPING BEFORE ANY WRITE. ${counts.total} target(s) would be rewritten across ${plan.chunks} chunk(s).`)
  // The id to re-invoke with is the REAL one, not this plan's. On a dry run plan.run_id already
  // carries `-dry`, and echoing it back is how a real campaign ends up writing into a dry-named
  // directory that a later default-id run will not resume -- one campaign split across two run
  // dirs. Nothing is lost (the dry run wrote nothing there), but the resume chain silently breaks.
  const nextRunId = DRY_RUN ? String(plan.run_id || '').replace(/-dry$/, '') : plan.run_id
  log(`Re-invoke with confirmed: true (and run_id: '${nextRunId}') to start writing.`)
  if (DRY_RUN) log('  dry_run does NOT stand in for confirmed. Pass both to run the dry run itself.')
  return {
    plan_only: true, awaiting_confirmation: true, dry_run: DRY_RUN,
    run_id: plan.run_id, next_run_id: nextRunId, run_dir: RUN_DIR, plan_path: plan.plan_path,
    // mode/layers decide WHICH TREE gets rewritten, and the planner's detector is a strict subset
    // of the canonical session detector (path only, no SVN-branch-URL fallback). So they are part
    // of what the human confirms, not just a log line. batch-full.md tells the reader to check
    // them "in the plan-only result" -- until now they were not in it, so that contract was
    // unsatisfiable from the object the reviewer actually sees.
    mode: plan.mode, layers: plan.layers || [],
    counts, chunks: plan.chunks, est_agents: plan.est_agents,
    escalations: plan.escalations || [], coverage_boundary: plan.coverage_boundary || [],
  }
}

// -- Phase: Write ----------------------------------------------------------------

phase('Write')

// A child that throws must degrade to a recorded failure, never abort the fleet - one bad target
// out of 600 is a line in the report, not a lost campaign. parallel() already resolves a throwing
// thunk to null, and that null is recorded as 'unknown' rather than filtered out: a target missing
// from the results is indistinguishable from one that was never scheduled.
const results = []

function runTarget(t) {
  // Replace EVERY separator, not the first. String.replace with a string pattern replaces ONE
  // occurrence, so a three-segment project target (`project/ord/basket_browse`) became
  // `project__ord/basket_browse` -- still holding a slash, which turned the journal and result
  // paths into nested directories. batch_results.mjs scans `results/*.json` non-recursively, so
  // that target's outcome would be silently missed and it would be recorded as never reported.
  const journalName = t.target.split('/').join('__')
  // The module is the SECOND-TO-LAST segment, correct for both `ord/basket_browse` and
  // `project/ord/basket_browse`. Taking [0] yielded the literal string `project` for the latter.
  const seg = t.target.split('/')
  const moduleCode = seg.length > 1 ? seg[seg.length - 2] : seg[0]
  // Everything below that differs between the two kinds is derived HERE rather than left to the
  // reader of a page-worded prompt. An object target used to receive the page wording verbatim:
  // "ONE Buyer V8 page spec", a scope boundary listing only `<module>/<page>.spec.md`, and a
  // journal template hardcoding `"table": "Pages"`. The last one is not cosmetic -- merge_deferred
  // defaults an index row to the Pages table, and a module index carries a separate
  // `## Object Types` table, so every object spec this batch produced would have been filed as a
  // page in the module index.
  const isObject = t.kind === 'object'
  const noun = isObject ? 'object-type spec' : 'page spec'
  const indexTable = isObject ? 'Object Types' : 'Pages'
  const ownFiles = isObject
    ? `\`${moduleCode}/<otype>.spec.md\` for THIS object type (the exact path is given above)`
    : `\`${moduleCode}/<page>.spec.md\` and \`.tech.md\` for THIS page`
  return agent(`
Generate or refresh ONE Buyer V8 ${noun} by invoking the spec-write skill, then record what you did.

## Your target

- Target scope: \`${t.target}\`
- Layer: ${t.layer}
- Kind: ${t.kind === 'object' ? 'OBJECT TYPE' : 'PAGE'}${t.spec ? `
- Write the spec at EXACTLY this path: \`${t.spec}\`${t.kind === 'object' ? `
  Do not re-derive this filename. An object spec's name is not derivable from its otype code -
  this tree contains both conventions (otype \`ord_item\` is \`ord_item.spec.md\`, otype
  \`iva_chat\` is \`chat.spec.md\`) - so two writers left to choose will choose differently, and
  the planner then cannot tell the spec was written. That already happened once: a run wrote
  \`usecase.spec.md\` for otype \`iva_usecase\` and the next plan re-queued it.` : ''}` : ''}
- Planned action: ${t.action}   (generate = no spec exists yet; update = source is newer than the spec)

## Step 1 -- invoke the skill

Invoke \`/skills-v8:spec-write ${t.target} ${t.kind === 'object' ? '--object-only' : '--page-only'} --no-review\` and follow it to completion.

Neither flag is optional.

\`--no-review\` does NOT mean this spec goes unreviewed. The review gate runs as its own phase after
every target in this wave has finished, spawned by the workflow script instead of by you. Do not
try to review the spec yourself, and do not treat spec-lint as a substitute for the gate - just
write the spec and report. Reviewing from in here is what the flag exists to prevent: measured, a
reviewer spawned at this depth DEADLOCKS - it hangs until a 600-second watchdog kills it, and takes
this whole target down with it, losing the spec you already wrote. The extraction agents (A/B/C)
are fine to spawn at this depth and you should; it is specifically the reviewer that must not be.

\`--page-only\` does two things, and both are load-bearing.

It keeps you off the OBJECT spec. An object spec is shared by every page bound to the same object
type - \`supplier\` has 102 of them - so if targets wrote object specs concurrently, one page's
write would silently overwrite another's. Object specs are handled separately, after the pages.

It also ASSERTS the page pipeline. spec-write's own Phase 0 probe decides page-vs-object by looking
for a \`.view.cs\`, and a VIRTUAL page (\`page_virtual = 1\`) has no source file at all, so left to
the probe it classifies as an object type and takes the object pipeline. The plan does not have
that problem: it resolved this scope's kind from \`t_bas_page\`, which is the authority. So the
\`Kind:\` line above is authoritative. If Phase 0 disagrees with it, trust the plan, record the
disagreement in your result's \`error\` field, and continue down the pipeline the plan chose.

Do not read any of that symmetrically for \`--object-only\`. That flag is documented as "on a page
input, skip the page spec" - it applies perfectly well to a page scope and asserts nothing about
the scope being an object type. An object target needs no assertion anyway: an otype scope has no
page source file for the probe to be misled by.

## Step 2 -- scope boundary (this is what makes the fleet safe)

You may write ONLY files owned by this target:

- ${ownFiles}
- your journal and result files, named below

You must NOT write, even if spec-write's own steps ask for it:

| Destination | Why it is off limits here | Journal it as |
|---|---|---|
| any \`index.md\` (module or layer) | shared; the layer index is shared by every target in the run | \`index-row\` |
| \`<module>/overview.md\` | shared across the module | \`overview-patch\` |
| \`<module>-utilities.tech.md\` | shared across the module | \`utility-contract\` |
| \`buyer/platform/specs/<capability>.spec.md\` | shared GLOBALLY, by every target in the run | \`platform-spec\` |
| another page's \`.notes.md\` | belongs to a different target, which may already have finished | \`notes\` |

Every row has a journal kind, so "forbidden" never means "dropped": if you would have written it,
there is an entry kind that carries it to the merge phase instead.

Hundreds of these run concurrently. A concurrent write to a shared file does not conflict or
error - one writer simply wins and the other's content is gone. So instead of writing them, record
each one as a journal entry in Step 3 and the merge phase applies them all once, single-threaded.

## Step 3 -- journal the shared-file writes you skipped

Write \`${RUN_DIR}/deferred/${journalName}.json\`:

\`\`\`json
{
  "target": "${t.target}",
  "entries": [
    { "kind": "index-row", "file": "<layer>/specs/<module>/index.md", "table": "${indexTable}",
      "label": "<label>", "link": "<this target's spec filename>", "summary": "<frontmatter summary>" },
    { "kind": "overview-patch", "file": "<layer>/specs/<module>/overview.md",
      "section": "## <section this page belongs under>", "link": "<page>.spec.md",
      "body": "<the markdown mentioning this page, one bullet or short paragraph>" },
    { "kind": "utility-contract", "file": "<layer>/specs/<module>/<module>-utilities.tech.md",
      "heading": "<Class>.<Method>", "body": "<the full markdown contract block>" },
    { "kind": "platform-spec", "file": "buyer/platform/specs/<capability>.spec.md",
      "heading": "### <Behaviour>", "body": "<the markdown to append>" },
    { "kind": "notes", "file": "<layer>/specs/<module>/<other-page>.notes.md",
      "section": "## <observation type> from ${t.target}", "body": "<the observation>" }
  ]
}
\`\`\`

Include only the kinds that actually apply - an empty \`entries\` array is a perfectly normal
result, and most update runs produce one. Write the file even when \`entries\` is empty.

Four details the applier enforces rather than forgives:

- \`table\` on an index-row is \`${indexTable}\` for THIS target, and it is prefilled above. A module
  index carries a \`## Pages\` table and a \`## Object Types\` table; the applier defaults to
  \`Pages\` when the field is absent, so an object spec filed without it lands under Pages and is
  wrong in the one document readers use to find it.
- Every \`file\` is WORKSPACE-RELATIVE (\`buyer/specs/ord/index.md\`). An absolute path, or one that
  escapes the workspace with \`..\`, is refused and its entry is dropped - the flush creates
  directories recursively, so it will not take a path it cannot vouch for.
- Heading form differs by kind, and it is not cosmetic. \`utility-contract\` takes a BARE symbol
  name (\`Ord.DoThing\`), because the applier renders the \`###\` and the backticks itself.
  \`platform-spec\` and \`notes\` take their marker (\`###\`, \`##\`) INSIDE the value, copied through
  as written.
- \`overview-patch\` is the ONLY way this run can contribute to \`<module>/overview.md\`, which
  Step 2 forbids you to write. \`link\` is its identity, so re-merging is a no-op; \`section\` is
  optional and decides which \`##\` heading the body lands under.

If two targets in one wave supply the same \`utility-contract\` heading, the merge phase reports it
as a lost contribution rather than resolving it - so make the heading the real symbol name, not a
paraphrase, or the collision cannot even be detected.

## Step 4 -- record your outcome

Write \`${RUN_DIR}/results/${journalName}.json\` with the same fields you return (below), then
return them as your structured result. Both, not one: the file is what survives an interrupted
campaign and drives \`--resume\`; the return value is what the log shows now.

Read the fields off spec-write's own closing summary block rather than inferring them:

- \`target\`: \`${t.target}\`, exactly as given to you.
- \`action\`: \`${t.action}\` -- copy this literal, do not re-derive it. The run report's
  "Unreviewed greenfield specs" check keys on it, and with the field absent that check silently
  renders nothing: the safety net for an unreviewed batch fails exactly like the thing it detects.
- \`outcome\`: "written" if it wrote any spec content; "skipped-current" if it reported the spec
  already current (that is a normal outcome, not a failure); "failed" if it errored or refused.
- \`files\`: the paths from its "Files written" lines.
- \`review\`: its Review line verbatim.
- \`deferred\`: how many entries you put in the journal.

If spec-write cannot run at all, report outcome "failed" with the error text. Do not retry it more
than once, and do not hand-write a spec yourself as a substitute - a hand-written spec that skipped
the skill's fabrication checks is worse than a recorded failure.

## If you hit a retry, a surprise, or a workaround

Invoke \`/learn\` before continuing. You own your own discoveries; do not save them for the end or
defer them to the parent.
`, { label: `spec:${t.target}`, phase: 'Write', schema: TARGET_SCHEMA, agentType: 'general-purpose' })
    .then((r) => {
      const rec = { target: t.target, action: t.action, outcome: r?.outcome ?? 'unknown', files: r?.files ?? [], deferred: r?.deferred ?? 0, review: r?.review ?? null, error: r?.error ?? null }
      results.push(rec)
      log(`  ${t.target} -> ${rec.outcome.toUpperCase()}${rec.deferred ? ` (+${rec.deferred} deferred)` : ''}${rec.error ? `: ${String(rec.error).slice(0, 120)}` : ''}`)
      return rec
    })
    .catch((e) => {
      const rec = { target: t.target, action: t.action, outcome: 'failed', error: String(e?.message ?? e) }
      results.push(rec)
      log(`  ${t.target} -> FAILED: ${rec.error}`)
      return rec
    })
}

// The planner's effective wave size, not a re-guessed default: a malformed wave_size aborts in
// Preflight now, and the planner reports the value it actually used, so this line can no longer
// read "waves of up to NaN".
// Re-checked like every other relayed value: `??` does not catch a 0, and the Review loop below
// advances by this number, so a relay that blanked wave_size to 0 would spin forever after the
// specs were written and before merge and report ran -- losing the chunk's record.
const relayedWaveSize = Number.isInteger(plan.wave_size) && plan.wave_size >= 1 ? plan.wave_size : null
if (WAVE_SIZE === null && plan.wave_size !== undefined && relayedWaveSize === null) log(`  NOTE: the plan relay returned wave_size '${plan.wave_size}', which is not a positive integer; using 6.`)
const EFFECTIVE_WAVE_SIZE = WAVE_SIZE ?? relayedWaveSize ?? 6

// The grouping and the count are relayed SEPARATELY by the same agent, and only the count is
// logged. `forceSessionModel` on the Plan relay makes a dropped wave member unlikely; it does not
// make it detectable, and a dropped member is a target that never runs while the log reports the
// planner's number. The script holds both values, so the check is free. Refuse rather than run a
// short chunk: a silent under-run is indistinguishable from a completed one on resume.
// A relay that omitted the scalar altogether (null/undefined) is "not relayed", not "zero": treating
// it as 0 aborted with a diagnosis blaming a dropped wave member when no member was dropped.
const declaredTargets = plan.first_chunk_targets ?? null
const relayedTargets = waves.reduce((n, w) => n + (Array.isArray(w) ? w.length : 0), 0)
if (declaredTargets === null) log(`  NOTE: the plan relay omitted first_chunk_targets; running the ${relayedTargets} relayed target(s) unchecked.`)
if (declaredTargets !== null && declaredTargets !== relayedTargets) {
  log(`ABORT: the plan relay is internally inconsistent -- first_chunk_targets says ${declaredTargets} but first_chunk_waves carries ${relayedTargets}. A wave member was dropped or duplicated in transit; running would silently skip targets and mark the chunk done.`)
  return { aborted: true, reason: 'plan relay dropped or duplicated a wave member', declared_targets: declaredTargets, relayed_targets: relayedTargets, plan }
}

if (DRY_RUN) {
  // A dry run spawns NO target agent. Not "spawns one and asks it not to write" - that was the old
  // shape, and the request not to invoke spec-write trailed the imperative to invoke it inside a
  // single sentence, so one prompt-following miss was a real rewrite. Not spawning is the only
  // version of this that cannot be talked out of.
  //
  // Each target is recorded as `dry-run`, an outcome deliberately absent from DONE_OUTCOMES in
  // plan_specs.mjs and from DONE in batch_results.mjs, so it can never mark a target finished for a
  // later --resume. The `-dry` run directory already keeps these records out of a real run's reach;
  // both hold, because either alone is a single point of failure. Nothing is written to
  // <run-dir>/deferred or <run-dir>/results either - the writer of those files is the target agent,
  // and there is no target agent.
  log(`DRY RUN: ${plan.first_chunk_targets ?? 0} target(s) would be written in ${waves.length} wave(s) of up to ${EFFECTIVE_WAVE_SIZE}. No target agent is spawned; no spec, journal or result file is touched.`)
  for (const [i, wave] of waves.entries()) {
    if (!wave.length) continue
    log(`Wave ${i + 1}/${waves.length}: ${wave.map((t) => `${t.target} [${t.kind}/${t.action}]`).join(', ')}`)
    for (const t of wave) results.push({ target: t.target, action: t.action, outcome: 'dry-run', files: [], deferred: 0, review: null, error: null })
  }
} else {
  log(`Writing ${plan.first_chunk_targets} target(s) in ${waves.length} wave(s) of up to ${EFFECTIVE_WAVE_SIZE}.`)

  for (const [i, wave] of waves.entries()) {
    if (!wave.length) continue
    log(`Wave ${i + 1}/${waves.length}: ${wave.map((t) => t.target).join(', ')}`)
    // The wave boundary here is a CONCURRENCY THROTTLE, not a write-safety barrier - page targets
    // run --page-only, object targets --object-only, and the planner queues at most one target per
    // spec file, so no two can collide. It exists because each of these agents spawns spec-write's
    // own agents underneath, so a wave of 6 is roughly 24 real agents against one database.
    const settled = await parallel(wave.map((t) => () => runTarget(t)))
    for (const [j, r] of settled.entries()) {
      if (r === null) {
        results.push({ target: wave[j].target, action: wave[j].action, outcome: 'unknown', error: 'the target agent returned no result' })
        log(`  ${wave[j].target} -> UNKNOWN (no result returned)`)
      }
    }
  }
}

// -- Phase: Review ---------------------------------------------------------------
// The gate runs HERE, at depth 1, and not inside the target - that placement is the whole point.
//
// Targets are spawned `agentType: 'general-purpose'`, so they CAN spawn subagents, and their A/B/C
// extraction fan-out works fine at that depth. The reviewer does not: measured on a real greenfield
// target, two reviewers spawned from inside a target both hung and were killed by the 600s stream
// watchdog, taking the parent target down with them AFTER it had already written its spec. The same
// review work, run one level shallower, completed in ~16 minutes. So the target writes with
// `--no-review` and the script reviews afterwards.
//
// Only `generate` targets are reviewed. spec-write auto-runs the gate on greenfield and makes it
// opt-in on the update path (SKILL.md Phase 3 Step 1), so reviewing updates here would apply a
// stricter rule than the skill's own and pay for it on every chunk.
//
// Cost, measured on one page: generate without review was ~318k tokens / 21.6 min; the review added
// ~183k / 16.2 min. It is the expensive phase, and it earns it on the TECH spec - the findings that
// mattered were factual claims only a DB query could falsify, while the functional spec came back
// materially clean. Budget accordingly; do not assume review is a rubber stamp.

phase('Review')

const reviewable = results.filter((r) => r.action === 'generate' && r.outcome === 'written' && (r.files || []).length)

if (DRY_RUN) {
  log(`Review SKIPPED -- dry run spawned no target, so there is nothing written to review.`)
} else if (!reviewable.length) {
  log('Review: no greenfield target wrote a spec in this chunk -- nothing to review.')
} else {
  log(`Reviewing ${reviewable.length} greenfield spec(s) in wave(s) of up to ${EFFECTIVE_WAVE_SIZE}.`)
  for (let i = 0; i < reviewable.length; i += EFFECTIVE_WAVE_SIZE) {
    const batch = reviewable.slice(i, i + EFFECTIVE_WAVE_SIZE)
    await parallel(batch.map((rec) => () =>
      agent(`Review the Buyer V8 spec files just generated for \`${rec.target}\` and fix what you find.

## Artifacts

${(rec.files || []).map((f) => `- \`${f}\``).join('\n')}

They were generated greenfield by /skills-v8:spec-write and have NOT been reviewed.

## What to do

Invoke \`/skills-v8:review\` on them (type: \`spec\`), then APPLY the corrections for findings you
can evidence. Iterate at most 3 passes; stop earlier once there is no ISSUE and no GAP left.

Two hard constraints, both learned from a failure:
- Do NOT spawn a further nested subagent to do the reviewing. Do the review work yourself in this
  context. Nested reviewers deadlock and get killed by a watchdog.
- Do NOT use Bash to write files. A denied Bash write hangs a background agent on a prompt nobody
  can answer. Use Write / Edit.

Ground every finding in source - the page's \`.view.cs\` / \`.ascx.cs\` / \`*Methods.cs\`, and the DB
config via the mssql MCP. Cite \`file:line\` or the DB row. Findings that cannot be evidenced are
SUGGESTIONs at most; do not manufacture findings, and do not rewrite prose for taste. "Nothing
material" is a valid outcome and must be reported as such rather than padded.

## Step 2 -- record the verdict where the report can see it

Read \`${RUN_DIR}/results/${rec.target.split('/').join('__')}.json\`, set its \`review\` field to the
one-line verdict described below, and write the file back with every other field unchanged. Use
Write, not Bash.

This step is not bookkeeping. The target agent wrote that file before you existed, and it says
\`skipped\` because the target was told \`--no-review\`. The run report reads the field from THIS
file, not from what you return, so a verdict left only in your reply means the report still calls
this spec unreviewed.

## Scope boundary

Edit only the files listed above, the \`.review.md\` beside them, and the one result JSON named in
Step 2. Touch no index, no other spec, no shared file.

## Report

- \`review\`: one line starting \`PASSED\` when no ISSUE and no GAP remain (e.g. \`PASSED 2 passes\`),
  otherwise start it with the count that remains (e.g. \`2 ISSUE remaining\`). The report renderer
  keys off the \`PASSED\` prefix, so it has to lead the string.
- \`findings\`: how many of each of ISSUE / GAP / RISK / SUGGESTION were raised, and how many fixed.

## If you hit a retry, a surprise, or a workaround

Invoke \`/learn\` before continuing. You own your own discoveries.
`, { label: `review:${rec.target}`, phase: 'Review', schema: REVIEW_SCHEMA, agentType: 'general-purpose' })
        .then((rv) => {
          // Write the gate's verdict back onto the target's record. batch_results.mjs reads
          // `review` off each result file and flags any `generate` whose value does not start
          // PASSED, so this assignment is what makes the report's Unreviewed section truthful.
          rec.review = rv?.review ?? 'unknown -- reviewer returned no verdict'
          log(`  review ${rec.target} -> ${rec.review}`)
          return rv
        })
        .catch((e) => {
          // A reviewer that dies must not lose the SPEC. The target already wrote it and journalled
          // its shared entries; only the verdict is missing. Record that and carry on - the report
          // lists it as unreviewed, which is exactly what it is.
          rec.review = `failed -- ${String(e?.message ?? e).slice(0, 160)}`
          log(`  review ${rec.target} -> FAILED (spec is written but unreviewed): ${rec.review}`)
          return null
        })))
  }
}

// -- Phase: Merge ----------------------------------------------------------------
// Per chunk, not once at the end of the campaign. A whole-tree campaign is several
// invocations, so an end-of-campaign merge would leave every index wrong for every intermediate
// chunk and would lose every journalled entry if the campaign were abandoned. The applier is
// idempotent, so merging the same journal again after a resume is a no-op.

phase('Merge')

// runScript can THROW as well as resolve null - agent() rejects on a runner that dies, on a schema
// violation, and on an unknown agentType that is not the first such failure. An unhandled rejection
// here ends the whole script, which means the Report phase never runs and results.json is never
// written, so the next --resume re-runs a chunk whose targets all finished. A merge that failed is
// a line in the report; it is not a reason to lose the chunk's record.
const merge = await runScript(
  `node "SKILL_DIR/scripts/merge_deferred.mjs" --run-dir "${RUN_DIR}" --workspace .${DRY_RUN ? ' --dry-run' : ''}`,
  {
    label: 'merge-deferred', phase: 'Merge', schema: MERGE_SCHEMA,
    extra: `This applies the shared-file writes every target deferred. "skipped" entries are ones
already present - the expected result when re-merging after a resume, not a problem.

Relay \`warnings\` in full. It is not a softer \`errors\`: the merge SUCCEEDED and still lost
content, which is the one outcome nothing else in this pipeline records. Dropping a warning here
reports a lost write as a clean run.`,
  }).catch((e) => {
    log(`  MERGE WARNING: the merge runner failed (${String(e?.message ?? e)}) -- the journal is still on disk, so re-running this chunk will apply it.`)
    return null
  })

if (merge) {
  if (merge.exit_code !== 0) log(`  MERGE WARNING: merge_deferred.mjs exited ${merge.exit_code}${merge.error ? `: ${merge.error}` : ''} -- the journal is still on disk.`)
  if (merge.note) log(`  Merge: ${merge.note}`)
  else log(`Merge: ${merge.applied ?? 0} entr${(merge.applied ?? 0) === 1 ? 'y' : 'ies'} applied, ${merge.skipped ?? 0} already present, ${merge.files_written ?? 0} file(s) written${merge.files_unchanged ? `, ${merge.files_unchanged} unchanged` : ''} from ${merge.journals ?? 0} journal(s).`)
  for (const e of (merge.errors || [])) log(`  MERGE ERROR: ${e}`)
  // A warning here means the merge succeeded and still lost content -- a cross-target collision the
  // applier could detect but not resolve. Logged as LOST WRITE rather than as a warning so it does
  // not read as advisory, and carried into run-report.md below so it outlives this log.
  for (const w of (merge.warnings || [])) log(`  MERGE LOST WRITE: ${w}`)
} else {
  log('  MERGE WARNING: the merge agent returned no result -- the journal is still on disk, so re-running this chunk will apply it.')
}

// -- Phase: Report ---------------------------------------------------------------

phase('Report')

let report = null

if (DRY_RUN && !DRY_RUN_ISOLATED) {
  log('Report SKIPPED -- see the DRY RUN WARNING in the Plan phase. This dry run has no directory of its own, and the report is the only file it would write.')
} else {

if (DRY_RUN) log('DRY RUN: no target wrote a result file, so the aggregate below reads 0 targets. That is the expected shape of a dry run, not a failure -- what it exercises is the aggregator and the merge relay.')

// The merge outcome reaches the report through ARGUMENTS, not through a file. batch_results.mjs has
// always accepted `--merge <path>`, but nothing ever wrote that file: merge_deferred.mjs prints its
// result on stdout only, and this script has no filesystem access to persist it. So the report's
// Merge section was unreachable and every merge error lived only in a transient agent log - the one
// piece of this pipeline that most needs to be durable, because a shared-file write that did not
// land is invisible everywhere else.
//
// Values are flattened for the command line first: a newline would end the command and a double
// quote would end the argument. `$` and a backtick are neutralised too, because the runner may use
// either bash or PowerShell and each treats one of them as live syntax inside double quotes.
//
// A BACKSLASH is in that set as well, and it is the one that is easy to miss because the others
// look obviously dangerous. Inside bash double quotes `\` escapes the next character, so a value
// ending in one turns the closing quote into a literal and swallows the rest of the command line.
// That is not hypothetical here: merge errors carry ABSOLUTE Windows paths (merge_deferred.mjs
// reports `could not write ${slot.path}`), and the .slice(240) below can land exactly on a
// separator. Replaced rather than escaped -- these strings are log text going into a report, so
// legibility beats fidelity, and one uniform rule is easier to keep right than per-shell escaping.
const argSafe = (s) => String(s ?? '').replace(/[\r\n\t]+/g, ' ').replace(/["`$\\]/g, "'").trim().slice(0, 240)
const numOr0 = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0)
// Capped, because both lists are unbounded and this is a command line. The cap is REPORTED rather
// than silent: an omitted entry that nothing mentions is the failure this whole relay exists to
// stop. Warnings get the larger share -- an error is usually also visible in the phase log, whereas
// a lost cross-target write is recorded here and nowhere else.
const relay = (list, cap, flag, noun) => {
  const kept = list.slice(0, cap)
  const dropped = list.length - kept.length
  return kept.map((e) => ` ${flag} "${argSafe(e)}"`).join('')
    + (dropped > 0 ? ` ${flag} "${dropped} further ${noun} omitted from this relay -- see the Merge phase log"` : '')
}

// Same provenance and same destination as `inv.saved_to` and `plan.run_dir`, both of which are
// re-checked above -- this was the only relayed value reaching a command line unvalidated. The
// planner's honest value (join(runDir, "plan.json")) is safe, so the exposure is a relay
// transcription, not a planner defect. When there is no usable path -- the planner could not write
// plan.json (it reports plan_path "") or the relay mangled it -- the report gets `--no-plan`, which
// DISABLES batch_results.mjs's fallback to <run-dir>/plan.json: that file would be the PREVIOUS
// chunk's plan, and reconciling against it would re-queue finished work as `unreported`.
const PLAN_PATH = shellArg('plan_path (relayed from the planner)', plan.plan_path, PATH_GRAMMAR, 'a filesystem path')
if (plan.plan_path && PLAN_PATH === null) {
  log(`WARNING: the relayed plan_path could not be passed to a command safely; the report is NOT reconciled against the plan this chunk. ${badArgs[badArgs.length - 1] ?? ''}`)
}
if (!plan.plan_path) log('WARNING: the planner wrote no plan.json this chunk; the report is NOT reconciled against the plan (a crashed target agent would go uncounted).')

const mergeErrors = [...(merge?.error ? [String(merge.error)] : []), ...(merge?.errors || [])]
const mergeWarnings = merge?.warnings || []

const mergeArgs = merge
  // NOT numOr0: batch_results.mjs branches on the flag being ABSENT to print "The merge phase
  // reported no exit code. Treat the figures below as unconfirmed." Coercing null/undefined to 0
  // reports a clean merge that never confirmed itself, and makes that honest branch unreachable
  // from its only real producer.
  ? `${merge.exit_code == null ? '' : ` --merge-exit-code ${numOr0(merge.exit_code)}`}`
    + ` --merge-journals ${numOr0(merge.journals)}`
    + ` --merge-applied ${numOr0(merge.applied)}`
    + ` --merge-skipped ${numOr0(merge.skipped)}`
    + ` --merge-files-written ${numOr0(merge.files_written)}`
    + ` --merge-files-unchanged ${numOr0(merge.files_unchanged)}`
    + (merge.note ? ` --merge-note "${argSafe(merge.note)}"` : '')
    + relay(mergeErrors, 10, '--merge-error', 'merge error(s)')
    + relay(mergeWarnings, 20, '--merge-warning', 'lost cross-target contribution(s)')
  : ' --merge-exit-code -1 --merge-error "the merge phase returned no result at all; its journal is still on disk and re-running this chunk will apply it"'

report = await runScript(
  `node "SKILL_DIR/scripts/batch_results.mjs" --run-dir "${RUN_DIR}" --report`
  + `${PLAN_PATH ? ` --plan "${PLAN_PATH}"` : ' --no-plan'}`
  + mergeArgs,
  { label: 'batch-results', phase: 'Report', schema: REPORT_SCHEMA })
  // Same reason as the merge runner: a throw here would abort the script AFTER the chunk's work is
  // done, losing the summary the operator needs to decide whether to continue.
  .catch((e) => {
    log(`  REPORT WARNING: the report runner failed (${String(e?.message ?? e)}) -- per-target result files are still on disk under ${RUN_DIR}/results, so re-running this chunk regenerates the record.`)
    return null
  })

}

// A dry run finishes no target, so its `dry-run` records are not failures. Everything else that is
// neither written nor skipped-current is: this list is what the chunk loop and _failed.txt consume.
const failed = results.filter((r) => !TARGET_DONE.includes(r.outcome) && !(DRY_RUN && r.outcome === 'dry-run'))

if (report) {
  if (report.exit_code !== 0) log(`  REPORT WARNING: batch_results.mjs exited ${report.exit_code}${report.error ? `: ${report.error}` : ''}`)
  log(`Report: ${report.report_path || report.results_path || `(none written under ${RUN_DIR})`}`)
  if (report.targets !== undefined) log(`  ${report.clean ?? 0}/${report.targets} done, ${report.failed ?? 0} not done.`)
  for (const w of (report.warnings || [])) log(`  REPORT WARNING: ${w}`)
}

const deferred = plan.deferred_targets ?? 0

// A dry run finishes no target, so `remaining` cannot be its loop variable: the documented chunk
// loop is `while (r.remaining)`, and a dry run whose remaining never shrinks does not terminate. It
// therefore reports 0 remaining and carries the real figure in deferred_targets alongside
// dry_run:true, so the loop ends and the plan's size is still visible.
//
// `deferred_targets` is a PLAN-TIME constant (total minus this chunk), so it is identical on every
// invocation that makes no progress. --resume only skips DONE_OUTCOMES, and `failed` is
// deliberately re-queued, so a chunk where every target failed (the DB went down mid-wave) replans
// byte-identically: same total, same chunk, same `remaining`. The documented `while (r.remaining)`
// loop then reissues the same doomed chunk forever, ~40 agents an iteration, unattended.
// batch-full.md names only the missing-`resume` cause of non-termination; this one has the same
// shape. Partial failure still makes progress and still terminates -- this is the all-fail case.
const progressed = results.some((r) => TARGET_DONE.includes(r.outcome))
const stalled = !DRY_RUN && results.length > 0 && !progressed
const remaining = DRY_RUN || stalled ? 0 : deferred

if (stalled) {
  log(`STALLED: ${results.length} target(s) ran and none completed, so a resume would replan this identical chunk and loop forever. Reporting 0 remaining to break the loop -- ${deferred} target(s) are still unplanned.`)
  log(`Fix the underlying failure (see the per-target errors above), then resume with: confirmed: true, run_id: '${plan.run_id}', resume: '${RUN_DIR}'`)
}

if (DRY_RUN) {
  log(`spec-batch DRY RUN DONE -- ${results.length} target(s) enumerated, 0 written by design. ${deferred} further target(s) are in the plan beyond this chunk.`)
  log(`Nothing under ${RUN_DIR} is readable by a real run: the planner gave this run its own '-dry' run id.`)
  log(`To run it for real: confirmed: true WITHOUT dry_run.`)
} else {
  log(`spec-batch DONE -- ${results.length} target(s) this chunk, ${failed.length} not done.${remaining ? ` ${remaining} target(s) deferred to the next invocation.` : ''}`)
  if (remaining) {
    log(`Continue with: confirmed: true, run_id: '${plan.run_id}', resume: '${RUN_DIR}'`)
  }
}

return {
  run_id: plan.run_id,
  run_dir: RUN_DIR,
  mode: plan.mode,
  layers: plan.layers,
  counts,
  only: ONLY,
  dry_run: DRY_RUN,
  script_agent: SCRIPT_AGENT,
  ...(agentFellBack ? { script_agent_fellback: true } : {}),
  chunk_targets: results.length,
  written: results.filter((r) => r.outcome === 'written').length,
  skipped_current: results.filter((r) => r.outcome === 'skipped-current').length,
  ...(DRY_RUN ? { dry_run_targets: results.filter((r) => r.outcome === 'dry-run').length } : {}),
  failed: failed.map((r) => ({ target: r.target, outcome: r.outcome, error: r.error ?? null })),
  merge: merge
    ? {
      exit_code: merge.exit_code ?? null,
      applied: merge.applied ?? 0,
      skipped: merge.skipped ?? 0,
      files_written: merge.files_written ?? 0,
      files_unchanged: merge.files_unchanged ?? 0,
      note: merge.note ?? null,
      errors: merge.errors ?? [],
      // Surfaced in the RESULT, not only the log: a caller driving the chunk loop has to be able to
      // see that a chunk lost a cross-target contribution without re-reading the phase output.
      warnings: merge.warnings ?? [],
    }
    : null,
  report_path: report?.report_path ?? null,
  failed_list_path: report?.failed_list_path ?? null,
  escalations: plan.escalations || [],
  coverage_boundary: plan.coverage_boundary || [],
  // Targets the plan holds beyond this chunk, whether or not this run could act on them.
  deferred_targets: deferred,
  // Non-zero -> invoke again with the same run_id plus resume: run_dir, until it reaches 0.
  // Always 0 for a dry run, which finishes nothing and so cannot drive that loop, and 0 when
  // `stalled` -- a chunk that completed nothing would otherwise replan identically forever.
  remaining,
  // Set when the loop was broken because this chunk made zero forward progress. `deferred_targets`
  // is still the real outstanding count: the campaign is unfinished, not done. Distinguishing the
  // two matters -- `remaining: 0` alone reads as success.
  ...(stalled ? { stalled: true } : {}),
}
