#!/bin/sh
# CLI start-up benchmark (docs/benchmarks.md, "CLI start-up"). Median of 5
# wall-clock and user-CPU seconds for the commands an agent's edit-check-test
# loop repeats: check/run of a trivial program, check of a 60-line file with
# exploring tests, and its test run with an empty and with a warm result cache.
#   sh scripts/startup-bench.sh [path/to/jacquard]
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${TMPDIR:=$ROOT/.scratch/tmp}"
export TMPDIR
mkdir -p "$TMPDIR"
JAC=${1:-$ROOT/_build/default/bin/main.exe}
export JACQUARD_PRELUDE=${JACQUARD_PRELUDE:-$ROOT/prelude}
WORK=$(mktemp -d "$TMPDIR/startup-bench.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
printf 'main() = "hi"\n' > "$WORK/trivial.jac"
FIXTURE=$ROOT/bench/startup/transfer.jac

median() { sort -n | sed -n 3p; }
measure() {
  name=$1
  shift
  : > "$WORK/times"
  for _ in 1 2 3 4 5; do
    rm -rf "$WORK/cache"
    if [ "$name" = test-warm-cache ]; then "$JAC" "$@" > /dev/null 2>&1 || true; fi
    /usr/bin/time -o "$WORK/time" -f "%e %U" "$JAC" "$@" > /dev/null 2>&1 || true
    cat "$WORK/time" >> "$WORK/times"
  done
  printf '%-16s wall %ss  user %ss\n' "$name" \
    "$(cut -d' ' -f1 "$WORK/times" | median)" "$(cut -d' ' -f2 "$WORK/times" | median)"
}

measure check-trivial check "$WORK/trivial.jac"
measure run-trivial run "$WORK/trivial.jac"
measure check-fixture check "$FIXTURE"
measure test-cold test --cache-dir "$WORK/cache" "$FIXTURE"
measure test-warm-cache test --cache-dir "$WORK/cache" "$FIXTURE"
