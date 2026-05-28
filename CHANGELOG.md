# Changelog

All notable changes to Bonsai are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet. See the [open issues](https://github.com/ferdinandobons/bonsai/issues) for what's planned.

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
