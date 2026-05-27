---
name: help
description: Show all Bonsai commands
---

Print this command reference to the user:

```
Bonsai commands

  /bonsai:tend     →  start watching this project
  /bonsai:rest     →  stop watching (history preserved)
  /bonsai:health   →  show status, quota, cost
  /bonsai:observe  →  show recent open observations
  /bonsai:discuss  →  talk about an observation in this session
  /bonsai:trim     →  dismiss as unhelpful (Bonsai learns from this)
  /bonsai:keep     →  mark as resolved / accepted
  /bonsai:sleep    →  silence temporarily (30m / 1h / 4h / 1d)
  /bonsai:wake     →  resume after sleep
  /bonsai:config   →  edit per-project settings
  /bonsai:help     →  this message

Bonsai runs silently after each turn (5-min throttle, configurable).
It emits zero observations most of the time — by design.
It never modifies your code.

Docs: https://github.com/ferdinandobons/bonsai
```

Do not perform any other action.
