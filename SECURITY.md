# Security policy

## Reporting a vulnerability

If you believe you've found a security issue in Bonsai, please **do not** open a public GitHub issue. Instead, email **1bonsegnaferdinando@gmail.com** with:

- A description of the issue and the affected version
- Steps to reproduce
- Your assessment of impact

I'll acknowledge within 72 hours and aim to ship a fix within 7 days for high-severity issues. After the fix is released, you're welcome to disclose publicly; I'll credit you in the changelog unless you'd rather stay anonymous.

## Threat model — what Bonsai can and cannot do

Bonsai is a Claude Code plugin that executes shell scripts in your local environment as part of normal operation. This makes the threat model worth being explicit about.

### What Bonsai is allowed to do

- Read your Claude Code session transcript (via `mcp__ccd_session_mgmt__search_session_transcripts`).
- Read files in your project directory that have been modified since the last gardener run.
- Optionally run read-only `git` commands (`git status`, `git diff --stat HEAD`) when a `.git/` directory exists.
- Write to `${CLAUDE_PROJECT_DIR}/.claude/bonsai/` (branch files, INDEX.md, state.json, trimmed.md).
- Write to `${CLAUDE_PLUGIN_DATA}/` (whitelist, global config, quota counters, mute state, logs).
- Send push notifications **only for `critical` severity** observations, rate-limited to 5 per project per hour.
- Spawn task chips (`mcp__ccd_session__spawn_task`) for `critical` and `normal` observations.

### What Bonsai is explicitly NOT allowed to do

- **Edit any file outside `.claude/bonsai/`.** The gardener subagent's `allowed-tools` list does not include `Edit`. Bash is restricted to read-only commands in the gardener's system prompt. Write is restricted to the bonsai directory.
- **Make any network call.** No `WebSearch`, no `WebFetch`. The gardener's `allowed-tools` does not include them.
- **Run arbitrary code suggested by the LLM.** The gardener cannot execute its own observations; it only writes them to files and creates chips. The user has to click a chip (which opens a separate Claude Code session) to act on a suggestion.
- **Spawn sub-subagents.** `disable-model-invocation: true` in the gardener's frontmatter prevents recursive agent dispatch.

### Failure modes that affect security

- **Silent failure on the hook path.** Any error in `hooks/stop.sh` is trapped, logged, and the script exits 0. This protects the user's session but means a bug could silently disable observation. Inspect `${CLAUDE_PLUGIN_DATA}/logs/bonsai-errors.log` if you suspect Bonsai is misbehaving.
- **Corrupt JSON in state files.** Every read function defends against corruption and returns safe defaults. Write functions refuse to overwrite a known-corrupt file (`/bonsai:config` is the user-facing example; `bonsai_json_write` is the underlying primitive).
- **Concurrent writes.** Per-project state writes use `mktemp + mv` for atomicity. The whitelist add path has a small TOCTOU window for concurrent `/bonsai:start` invocations on the same project; this is documented in the source and considered acceptable for v1.

## Where to look first if something looks wrong

1. `${CLAUDE_PLUGIN_DATA}/logs/bonsai-errors.log` — every silent failure path logs here.
2. `${CLAUDE_PROJECT_DIR}/.claude/bonsai/INDEX.md` — confirms what observations have been emitted.
3. `/bonsai:status` — surfaces last run, quota, mute state, last error.

## Supported versions

Only the latest released version receives security fixes. Pre-1.0, expect rapid iteration. From 1.0 onward, the latest minor version on the latest major line is supported.

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✅ Latest only (0.1.3 at time of writing) |
| < 0.1.0 | ❌ No releases existed before 0.1.0 |
