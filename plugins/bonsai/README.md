# Bonsai plugin

Plugin-level README. See repo root README for marketing-facing description.

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
```
