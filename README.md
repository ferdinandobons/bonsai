# Bonsai

> A patient gardener for your code.

Bonsai is a [Claude Code](https://claude.com/claude-code) plugin that watches
your session silently and surfaces high-signal observations between turns —
bugs, strategic blind spots, workflow inefficiencies — only when they matter.

It is named for the art of bonsai: patient, observant, minimal. Trim only
what matters. Never intervene for the sake of intervening.

## Install

Add this marketplace to your Claude Code settings (in `~/.claude/settings.json`):

```json
{
  "extraKnownMarketplaces": {
    "bonsai": {
      "source": { "source": "github", "repo": "ferdinandobons/bonsai" }
    }
  }
}
```

Then install the plugin:

```bash
/plugin install bonsai@bonsai
```

## Activate per project

```bash
cd ~/your-project
/bonsai:tend
```

That's it. Bonsai now watches this project silently. It runs after each turn,
waits at least 5 minutes between checks, and emits zero observations most of
the time — by design.

## Commands

| Command | Action |
|---|---|
| `/bonsai:tend` | Start watching this project |
| `/bonsai:rest` | Stop watching (history preserved) |
| `/bonsai:health` | Show status, quota, cost |
| `/bonsai:observe` | Read recent observations |
| `/bonsai:discuss <id>` | Discuss an observation in this session |
| `/bonsai:trim <id> [reason]` | Mark as not useful (Bonsai learns) |
| `/bonsai:keep <id>` | Mark as resolved |
| `/bonsai:sleep <duration>` | Silence (30m / 1h / 4h / 1d) |
| `/bonsai:wake` | Resume after sleep |
| `/bonsai:config <key> <value>` | Edit per-project config |
| `/bonsai:help` | Full command reference |

## How it works

After each turn of Claude Code, a `Stop` hook script runs. It checks: is this
project tended? Are we throttled? Are we below daily quota? Is Bonsai sleeping?
If all gates pass, it dispatches a background subagent — the *gardener* — that:

1. Reads the recent session transcript
2. Picks a lens (technical / strategic / workflow) based on what just happened
3. Looks for high-signal observations under that lens
4. Writes survivors to `.claude/bonsai/branches/<id>-<slug>.md`
5. For critical observations: sends a push notification
6. For critical + normal: creates a clickable chip you can spin into a fresh
   task session

## Privacy

Bonsai processes:
- Your Claude Code session transcript (via the standard transcript API)
- Files in your project modified since the last run
- Optional: `git status` / `git diff --stat` output (when a `.git/` exists)

The gardener subagent runs through the LLM configured in your Claude Code
session. No data leaves your machine beyond what your normal Claude Code
usage already sends to the model provider.

Bonsai writes only inside `${CLAUDE_PROJECT_DIR}/.claude/bonsai/` and
`${CLAUDE_PLUGIN_DATA}/`. It never modifies your project source files.

## Trust posture

- Read-only on your code, always.
- Silent failure: any error path exits 0 silently. Bonsai never disturbs a session.
- File system is the source of truth: chips and push notifications are
  derivative; the markdown log under `.claude/bonsai/` always wins.

## License

Apache 2.0 — see [LICENSE](LICENSE).

## Contributing

Issues and PRs welcome. Run `cd plugins/bonsai && bats tests/unit tests/integration` before submitting.
