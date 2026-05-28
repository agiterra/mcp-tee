# mcp-tee

A tiny launcher that wraps an MCP (Model Context Protocol) server command and
tees its stderr to a logfile, while keeping the original stderr stream intact
for the parent process (Claude Code, Codex, etc.).

## Why

Stdio MCP servers communicate JSON-RPC over stdout; stderr is free for logs.
Most CC-hosted plugins log to stderr via pino or similar, but CC doesn't
persist that stream to disk by default. After-the-fact debugging requires
reproducing the failure live.

`mcp-tee` is one shell script. Drop it in front of any `command` line in
`.mcp.json` and the server's stderr lands in `~/.wire/mcp-stderr/<name>.log`
in addition to its normal destination — useful for verifying clock-gap
gating, channel injection, validator failures, signature mismatches,
anything that the host swallows.

## Usage

```jsonc
// .mcp.json
{
  "mcpServers": {
    "wire": {
      "command": "/Users/you/.claude/plugins/cache/agiterra/mcp-tee/0.1.0/bin/mcp-tee.sh",
      "args": ["wire", "bun", "run", "--cwd", "${CLAUDE_PLUGIN_ROOT}", "--silent", "start"]
    }
  }
}
```

Argument shape: `mcp-tee.sh <log-name> <command> [args...]`.
The launcher `exec`s the command with `2> >(tee -a <log> >&2)`.

## Env knobs

| Var | Default | Effect |
|---|---|---|
| `MCP_LOG_DIR` | `~/.wire/mcp-stderr` | Output directory |
| `MCP_LOG_ROTATE_BYTES` | `10485760` (10MB) | Rotate threshold at startup |
| `MCP_TEE_DISABLE` | `0` | Set to `1` to exec without teeing (escape hatch) |

Rotation is single-generation: if the log exceeds the threshold at startup,
rename to `<name>.log.1` and start fresh. No background rotation; tee runs
inline for the life of the MCP server.

## Install

`mcp-tee` is shell-only; no compile step.

- **Path-pinned (no install):** reference `bin/mcp-tee.sh` directly from `.mcp.json` using an absolute path to the cloned repo.
- **Plugin-bundled:** depend on `agiterra/mcp-tee#v0.1.0` from a plugin's `package.json` and call `node_modules/@agiterra/mcp-tee/bin/mcp-tee.sh`.

## License

MIT.
