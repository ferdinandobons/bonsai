# bonsai plugin

This is the Claude Code plugin manifest. End-user docs live in the top-level
README of this repo.

## Layout

- `.claude-plugin/plugin.json` — plugin manifest (Stop hook declaration)
- `commands/` — `/bonsai:*` slash commands
- `agents/gardener.md` — `bonsai:gardener` subagent
- `hooks/stop.sh` — Stop hook gatekeeper
- `lib/` — shell helpers (common, whitelist, mute, quota, dedup, branches, index, archive, migrate, lock, signal, dispatch, judge, reminder, telemetry)
- `lib/commands/` — backing scripts for the `/bonsai:*` slash commands
- `tests/unit/` — bats unit tests for `lib/`
- `tests/integration/` — bats end-to-end Stop hook test
- `tests/e2e/CHECKLIST.md` — manual end-to-end checklist

## Development

### Prerequisites
- `bash` 5+
- `jq`
- `bats-core` 1.10+ (`brew install bats-core` on macOS)
- `shellcheck` 0.9+ (`brew install shellcheck`)

### Run tests
```bash
cd plugins/bonsai
bats tests/unit tests/integration
shellcheck -x lib/*.sh hooks/*.sh
```
