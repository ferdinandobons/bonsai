---
name: start
description: Start watching the current project with Bonsai
argument-hint: "[--throttle=Xm] [--quota-runs=N] [--quota-observations=N] [--lenses=a,b,c] [--model=name]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/lib/commands/start.sh:*)"]
---

The user has invoked `/bonsai:start` in the current project.

```!
"${CLAUDE_PLUGIN_ROOT}/lib/commands/start.sh" $ARGUMENTS
```

Print this welcome message to the user verbatim:

```
Bonsai is now watching this project.

Bonsai runs after each turn, with at least 5 minutes between checks.
It emits zero observations most of the time — by design.
It never modifies your code. It only observes the session and surfaces
high-signal observations: bugs, strategic blind spots, workflow tips.

Tier:
  CRITICAL  → push notification + chip + log
  NORMAL    → chip + log
  LOW       → log only

Where things live:
  .claude/bonsai/INDEX.md             ← human-readable index
  .claude/bonsai/branches/            ← one file per observation
  .claude/bonsai/config.json          ← per-project config

Commands:
  /bonsai:status      → see what Bonsai has been up to
  /bonsai:list     → read recent observations
  /bonsai:mute 30m   → silence for 30 minutes
  /bonsai:stop        → stop entirely (log preserved)
  /bonsai:help        → all commands

You can change throttle / quota / lenses with /bonsai:config or via flags
on /bonsai:start (e.g. /bonsai:start --throttle=10m --lenses=technical,workflow).
```

Do not run any other action.
