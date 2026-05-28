#!/usr/bin/env bash
#
# mcp-tee.sh — wrap an MCP server command so its stderr is teed to a logfile
# while preserving the original stderr stream the parent process captures.
#
# Usage: mcp-tee.sh <log-name> <command> [args...]
#
# Example .mcp.json entry:
#   {
#     "command": "/path/to/mcp-tee.sh",
#     "args": ["wire", "bun", "run", "--cwd", "${CLAUDE_PLUGIN_ROOT}", "--silent", "start"]
#   }
#
# Output: appends to $MCP_LOG_DIR/<log-name>.log (default ~/.wire/mcp-stderr/).
# Rotation: rename to <log-name>.log.1 if it exceeds $MCP_LOG_ROTATE_BYTES at
# startup (default 10MB). Single-generation, no daemon.
#
# Env knobs:
#   MCP_LOG_DIR             — output directory          (default ~/.wire/mcp-stderr)
#   MCP_LOG_ROTATE_BYTES    — rotate threshold in bytes (default 10485760 = 10MB)
#   MCP_TEE_DISABLE         — if "1", exec without teeing (escape hatch)

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "usage: $(basename "$0") <log-name> <command> [args...]" >&2
    exit 64
fi

name="$1"
shift

if [ "${MCP_TEE_DISABLE:-0}" = "1" ]; then
    exec "$@"
fi

log_dir="${MCP_LOG_DIR:-$HOME/.wire/mcp-stderr}"
mkdir -p "$log_dir"

log="$log_dir/$name.log"
rotate_bytes="${MCP_LOG_ROTATE_BYTES:-10485760}"

if [ -f "$log" ]; then
    # macOS uses -f%z, Linux uses -c%s; fall through to 0 if neither works.
    size=$(stat -f%z "$log" 2>/dev/null || stat -c%s "$log" 2>/dev/null || echo 0)
    if [ "$size" -gt "$rotate_bytes" ]; then
        mv -f "$log" "$log.1"
    fi
fi

exec "$@" 2> >(tee -a "$log" >&2)
