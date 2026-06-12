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
# Output: appends to $MCP_LOG_DIR/<log-name>.log (default ~/.wire/mcp-stderr/),
# each line stamped "<ISO-time> [<server-pid>:<AGENT_ID or ?>] <line>" plus a
# "=== start: <command> ===" header per server start. The stream the parent
# captures stays byte-identical — stamping is file-copy only.
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

# Stamp every logged line with time + server pid + agent id so the shared,
# fleet-wide log file stays attributable (the raw tee stream had no way to
# tell sessions apart — that cost two RCAs on 2026-06-12). The ORIGINAL
# stderr stream stays byte-identical: stamping happens only on the file copy.
# perl, not awk/date: BSD awk lacks strftime, date-per-line forks a process
# per line; perl line-buffers both sinks. $$ expands before exec replaces the
# shell, so the tag pid IS the server's pid. Agent id comes from AGENT_ID in
# the server's env (all agiterra plugins carry it), '?' when absent.
exec "$@" 2> >(perl -MPOSIX -we '
  my ($log, $tag, $cmd) = @ARGV; @ARGV = ();
  open my $fh, ">>", $log or die "mcp-tee: cannot open $log: $!";
  select((select($fh), $| = 1)[0]);
  $| = 1;
  my $ts = sub { strftime("%Y-%m-%dT%H:%M:%S%z", localtime) };
  print $fh $ts->() . " [$tag] === start: $cmd ===\n";
  while (<STDIN>) {
    print STDERR $_;
    print $fh $ts->() . " [$tag] " . $_;
  }
' "$log" "$$:${AGENT_ID:-?}" "$*")
