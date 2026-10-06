#!/usr/bin/env bash
# Runs a bpftrace script from this directory against an instrumented
# binary and prints the results with span names instead of numeric IDs.
#
#   Tools/bpf/run.sh spans.bt .build/release/kpbench probe-check --iterations 50
#
# Needs root (or CAP_BPF and CAP_PERFMON) and bpftrace 0.20 or newer.
set -euo pipefail

if (($# < 2)); then
  echo "usage: $0 <script.bt> <binary> [arguments...]" >&2
  exit 2
fi

# bpftrace needs tracefs for uprobes and room to lock BPF maps in memory.
if [[ ! -e /sys/kernel/tracing/uprobe_events ]]; then
  mount -t tracefs nodev /sys/kernel/tracing 2>/dev/null || true
fi
ulimit -l unlimited 2>/dev/null || ulimit -l 8192 2>/dev/null || true

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/$1"
binary="$(readlink -f "$2")"
shift 2

# Map "id<TAB>name" lines from `kpbench spans` into a sed program that
# rewrites the first map key ("@name[3" or "@name[3,") to the span name.
kpbench="$(dirname "$binary")/kpbench"
sed_program="$(mktemp)"
trap 'rm -f "$sed_program"' EXIT
"$kpbench" spans | while IFS=$'\t' read -r id name; do
  printf 's/^\\(@[a-z_]*\\)\\[%s\\([],]\\)/\\1[%s\\2/\n' "$id" "$name"
done >"$sed_program"

bpftrace "$script" "$binary" -c "$binary $*" | grep -v "^$" | sed -f "$sed_program"
