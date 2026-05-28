# Bonsai end-to-end manual test checklist

Run this checklist before tagging a release. Use a scratch project directory
that you can throw away.

## Setup

- [ ] Create scratch project: `mkdir -p /tmp/bonsai-e2e && cd /tmp/bonsai-e2e`
- [ ] Install plugin from local marketplace: add `"source": {"source":"local","path":"/path/to/bonsai"}` to `extraKnownMarketplaces` in `~/.claude/settings.json`, then `/plugin install bonsai@bonsai`.
- [ ] Open Claude Code in the scratch project.

## Activation

- [ ] `/bonsai:start` → welcome message printed, `.claude/bonsai/` directory created with `config.json`, `state.json`, `branches/`, `archive/`.
- [ ] Whitelist contains the scratch project path: `jq . ~/.claude/plugin-data/bonsai/projects.json`.

## First observation cycle

- [ ] Ask Claude to do a small task that modifies files (e.g. "create a hello world Python script with a bug").
- [ ] End the turn (no new prompt).
- [ ] Wait up to 60 seconds.
- [ ] Verify a new file appears in `.claude/bonsai/branches/`.
- [ ] Verify `INDEX.md` was regenerated with the new entry under "Open".
- [ ] If the observation was critical: verify a push notification was received.
- [ ] If the observation was critical or normal: verify a chip appeared in the UI.

## Discuss

- [ ] `/bonsai:list` → shows the new observation with its id.
- [ ] `/bonsai:discuss <id>` → Claude responds with the observation context loaded and engages in discussion.

## Trim

- [ ] `/bonsai:dismiss <id> "test reason"` → branch frontmatter shows `status: trimmed`, `.claude/bonsai/trimmed.md` contains the entry.

## Keep

- [ ] Create another observation cycle (modify file → end turn → wait).
- [ ] `/bonsai:done <new-id>` → branch frontmatter shows `status: kept`.

## Mute / unmute

- [ ] `/bonsai:mute 1m` → next `Stop` hook exits silently during the window.
- [ ] Wait ~70 seconds (or run `/bonsai:unmute`).
- [ ] Trigger another `Stop` event → observation cycle resumes.

## Status

- [ ] `/bonsai:status` → reports ACTIVE state, last_run, today's counts, no recent errors.

## Help

- [ ] `/bonsai:help` → prints the full command table.

## Rest

- [ ] `/bonsai:stop` → whitelist no longer contains the scratch project, but `.claude/bonsai/` is preserved.

## Cleanup

- [ ] `rm -rf /tmp/bonsai-e2e`
- [ ] Optionally: remove scratch project from whitelist via `jq` if it persisted.

## Pass criteria

All boxes checked, no error messages, no leftover state outside whitelisted paths.
