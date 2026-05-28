---
name: help
description: Show all Bonsai commands
---

Print this command reference to the user:

```
Bonsai commands

Watch
  /bonsai:start [--throttle=Xm] [--lenses=a,b,c] [--model=name]
                          start watching this project
  /bonsai:stop            stop watching (history preserved)
  /bonsai:mute <30m|1h|4h|1d> [--global]
                          silence temporarily
  /bonsai:unmute [--global]
                          resume after a mute

Read
  /bonsai:status          health, quota, cost
  /bonsai:list [N=5]      show N most recent open observations
  /bonsai:discuss <id>    talk through an observation in this session

Triage
  /bonsai:done <id>       mark as resolved / accepted
  /bonsai:dismiss <id> [reason]
                          dismiss as unhelpful (the gardener learns)

Config
  /bonsai:config [key value]   view, or set one key
  /bonsai:help                 this message

Bonsai runs silently after each turn (5-min throttle, configurable). It emits
zero observations most of the time — by design. It never modifies your code.

Docs: https://github.com/ferdinandobons/bonsai
```

Do not perform any other action.
