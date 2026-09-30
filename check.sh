#!/usr/bin/env bash
# Smoke test for the "Markov text generator" homework (hw-markov.md).
#
# Usage:
#   bash check.sh [PROJECT_DIR]
#
#   PROJECT_DIR   folder with gen.py (default: current directory)
#   PYTHON        interpreter to use (default: python3)
#
# Install the requirements before you run this script. The source text is alice.txt next to
# this script. Every check prints PASS or FAIL. The homework is accepted when all checks pass.
# The project is copied to a temporary folder, so your own .env is not touched.
#
# A failed check prints the command it ran and the first lines of stdout and stderr. The full
# output of every failed check is saved in check-logs/ in the folder you run this script from.

set -u

PROJECT=${1:-.}
PYTHON=${PYTHON:-python3}
TEXT=$(cd "$(dirname "$0")" && pwd)/alice.txt
START=the                         # the most frequent word of alice.txt
HERE=$PWD; LOGS=$HERE/check-logs

[ -f "$TEXT" ] || { echo "alice.txt not found next to check.sh" >&2; exit 2; }
[ -f "$PROJECT/gen.py" ] || { echo "gen.py not found in $PROJECT" >&2; exit 2; }
command -v "$PYTHON" >/dev/null || { echo "interpreter not found: $PYTHON" >&2; exit 2; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/project"
find "$PROJECT" -mindepth 1 -maxdepth 1 ! -name venv ! -name .venv ! -name .git ! -name check-logs \
  -exec cp -r {} "$WORK/project/" \;
cd "$WORK/project" || exit 2
rm -f .env
rm -rf "$LOGS"
out=$WORK/out; err=$WORK/err; out2=$WORK/out2

T=""; command -v timeout >/dev/null && T="timeout 10"   # a hanging program must not hang the check
PASSED=0; FAILED=0; hint=""; last_cmd=""

# run ARGS...: run gen.py with stdin from $IN. Keeps stdout in $out, stderr in $err, exit code
# in $rc and the command line in $cmd. IN=/dev/null run ... gives the program no input.
IN=$TEXT
run() {
  cmd="$PYTHON gen.py $* < $([ "$IN" = "$TEXT" ] && echo alice.txt || echo "$IN")"
  for v in GEN_LINES GEN_WIDTH GEN_SEED; do [ -n "${!v+x}" ] && cmd="$v=${!v} $cmd"; done
  [ -f .env ] && cmd="$cmd    (.env: $(tr '\n' ' ' < .env))"
  $T "$PYTHON" gen.py "$@" <"$IN" >"$out" 2>"$err"; rc=$?
}
lines() { wc -l < "$1" | tr -d ' '; }

# show LABEL FILE: print the first lines of FILE, prefixed with LABEL.
show() {
  local n; n=$(lines "$2")
  if [ ! -s "$2" ]; then echo "      $1 | (empty)"; return; fi
  head -5 "$2" | cut -c1-120 | sed "s/^/      $1 | /"
  [ "$n" -gt 5 ] && echo "      $1 | ... $((n-5)) more lines"
}

# expect NAME COMMAND...: PASS when COMMAND succeeds, FAIL with details of the last run otherwise.
# Set $hint before expect to add one line of advice to a failure.
expect() {
  local name=$1; shift
  if "$@"; then
    echo "PASS  $name"; PASSED=$((PASSED+1))
  else
    FAILED=$((FAILED+1))
    local slug dir
    slug=$(echo "$name" | tr -c 'A-Za-z0-9\n' '-' | tr -s '-' | cut -c1-40 | sed 's/-$//')
    dir=$LOGS/$(printf '%02d' $((PASSED+FAILED)))-$slug
    mkdir -p "$dir"; cp "$out" "$dir/stdout"; cp "$err" "$dir/stderr"; echo "$cmd" > "$dir/command"
    echo "FAIL  $name"
    if [ "$cmd" = "$last_cmd" ]; then
      echo "      same run as the failed check above"
    else
      echo "      command: $cmd"
      echo "      exit code $rc, stdout $(lines "$out") lines, stderr $(lines "$err") lines"
      show stdout "$out"; show stderr "$err"
    fi
    [ -n "$hint" ] && echo "      hint: $hint"
    echo "      full output: ${dir#"$HERE"/}"
    last_cmd=$cmd
  fi
  hint=""
}

# Conditions that do not fit into one test(1) call.
help_lists_every_option() {
  [ $rc -eq 0 ] || return 1
  for word in --lines --width --seed --verbose --show-config START; do grep -qi -- "$word" "$out" || return 1; done
}
# output_has LINES WIDTH: exactly LINES lines, each starts with START and has at most WIDTH words.
output_has() { awk -v n="$1" -v w="$2" -v s=$START 'NF < 1 || $1 != s || NF > w { bad = 1 } END { exit bad || NR != n }' "$out"; }
differ() { ! cmp -s "$1" "$2"; }
pairs_from_text() {
  "$PYTHON" - "$TEXT" "$out" <<'PY'
import sys
source = open(sys.argv[1]).read().split()
pairs = set(zip(source, source[1:]))
for line in open(sys.argv[2]):
    words = line.split()
    if any(p not in pairs for p in zip(words, words[1:])):
        sys.exit(1)
PY
}
# shows_config "NAME VALUE SOURCE"...: for every triple, some stdout line contains all three
# as separate words. Case and punctuation do not matter: "lines=4 (env)", "LINES: 4 [env]"
# and "lines = 4, source: env" all pass. ".env" and "env" are different words.
shows_config() {
  for want in "$@"; do
    awk -v want="$want" '
      BEGIN { n = split(want, w, " ") }
      { line = tolower($0); gsub(/[^a-z0-9.]+/, " ", line); gsub(/\.+ /, " ", line); line = " " line " "
        for (i = 1; i <= n; i++) if (!index(line, " " w[i] " ")) next
        found = 1 }
      END { exit !found }' "$out" || return 1
  done
}

# --- help and usage errors --------------------------------------------------
run --help
expect "--help exits 0 and lists every option"      help_lists_every_option
run --lines 2
expect "missing START: exit 2, empty stdout"         test $rc -eq 2 -a ! -s "$out"
IN=/dev/null run --bogus $START
expect "unknown option: exit 2, empty stdout"        test $rc -eq 2 -a ! -s "$out"
run --width 0 $START
expect "--width 0: exit 2, empty stdout"             test $rc -eq 2 -a ! -s "$out"

# --- runtime errors ---------------------------------------------------------
run --lines 2 zzqxjvnotaword
expect "START not in text: exit 1, message in stderr" test $rc -eq 1 -a ! -s "$out" -a -s "$err"
IN=/dev/null run --lines 2 $START
expect "empty stdin: exit 1, message in stderr"      test $rc -eq 1 -a ! -s "$out" -a -s "$err"

# --- generation -------------------------------------------------------------
run --lines 5 --width 8 --seed 1 $START
expect "successful run: exit 0"                           test $rc -eq 0
expect "--lines 5 --width 8: exactly 5 lines, each starts with START and has at most 8 words" output_has 5 8
expect "model statistics go to stderr"               test -s "$err"
expect "every adjacent pair in the output occurs in the text" pairs_from_text

run --lines 20 --seed 7 $START; cp "$out" "$out2"
run --lines 20 --seed 7 $START
hint="sets of strings iterate in a different order on every run; use a list or a Counter"
expect "same seed gives the same output"             cmp -s "$out" "$out2"
run --lines 20 --seed 8 $START
expect "different seed gives different output"       differ "$out" "$out2"

run --lines 200 --width 2 --seed 3 $START
n=$(awk 'NF >= 2 { print $2 }' "$out" | sort -u | wc -l | tr -d ' ')
expect "next word is a weighted random choice, not the most frequent one" test "$n" -ge 2

cmd="$PYTHON gen.py $START < alice.txt 2>/dev/null | head -3"
$T "$PYTHON" gen.py $START <"$TEXT" 2>"$err" | head -3 >"$out"; rc=$?
hint="print every line as soon as it is generated; the program stops when head closes the pipe"
expect "--lines 0 (default) is infinite: gen.py | head -3 prints 3 lines" test "$(lines "$out")" = 3

run --lines 20000 --verbose $START
expect "--verbose: one stderr line for every stdout line (20000 lines)" test $rc -eq 0 -a "$(lines "$out")" = 20000 -a "$(lines "$err")" -ge 20000

# --- env, .env, precedence --------------------------------------------------
GEN_LINES=4 run $START
expect "GEN_LINES environment variable sets --lines"                   test "$(lines "$out")" = 4

printf 'GEN_LINES=6\nGEN_WIDTH=3\n' > .env
run $START
expect ".env file sets GEN_LINES and GEN_WIDTH"       output_has 6 3
GEN_LINES=4 run $START
expect "env variable overrides .env"                 test "$(lines "$out")" = 4
GEN_LINES=4 run --lines 2 $START
expect "option overrides env variable"               test "$(lines "$out")" = 2
GEN_LINES=4 IN=/dev/null run --seed 5 --show-config $START
hint="expected: lines=4 (env), width=3 (.env), seed=5 (cli); punctuation and case are up to you"
expect "--show-config prints every setting with its value and source" shows_config 'lines 4 env' 'width 3 .env' 'seed 5 cli'
rm -f .env

IN=/dev/null run --show-config $START
hint="expected: lines=0 (default), width=10 (default), seed=none (default)"
expect "--show-config: lines=0, width=10, seed=none when nothing is set"                shows_config 'lines 0 default' 'width 10 default' 'seed none default'

# --- summary ----------------------------------------------------------------
echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] || echo "full output of every failed check: ${LOGS#"$HERE"/}/"
[ "$FAILED" -eq 0 ]
