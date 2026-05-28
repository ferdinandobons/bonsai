# Contributing to Bonsai

First — thanks for being interested. This guide covers the minimum you need to know to land a clean PR.

## TL;DR

```bash
git clone git@github.com:ferdinandobons/bonsai.git
cd bonsai/plugins/bonsai

# Prereqs
brew install bats-core jq shellcheck   # macOS; on Linux use apt

# Run the test suite
bats tests/unit tests/integration

# Lint
shellcheck -x lib/*.sh hooks/*.sh
```

All green? Make your change, write a test, repeat. Open a PR against `main`.

## Repo layout

```
bonsai/                                  # repo root = marketplace root
├── .claude-plugin/marketplace.json      # marketplace descriptor
├── install.sh, uninstall.sh             # convenience installers
├── README.md, CHANGELOG.md, SECURITY.md, LICENSE
├── .github/workflows/ci.yml             # shellcheck + bats + JSON validation
└── plugins/bonsai/
    ├── .claude-plugin/plugin.json       # plugin manifest (declares Stop hook)
    ├── agents/gardener.md               # the bonsai:gardener subagent
    ├── commands/                        # /bonsai:* slash commands (11 files)
    ├── hooks/stop.sh                    # Stop hook gatekeeper
    ├── lib/                             # shell helpers (11 files)
    ├── tests/
    │   ├── unit/                        # bats unit tests
    │   ├── integration/                 # bats end-to-end Stop hook test
    │   └── e2e/CHECKLIST.md             # manual release checklist
    └── README.md                        # plugin-level dev notes
```

The design spec lives in the Proaictive repo's `docs/superpowers/specs/` and is referenced from CLAUDE.md-style comments in the code. Read it before making structural changes.

## House rules

### Testing

Bonsai is shell-script-heavy. Tests catch regressions that shellcheck can't.

- **Write a test first** for any new behavior in `lib/*.sh`. The test suite is bats; sandboxed via `tests/helpers/setup.bash` so each test runs against a fresh `mktemp -d` HOME.
- **Run the full suite** before pushing: `bats tests/unit tests/integration`. CI will re-run on Ubuntu — there are differences (`stat`, `date`, `shasum` vs `sha256sum`) so don't trust local-only.
- **Cover the corrupt-input case** for every function that reads a JSON file. The convention is one test per read function asserting safe behavior on `{not valid json`.

### Shell style

- POSIX-ish bash 5+. No bashisms hidden in `lib/common.sh` — that file is sourced by every other helper and the hook.
- **No `set -o pipefail` at module scope.** Sourcing a helper must not mutate the caller's shell options. (See the comment at the top of `lib/common.sh` for the rationale.) Local `( set -o pipefail; ... )` inside a function is fine.
- **All JSON writes go through `bonsai_json_write`.** Bare `> "$file"` is forbidden — it's not atomic and creates a torn-read window for concurrent readers.
- **All `jq` invocations on user-controlled input use the `if ! var=$(jq ...)` form**, not direct assignment. This is required for bats compatibility (bats wraps tests with `set -E`, and direct assignment in a function would trip the ERR trap).
- Run `shellcheck -x` before committing. CI enforces it.

### Commits

Conventional commits: `feat(scope): summary`, `fix(scope): summary`, `test(scope): summary`, `docs(scope): summary`, `ci: summary`, `chore: summary`.

End every commit message with:

```
Co-Authored-By: <your-name> <your-email>
```

Squash-merge when landing PRs; the commit history on `main` should read as a clean changelog.

### PR checklist

Before opening a PR:

- [ ] `bats tests/unit tests/integration` passes locally
- [ ] `shellcheck -x lib/*.sh hooks/*.sh` is clean
- [ ] `jq empty` on both `.claude-plugin/marketplace.json` and `plugins/bonsai/.claude-plugin/plugin.json`
- [ ] If you changed an interface, the spec (`docs/superpowers/specs/`) is updated
- [ ] If you added a user-visible behavior, the README is updated
- [ ] CHANGELOG.md has an `## [Unreleased]` entry for your change

## Design principles to preserve

These are the non-negotiables. PRs that violate them won't land.

1. **Read-only on user code.** The gardener's `allowed-tools` must never include `Edit`. Write is restricted to `.claude/bonsai/` only.
2. **Silent failure.** The Stop hook must never produce an error visible to the user's session. All error paths exit 0; errors land in `${CLAUDE_PLUGIN_DATA}/logs/bonsai-errors.log`.
3. **File is the source of truth.** Chips and push notifications are derivative outputs. If they fail, the branch file under `.claude/bonsai/branches/` must still be written. Order matters: write the branch file first, then attempt chip/push.
4. **Silence beats noise.** The gardener's hard quality bar is that zero observations is the correct answer most of the time. Any change that lowers the emission threshold needs a strong rationale.

## Release process (maintainer notes)

1. Bump `version` in both `.claude-plugin/marketplace.json` and `plugins/bonsai/.claude-plugin/plugin.json`.
2. Add an entry to `CHANGELOG.md` under `## [Unreleased]`, then promote it to the new version section.
3. Commit (`chore(release): bump to vX.Y.Z`).
4. Tag: `git tag -a vX.Y.Z -m "summary"`.
5. Push: `git push origin main && git push origin vX.Y.Z`.
6. Release: `gh release create vX.Y.Z --title "vX.Y.Z — summary" --notes "..."`.
7. Watch CI: `gh run watch $(gh run list --limit 1 --json databaseId -q '.[0].databaseId') --exit-status`.

## Questions

Open a [GitHub discussion](https://github.com/ferdinandobons/bonsai/discussions) for design questions, or an issue for bugs and feature requests. For security issues see [SECURITY.md](SECURITY.md).
