#!/bin/bash
set -e

FACTORIO=${FACTORIO:-/opt/factorio/bin/x64/factorio}
WORKSPACE=${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}
# Every game launch goes through the wrapper, which gives this worktree a write-data
# directory of its own so runs from several worktrees don't lock each other out
RUN=$WORKSPACE/tests/factorio.sh
TEST_TIMEOUT=${FACTORIO_TEST_TIMEOUT:-30}

usage() {
  echo "Usage: bash tests/run.sh <save-create | suites | suite <name> [configuration] [case-filter]>"
  echo "The case filter is a Lua pattern matched against test names"
}

TEST=${1:-save-create}
SUITE=${2:-}
CONFIGURATION=${3:-}
CASES=${4:-}
case $TEST in
  save-create | suites) [ $# -le 1 ] || { usage; exit 2; } ;;
  suite)
    [ $# -ge 2 ] && [ $# -le 4 ] || { usage; exit 2; }
    [[ $SUITE =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] && [ -f "$WORKSPACE/tests/suites/$SUITE/suite.lua" ] \
      || { echo "Unknown suite: $SUITE"; exit 2; }
    ;;
  -h | --help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
FAILURE_DIR=""

RED=$'\033[31m'; GREEN=$'\033[32m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

# Preserve only failed logs; all mod copies and successful logs are removed on exit
preserve_log() {
  local logfile=$1 name=$2
  if [ -z "$FAILURE_DIR" ]; then
    FAILURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/factoryplanner-test-failures.XXXXXX")
  fi
  cp "$logfile" "$FAILURE_DIR/$name.log"
  echo "    Log: $FAILURE_DIR/$name.log"
}

# Quote CLI values as Lua strings, including patterns containing quotes or backslashes
lua_string() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  printf '"%s"' "$value"
}

count_label() {
  local count=$1 noun=$2
  [ "$count" -eq 1 ] || noun=${noun}s
  printf '%s %s' "$count" "$noun"
}

# Factorio owns the verdict; logs supply the readable report and failure diagnostics
run_game() {
  local name=$1
  shift
  local logfile=$TEST_TMP/run.log report=$TEST_TMP/report exit_code=0
  "$TIMEOUT" -k 5 "$TEST_TIMEOUT" "$RUN" "$@" > "$logfile" 2>&1 || exit_code=$?

  sed -n '/FPTEST_REPORT$/,/FPTEST_REPORT_END$/{/FPTEST_REPORT/!p;}' "$logfile" > "$report"
  sed "s/✓/${GREEN}✓${RESET}/; s/✗/${RED}✗${RESET}/" "$report"
  [ "$exit_code" -ne 0 ] || return 0

  local reason="game failed (exit $exit_code)"
  if [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 137 ]; then
    reason="game timed out after $TEST_TIMEOUT seconds"
  fi
  echo "  ${RED}✗${RESET} $reason [$name]"
  # Show engine diagnostics when the report doesn't explain the failure, or on timeout
  if ! grep -q '✗' "$report" || [ "$exit_code" -eq 124 ] || [ "$exit_code" -eq 137 ]; then
    tail -n 20 "$logfile" | sed 's/^/    | /'
  fi
  preserve_log "$logfile" "$name"
  return "$exit_code"
}

# All configurations in a suite use the same mod files, with new options for each launch
prepare_suite() {
  local suite_dir=$1 mods=$TEST_TMP/mods
  rm -rf "$mods" || return 1
  mkdir -p "$mods" || return 1
  cp -r "$WORKSPACE/modfiles" "$mods/factoryplanner" || return 1
  cp -r "$WORKSPACE/tests/mod" "$mods/factoryplanner-test" || return 1
  cp -r "$suite_dir" "$mods/factoryplanner-test/suite" || return 1
  # Pin the full mod set so runs don't depend on the installation's defaults
  cat > "$mods/mod-list.json" << EOF
{
    "mods": [
        { "name": "base", "enabled": true },
        { "name": "recycler", "enabled": true },
        { "name": "space-age", "enabled": false },
        { "name": "quality", "enabled": false },
        { "name": "elevated-rails", "enabled": false },
        { "name": "factoryplanner", "enabled": true },
        { "name": "factoryplanner-test", "enabled": true }
    ]
}
EOF
}

# RUN_* values are only metadata for summaries and configuration discovery
run_configuration() {
  local suite=$1 configuration=$2 cases=$3
  local mods=$TEST_TMP/mods logfile=$TEST_TMP/run.log exit_code=0
  RUN_PASSED=0
  RUN_CONFIGURATIONS=""
  {
    printf 'return {configuration='
    if [ -n "$configuration" ]; then lua_string "$configuration"; else printf 'nil'; fi
    printf ', filter='
    lua_string "$cases"
    printf '}\n'
  } > "$mods/factoryplanner-test/options.lua" || return 1

  run_game "$suite-${configuration:-first}" --mod-directory "$mods" \
    --test-scenario factoryplanner-test/tests || exit_code=$?

  RUN_CONFIGURATIONS=$(sed -n 's/^.*FPTEST_CONFIGURATION \([a-zA-Z0-9_-]*\)$/\1/p' "$logfile")
  RUN_PASSED=$(sed -n 's/^.*FPTEST_PASSED \([0-9][0-9]*\)$/\1/p' "$logfile" | tail -n 1)
  RUN_PASSED=${RUN_PASSED:-0}
  return "$exit_code"
}

run_suite() {
  local suite_dir=$1 configuration=${2:-} cases=${3:-}
  local suite=$(basename "$suite_dir")
  local passed=0 failed=0 count=1
  echo "${BOLD}$suite${RESET}"
  prepare_suite "$suite_dir" || return 1

  # The first configuration also provides the ordered list for the rest of the suite
  run_configuration "$suite" "$configuration" "$cases" || failed=$((failed + 1))
  passed=$RUN_PASSED
  local configurations=$RUN_CONFIGURATIONS
  if [ -z "$configuration" ]; then
    local next first=true
    for next in $configurations; do
      if [ "$first" = true ]; then first=false; continue; fi
      run_configuration "$suite" "$next" "$cases" || failed=$((failed + 1))
      passed=$((passed + RUN_PASSED))
      count=$((count + 1))
    done
  fi

  local summary="$passed passed · $(count_label "$count" configuration)"
  if [ "$failed" -gt 0 ]; then summary="$summary · $(count_label "$failed" configuration) failed"; fi
  echo "  $summary"
  [ "$failed" -eq 0 ]
}

# Run every suite, reporting all failures rather than stopping at the first
run_suites() {
  local suite_dir failed="" count=0
  for suite_dir in "$WORKSPACE"/tests/suites/*; do
    [ -f "$suite_dir/suite.lua" ] || continue
    run_suite "$suite_dir" || failed="$failed $(basename "$suite_dir")"
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || { echo "No suites found"; return 1; }
  if [ -n "$failed" ]; then
    echo "${RED}Failed suites:$failed${RESET}"
    return 1
  fi
  echo "${GREEN}All suites passed${RESET}"
}

TIMEOUT=$(command -v timeout || command -v gtimeout) \
  || { echo "Tests require timeout (install coreutils if unavailable)"; exit 1; }
[[ $TEST_TIMEOUT =~ ^[1-9][0-9]*$ ]] \
  || { echo "FACTORIO_TEST_TIMEOUT must be a positive number of seconds"; exit 2; }
if [ "$TEST" != save-create ]; then
  if ! "$FACTORIO" --help > "$TEST_TMP/help" 2>&1 || ! grep -q -- '--test-scenario' "$TEST_TMP/help"; then
    echo "Tests require Factorio with --test-scenario support (2.1.24 or newer)"
    exit 1
  fi
fi

case $TEST in
  save-create)
    mkdir -p "$TEST_TMP/mods"
    cp -r "$WORKSPACE/modfiles" "$TEST_TMP/mods/factoryplanner"
    run_game save-create --mod-directory "$TEST_TMP/mods" --create "$TEST_TMP/test-map.zip" || exit $?
    echo "${GREEN}✓${RESET} save-create: map created without errors"
    ;;
  suites) run_suites ;;
  suite) run_suite "$WORKSPACE/tests/suites/$SUITE" "$CONFIGURATION" "$CASES" ;;
esac
