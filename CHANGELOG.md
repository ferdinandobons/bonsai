# Changelog

All notable changes to Bonsai are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet. See the [open issues](https://github.com/ferdinandobons/bonsai/issues) for what's planned.

## [0.6.1] — 2026-05-29

### Fixed
- **CI**: the Shellcheck job runs `shellcheck -x` (default severity, fails on
  warnings), but local checks had used `-S error` — masking two preexisting
  `SC2155` warnings in `stop.sh` introduced during the v0.5.1 audit. CI had been
  red since v0.5.1 for this reason. Declared/assigned separately; no behavior
  change. (v0.6.0 shipped the return reminder but with this red CI; v0.6.1 is the
  first green build carrying it.)

## [0.6.0] — 2026-05-29

### Added
- **Return reminder.** When you come back to a watched project — on the next
  prompt you send (`UserPromptSubmit`) or when a new conversation starts
  (`SessionStart`) — Bonsai surfaces a soft in-chat box listing the top **critical**
  observations awaiting review, so a high-severity finding can't sit unseen in a
  file you forgot to open. Reading stays manual (`/bonsai:list`); the reminder only
  points. New `hooks/remind.sh` + `lib/reminder.sh`.
  - **Critical only** — normal/low never trigger it; silence still beats noise.
  - **Once per session** — per-session dedup in its own `reminder.json` (never
    touches `state.json`, so it can't race the detached gardener). Re-surfaces only
    when a new critical appears or the session changes.
  - **Respects mute** — a globally or per-project muted project stays silent.
  - The box shows up to 3 most-recent findings (id + title), collapsing the rest
    into "+N more".

## [0.5.1] — 2026-05-29

Full audit & cleanup pass (multi-agent review across correctness, security, dead
code, quality, performance, docs, tests). No new features — fixes, hardening, and
cleanup only. Suite 146 → 165 tests, all green; net −198 lines.

### Fixed
- **lock.sh**: a held lock whose epoch write hadn't landed was treated as age-0
  (ancient) and reclaimed, allowing a second gardener to spawn. Missing/unreadable
  epoch now defaults to "now" (fresh).
- **/bonsai:list**: a non-numeric `N` argument aborted the command mid-pipeline
  under `set -e`; it is now validated.
- **/bonsai:config**: setting a numeric key to a non-numeric (or negative) value
  was silently written and reported "OK" while every consumer ignored it; values
  are now type-checked per key and rejected with a clear error.

### Security
- **commands/*.md**: argument placeholders are now quoted (`"$id"`, etc.), so shell
  metacharacters in a command argument are treated as data — mitigates Claude
  Code's textual argument interpolation (upstream issue #16163).
- **gardener.md**: the judge pass scratch dir moved from world-writable
  `/tmp/bonsai-judge-*` to `$CLAUDE_PLUGIN_DATA/judge/<session_id>` (private,
  under `$HOME`), so a co-located user can't pre-create or symlink it.

### Removed
- Dead code: `lib/push.sh` and `lib/chip.sh` (push/chips removed back in v0.3.0),
  the unused `bonsai_branches_allocate_id`, `bonsai_signal_diff_stat`, and
  `bonsai_whitelist_list` functions, and the inert `push_notifications_*` config
  keys. `lib/` 16 → 14 files.

### Changed
- **Internal consolidation (behavior-preserving):** shared helpers promoted into
  `common.sh` (`bonsai_state_file`, `bonsai_config_file`, `bonsai_sha256`,
  `bonsai_file_mtime_epoch`, `bonsai_now_basic`) replacing duplicated private defs
  and inline literals; `status.sh`'s token scan folded into a new
  `bonsai_telemetry_token_usage` (one log scan instead of two); `mute.sh`'s
  project/global pairs deduped behind shared file-level primitives.
- **Test integrity:** fixed two silently-non-asserting tests (an intermediate
  `[[ ]]` and a vacuous `if`); added coverage for `migrate`, the quota caps
  (observation + global), and `/bonsai:start` side effects.
- **Docs:** SECURITY.md, README, CONTRIBUTING, start.md, and gardener.md aligned
  with actual v0.5.x behavior (removed stale MCP/push/chip/`disable-model-invocation`
  claims; corrected the gardener's wall-time budget and the adaptive-throttle
  interval).

### Deferred (documented, not applied)
- Hot-path micro-optimizations (batching repeated `jq`/`git` calls in the
  Stop-hook gate chain): low impact on a throttle-gated path and the clean fixes
  would risk the diff-hash semantics / JSON-malformed guard — not worth the
  regression risk.

## [0.5.0] — 2026-05-28

### Added
- **Adaptive throttle (Stage 0 of the "smarter gardener" work).** `stop.sh` now
  derives a cheap signal of whether the working tree changed since the last run
  (`lib/signal.sh`: hash of `git diff HEAD` + untracked files). If code changed,
  the gardener uses the short cadence (`throttle_min_minutes`, default 5); if
  nothing changed (idle/conversational turn), it uses the longer
  `throttle_idle_minutes` (default 20, configurable via `/bonsai:config`).
  strategic/workflow observations are still sampled, never dropped — this cuts
  the ~350k-token cost of running on substance-free turns without going
  code-only. `bonsai_quota_throttle_ok` gained an optional override arg.
- **Git diff as the gardener's primary detection context (Stage 1).** The Stop
  hook now passes the project's `git diff HEAD` (bounded to ~60KB) to the
  gardener as a `git_diff` field, and `gardener.md` instructs it to triage from
  the actual changes first and use the transcript for intent / strategic /
  workflow signals. Previously the gardener saw only the transcript tail.
- **Semantic dedup + calibrated severity via a Haiku judge pass (Stage 2).** New
  `lib/judge.sh` builds a cheap second-model prompt and parses its verdict; the
  gardener now runs `claude -p --model haiku` over its candidates before writing
  to (a) drop observations that are the same problem as an existing open one
  even when worded differently — beating the old exact-hash dedup — and (b)
  calibrate severity using the user's dismissed anti-patterns. Inputs are passed
  via fixed-path temp files (no shell injection); the gardener fails open if the
  judge errors, so a real finding is never lost to a judge hiccup.

### Fixed
- **The gardener was always told `last_run_iso = now`.** `stop.sh` read
  `last_run_iso` *after* `update_last_run` had already overwritten it, so the
  gardener's observation window was effectively zero-length every run. It now
  captures the previous timestamp before updating. (`hooks/stop.sh`)

## [0.4.1] — 2026-05-28

### Fixed
- **Open observations with a malformed severity no longer vanish from the
  index.** `bonsai_index_regenerate`'s severity `case` had no default branch, so
  an `open` branch whose severity wasn't `critical`/`normal`/`low` was silently
  dropped from INDEX.md (the file stayed on disk but became invisible). Unknown
  severities now fall back to the `normal` section. (`lib/index.sh`)
- **`/bonsai:start` validates numeric flags instead of silently ignoring bad
  values.** `--throttle`/`--quota-*` with a non-numeric value are now skipped
  with a `WARN` (previously a bad value made `jq` fail and was dropped with no
  feedback). Config writes go through a helper that cleans up its tmp file on
  failure, and `set -f` prevents glob expansion while parsing flags.
- **`/bonsai:config` fails gracefully on a non-object config.** A config that is
  valid JSON but not an object (e.g. `[]`) passed the `jq empty` check but made
  the update `jq` error out, which under `set -e` killed the script before its
  own error message. The update `jq` calls now tolerate failure so the integrity
  check reports a clean error. (`lib/commands/config.sh`)

## [0.4.0] — 2026-05-28

### Fixed
- **Branch id collisions can no longer overwrite observations.** Id assignment
  was delegated to the LLM gardener (`gardener.md` proposed `YYYY-MM-DD-NNN`),
  which cannot reliably count existing ids — two runs both picked `001` and
  `bonsai_branches_write` used `mv`, silently clobbering the earlier branch.
  `branches_write` is now the authority on the id: it detects an already-used
  id prefix, reallocates to the next free id for the day, and creates the file
  with `ln` (atomic, refuses to overwrite) instead of `mv`. The LLM-proposed id
  is now advisory. (`lib/branches.sh`)

### Added
- **Per-project concurrency lock (`lib/lock.sh`).** Two interactive sessions on
  the same project — or two Stop hooks racing — could spawn concurrent
  gardeners that race on `quota.json` / `state.json` / branch-id allocation.
  `stop.sh` now acquires an atomic `mkdir`-based lock before dispatch and skips
  silently if a gardener is already running; the detached gardener subshell
  releases it on exit, with a 15-minute staleness backstop so a crashed
  gardener can never wedge the project. Uses `mkdir` rather than `flock` for
  macOS portability.
- **Wall-clock guard on the gardener subprocess.** `--max-turns` caps
  iterations but cannot stop a hung `claude`; dispatch now wraps it with
  `timeout`/`gtimeout` (600s) when available, degrading gracefully where
  neither is installed (macOS), with `--max-turns` remaining the bound.
  (`lib/dispatch.sh`)
- **TTL purge of transient plugin-data.** Pre-sliced transcripts
  (`sliced/sliced-*.jsonl`) and per-run gardener logs (`logs/gardener-*.log`)
  were written once and never cleaned up, growing unbounded (~MBs/day at
  moderate use). `bonsai_archive_run` now purges these older than
  `transient_data_ttl_days` (default 7, configurable via `/bonsai:config`).
  The persistent `bonsai.log` / `bonsai-errors.log` are never matched.
  (`lib/archive.sh`)
- **Gardener run health in `/bonsai:status`.** A new `lib/telemetry.sh` reads
  the per-run gardener logs and `/bonsai:status` now reports completed vs
  errored runs, how many hit the turn cap (`subtype == error_max_turns`), and
  the peak `num_turns` used in the last 24h. This makes any future
  `--max-turns` change data-driven instead of guesswork (the cap was bumped
  8→15→25 blind). Note: the run's turn outcome lives in `subtype`, not the
  top-level `stop_reason` (which is the last API message's reason).

## [0.3.1] — 2026-05-28

### Fixed
- **CI: shellcheck on `lib/dispatch.sh` and `hooks/stop.sh` now passes.**
  Two informational warnings that broke the v0.3.0 CI:
  - `SC2016` in `dispatch.sh` — flagged the single-quoted `bash -c '…$1…'`
    body in `bonsai_dispatch_gardener`. The single quotes are intentional
    (we want `$1` to refer to the positional arg passed to the nested
    subshell, not expand at the outer shell). Added `shellcheck disable=SC2016`
    with explanatory comment.
  - `SC2317` in `stop.sh` — flagged the defensive `exit 0` after `main`.
    The redundancy is the point: `main()` always exits explicitly, but the
    outer exit guarantees a 0 return even if a future edit lets a code
    path return-without-exit. The Stop hook must never leak a nonzero exit
    to CC. Added `shellcheck disable=SC2317` with explanatory comment.

No runtime changes; v0.3.0 worked correctly. This is a pure CI hygiene
release so future releases ship with a green CI badge.

## [0.3.0] — 2026-05-28

This is the release in which Bonsai actually starts working end-to-end.
Versions 0.1.0 through 0.2.4 had a broken dispatch architecture: the Stop
hook emitted `hookSpecificOutput.additionalContext` to ask Claude to spawn
the gardener subagent, but Claude Code's Stop hook schema rejects that
field (only `PreToolUse`, `UserPromptSubmit`, `PostToolUse`, and
`PostToolBatch` accept context injection). Every dispatch attempt was
silently rejected by CC's schema validator. The plugin appeared installed
and watching, but the gardener never ran.

### Fixed

- **Stop hook now spawns the gardener via a detached `claude -p` subprocess.**
  `lib/dispatch.sh` runs `nohup claude -p --agent bonsai:gardener … &
  disown` so the gardener executes in its own headless session, completely
  independent of the parent CC session. The Stop hook returns empty output
  (schema-compliant) and the gardener writes observations to
  `.claude/bonsai/branches/` asynchronously.
- **`CLAUDE_PLUGIN_DATA` export carried forward from v0.2.4.** Still needed
  because CC doesn't export it to slash command Bash() subprocesses.

### Changed

- **Transcript pre-slicing.** Real session transcripts can exceed 1MB /
  200k tokens — well beyond Sonnet's context window — making the gardener
  spend most of its turns reading and filtering instead of producing
  observations. The Stop hook now runs `tail -n $transcript_tail_lines`
  (default 200, configurable in `.claude/bonsai/config.json`) before
  dispatch, writes the slice to `$CLAUDE_PLUGIN_DATA/sliced/`, and passes
  the small file path to the gardener. The full original path is still
  available as `original_transcript_path` for the rare case the gardener
  needs older context.
- **Gardener prompt simplified.** Step 1 no longer warns about large
  transcripts because the input is pre-sliced. Tool list reduced to standard
  CC tools (`Bash, Read, Grep, Glob, Write`); transcript reading switched
  from `mcp__ccd_session_mgmt__search_session_transcripts` (which is not
  reliably available in `claude -p` subprocess context) to direct `Read` on
  `transcript_path`.
- **Gardener frontmatter cleaned.** Dropped `disable-model-invocation: true`
  (silently ignored — only valid for Skills). Renamed `allowed-tools` to
  `tools` (canonical subagent field name per CC docs). Added
  `max-turns: 25` to cap runaway loops at the subagent level in addition
  to the dispatch-level cap.
- **`/bonsai:status` now reports actual token usage.** Instead of estimating
  USD cost (meaningless for subscription users — gardener runs consume the
  Agent SDK credit included with Pro/Max/Team/Enterprise plans, not actual
  USD), status sums real token counts from gardener logs across the four
  CC buckets (`input_tokens`, `cache_read_input_tokens`,
  `cache_creation_input_tokens`, `output_tokens`).
- **Dispatch limits philosophy.** Dropped `--max-budget-usd`. The combination
  of `--max-turns 25` and the pre-sliced transcript bounds gardener work
  effectively for subscription users.

### Removed

- **Chips (`mcp__ccd_session__spawn_task`) and push notifications
  (`PushNotification`).** Both depend on tools that aren't reliably
  available in `claude -p` subprocess context. v0.3.0 is filesystem-only:
  observations land in `.claude/bonsai/branches/` and are surfaced via
  the auto-regenerated `INDEX.md` (and `/bonsai:list`). Chip + push may
  return in a later release once their underlying mechanisms stabilize.

### The proof

On its first real CC-triggered run against this dev session's transcript,
the gardener caught a bug introduced 30 minutes earlier in the same
session: `status.sh` was summing only `input_tokens + output_tokens`,
omitting cache-read and cache-write tokens that dominate actual context
consumption (~54x underreport for the previous gardener run). The
observation cited the exact file path, lines 47–50, and provided a
copy-pasteable fix. The fix was applied in this release. The full
observation lives at
`branches/2026-05-28-001-token-display-in-bonsai-status-omits-cac.md`.

This is exactly the use case Bonsai exists for, and it demonstrated it
on its own codebase.

### Migration from v0.2.x

```
/plugin marketplace update bonsai
/reload-plugins
```

If that doesn't pull v0.3.0 immediately, force a fresh install:

```
/plugin uninstall bonsai@bonsai
/plugin marketplace remove bonsai
/plugin marketplace add ferdinandobons/bonsai
/plugin install bonsai@bonsai
/reload-plugins
```

Existing branch files and per-project state are unaffected.

## [0.2.4] — 2026-05-28

### Fixed
- **Critical: slash commands wrote state to `/tmp/bonsai-no-data/` instead
  of the canonical plugin-data path.** Per the
  [Claude Code plugins reference](https://code.claude.com/docs/en/plugins-reference#environment-variables),
  CC exports `${CLAUDE_PLUGIN_DATA}` to hook processes and MCP/LSP
  subprocesses, but **not** to slash command Bash() subprocesses. Bonsai
  relied on the variable being available in both contexts. Result: after
  `/bonsai:start`, the whitelist landed in the `/tmp` fallback, while the
  Stop hook (which does receive the variable) read the correct path,
  found no whitelist, and silently exited. **Bonsai appeared installed
  and started but never actually observed anything.**

  Two-layer fix:
  1. All 10 invoking `.md` commands now pass `CLAUDE_PLUGIN_DATA` as an
     env prefix in the block-fence command, so CC substitutes the value
     and the subprocess inherits it (CC-canonical approach).
  2. `lib/commands/_bootstrap.sh` and `hooks/stop.sh` now define a
     defensive fallback to `~/.claude/plugins/data/bonsai-bonsai/` so
     direct invocation (tests, debugging) and any future CC behavior
     change still work.

  No user action required after upgrading. Existing state in
  `/tmp/bonsai-no-data/projects.json` (if any) can be safely moved to
  `~/.claude/plugins/data/bonsai-bonsai/projects.json`, or just re-run
  `/bonsai:start` on each watched project to recreate it.

## [0.2.3] — 2026-05-28

### Changed
- **README refreshed for parity with shipped behavior.** Three stale
  spots fixed:
  - Commands table reorganized into four functional groups
    (Watch / Read / Triage / Config) matching `/bonsai:help`, with
    real argument syntax inline (`[N=5]`, `<id>`, `<30m|1h|4h|1d>`,
    `[--global]`, plus `/bonsai:start` flags).
  - `/bonsai:unmute` row corrected: was "Resume after sleep", now
    "Resume after a mute". (`sleep`/`wake` were renamed to
    `mute`/`unmute` in v0.2.0; the README row was missed.)
  - Bottom `Latest:` changelog link updated from `v0.1.4` to current.

No code changes in this release — docs only.

## [0.2.2] — 2026-05-28

### Removed
- **`install.sh` and `uninstall.sh`** convenience scripts. The native
  Claude Code install path (`/plugin marketplace add ferdinandobons/bonsai`
  + `/plugin install bonsai@bonsai`) is now the single supported method.

### Why
The bash scripts only edited `~/.claude/settings.json` declarations —
the actual marketplace clone, cache population, and plugin validation
were always deferred to Claude Code's next startup. The native commands
do the same `settings.json` mutation **plus** clone, cache, validate,
and surface errors synchronously. They also keep `known_marketplaces.json`,
`installed_plugins.json`, and per-plugin install manifests in sync —
state the bash scripts ignored entirely.

Maintaining two install paths created a mismatch risk: installing via
script then uninstalling via `/plugin uninstall` (or vice versa) left
leftover cache or settings entries. Collapsing to a single path removes
that class of bug.

### Migration
- Users on `0.2.1` or earlier installed via the bash script: no action
  required. The existing `settings.json` entry remains valid and Claude
  Code continues to load the plugin. To uninstall going forward, use
  `/plugin uninstall bonsai@bonsai` + `/plugin marketplace remove bonsai`
  instead of the (now-removed) `uninstall.sh`.
- Anyone with bookmarked `curl | bash` install one-liners: they will 404.
  Replace with the two-line `/plugin` install shown in the README.

## [0.2.1] — 2026-05-28

### Changed
- **`/bonsai:help` reorganized** into four functional groups
  (Watch / Read / Triage / Config) and now surfaces real argument syntax
  inline (`<id>`, `[N=5]`, `<30m|1h|4h|1d>`, `[--global]`, plus
  `/bonsai:start` flags), so users can discover usage from the help
  screen without consulting the README.
- **`/bonsai:list` empty-state message** improved: instead of the
  duplicate-worded "No open observations. /bonsai:status for status.",
  the empty state now explains the silent-by-default behavior and
  redirects to `/bonsai:status` for health and quota.

## [0.2.0] — 2026-05-28

### Changed
- **BREAKING — slash commands renamed for clarity.** The bonsai metaphor
  stays in the `bonsai:` namespace prefix; individual commands now use
  plain CLI verbs:

  | Old              | New                |
  |------------------|--------------------|
  | `/bonsai:tend`   | `/bonsai:start`    |
  | `/bonsai:rest`   | `/bonsai:stop`     |
  | `/bonsai:health` | `/bonsai:status`   |
  | `/bonsai:observe`| `/bonsai:list`     |
  | `/bonsai:trim`   | `/bonsai:dismiss`  |
  | `/bonsai:keep`   | `/bonsai:done`     |
  | `/bonsai:sleep`  | `/bonsai:mute`     |
  | `/bonsai:wake`   | `/bonsai:unmute`   |

  `discuss`, `config`, and `help` are unchanged. No deprecation aliases:
  pre-1.0, no known external scripts depend on the old names.
- README, install/uninstall scripts, e2e checklist, and user-facing
  messages updated to the new vocabulary (`muted`/`unmuted` instead of
  `sleeping`/`awake`, `watched projects` instead of `tended projects`).

### Internal
- Whitelist JSON schema still uses the `tended` key (on-disk schema —
  rename would require migration logic for existing users; flagged for
  a future major bump if ever worth it).

## [0.1.6] — 2026-05-28

### Fixed
- **Slash command scripts now run end-to-end**. v0.1.5 fixed the
  `.md` → script invocation but the scripts themselves still failed
  on the first `source "${CLAUDE_PLUGIN_ROOT}/lib/..."` line, because
  Claude Code expands `${CLAUDE_PLUGIN_ROOT}` in the `.md` block-fence
  (to find the script) without exporting it as an env var to the
  subprocess. Added `lib/commands/_bootstrap.sh`, sourced as the first
  line of every command script, which derives `CLAUDE_PLUGIN_ROOT`
  from the script's own location (`$(dirname BASH_SOURCE)/../..`) and
  falls back `CLAUDE_PROJECT_DIR` to `$PWD`.

## [0.1.5] — 2026-05-28

### Fixed
- **Slash commands now work**. Previously `/bonsai:tend` and every other
  `/bonsai:*` command failed with `bash: /lib/common.sh: No such file or
  directory` because Claude Code did not expand `$CLAUDE_PLUGIN_ROOT` /
  `$CLAUDE_PROJECT_DIR` when the inline `!`bash -c '...'` form was used.
  All ten commands now invoke an extracted script under
  `lib/commands/<name>.sh` via the executable block-fence
  `` ```! `` form with `${CLAUDE_PLUGIN_ROOT}` (braces), matching the
  pattern used by `claude-plugins-official/ralph-loop`.

### Changed
- Each command's `allowed-tools` now declares the specific script path
  (e.g. `Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/tend.sh:*)`) instead of
  the generic `Bash`, so the auto-mode classifier recognises the call as
  plugin-owned and stops blocking it.
- Removed `$CLAUDE_PROJECT_DIR` interpolations from prose lines in
  `.md` files — the preprocessor never expanded them, leaving the literal
  token in messages shown to the model.

## [0.1.3] — 2026-05-28

### Added
- **One-liner installer** (`install.sh`): atomic `jq`-based merge into
  `~/.claude/settings.json` with timestamped backup, idempotent re-runs,
  pre-existing-install detection. Invocable via `bash <(curl ...)`.
- **Uninstaller** (`uninstall.sh`): removes marketplace + plugin entry from
  settings while preserving per-project `.claude/bonsai/` observation logs.
- **README install section rewritten** to document three install paths in
  order of ease: one-liner, native `/plugin marketplace add + /plugin install`,
  manual `settings.json` edit.

### Notes
- The native `/plugin marketplace add ferdinandobons/bonsai` path was the
  simplest all along but was not documented in v0.1.0–v0.1.2. Now front-and-center.

## [0.1.2] — 2026-05-28

### Fixed
- **CI was failing on Linux** due to a cross-platform `stat` flag conflict in
  `lib/archive.sh`. `stat -f %m` on BSD/macOS returns mtime; on Linux it is the
  filesystem-info flag (succeeds with multi-line output, breaking arithmetic).
  Fix: try `stat -c %Y` (GNU) first, fall back to `stat -f %m` (BSD); validate
  numeric output before use. v0.1.2 is the first version verified green by
  GitHub Actions on Ubuntu.

## [0.1.1] — 2026-05-28

### Added
- **Global mute** for users with multiple tended projects:
  `/bonsai:sleep --global` and `/bonsai:wake --global` operate on a global mute
  file at `$CLAUDE_PLUGIN_DATA/mute.json`. The Stop hook checks the global mute
  *before* the per-project mute. Adds `bonsai_mute_is_muted_global`,
  `bonsai_mute_sleep_global`, `bonsai_mute_wake_global` (4 new tests).

### Fixed
- **Push notifications were declared but never sent.** v0.1.0 had `lib/push.sh`
  fully implemented and advertised in the welcome message, but the gardener
  had no `PushNotification` tool in its `allowed-tools` and no Step 6
  instruction to send one. Critical observations were silently demoted to
  chips-only. Fixed by adding the tool + the workflow step (rate-limited via
  `bonsai_push_rate_ok`).
- **`/bonsai:config` could silently wipe `config.json`** when the file was
  already corrupt: `jq` would fail, `tmp` would be empty, and `mv` would
  replace the corrupt config with an empty file. Now guards with `jq empty`
  before AND after the edit and refuses to write on either failure.

### Notes
- This release was published before CI completed; the Linux CI failure caught
  in 0.1.1 was fixed and re-tagged as 0.1.2.

## [0.1.0] — 2026-05-28

### Added
First public release.

- **`Stop` hook gatekeeper** (`hooks/stop.sh`) declared in `plugin.json` — runs
  after every Claude Code turn. Gating chain: whitelist → mute → throttle →
  per-project quota → global quota. Any failure exits 0 silently. When all
  gates pass, emits `hookSpecificOutput` with a natural-language
  `additionalContext` instructing Claude to dispatch the gardener subagent
  in the background.
- **`bonsai:gardener` subagent** (`agents/gardener.md`) — read-only,
  network-free, 60s wall-time budget, ≤3 observations per run, hard quality
  bar ("silence beats noise"). Triages between technical / strategic /
  workflow lenses based on transcript + filesystem signals. Outputs branch
  files, chips (for normal+critical), push notifications (for critical only),
  and the dedup hash array.
- **11 namespaced slash commands** (`/bonsai:tend`, `:rest`, `:health`,
  `:observe`, `:discuss`, `:trim`, `:keep`, `:sleep`, `:wake`, `:config`,
  `:help`) — opt-in lifecycle, observation review, anti-pattern teaching,
  config.
- **11 shell helpers** under `lib/` (`common`, `whitelist`, `mute`, `quota`,
  `dedup`, `branches`, `index`, `chip`, `push`, `archive`, `migrate`),
  shellcheck-clean, atomic JSON writes via `mktemp + mv`, set-`-E`-safe
  jq invocations, cross-platform `date`/`stat` handling.
- **Per-project file store**: `INDEX.md` (auto-maintained), `state.json`
  (last_run_iso + dedup hash window of 50), `config.json` (per-project
  overrides), `trimmed.md` (anti-patterns log), `branches/` (one file per
  observation), `archive/` (auto-moved after configurable thresholds).
- **103 bats tests** (95 unit + 8 integration), GitHub Actions CI with
  shellcheck + bats + JSON manifest validation, manual E2E checklist for
  release validation, Apache 2.0 license.

[Unreleased]: https://github.com/ferdinandobons/bonsai/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/ferdinandobons/bonsai/releases/tag/v0.1.3
[0.1.2]: https://github.com/ferdinandobons/bonsai/releases/tag/v0.1.2
[0.1.1]: https://github.com/ferdinandobons/bonsai/releases/tag/v0.1.1
[0.1.0]: https://github.com/ferdinandobons/bonsai/releases/tag/v0.1.0
