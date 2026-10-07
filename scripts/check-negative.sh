#!/usr/bin/env bash
#
# check-negative.sh — assert every negative fixture FAILS `esphome config`.
#
# tests/negative/ holds configs that each omit exactly one required substitution. The substitution
# contract says a missing required input (especially a credential) must fail validation LOUDLY — a
# default in a public repo is a default password in every device that forgot to override it. This
# gate proves that enforcement: it runs `esphome config` over every negative fixture and fails if
# ANY of them succeeds (a success means a required input silently gained a default — a regression).
#
# The passing fixtures live in tests/validate/ and are checked by validate.yml's own
# `esphome config` step; this script only ever runs the MUST-FAIL fixtures.
#
# A fixture must also fail WITHOUT reaching the network. Its includes pass `sdk_ref: local-test`,
# which no remote has, so any git fetch it starts — an `external_components` source in a module it
# imports — fails on its own, and the fixture "fails as required" whatever the rule it was written
# for now says. A fixture that logs a clone is therefore reported, not accepted.
#
# Usage:
#   check-negative.sh [ROOT]     # run over ROOT/tests/negative (default: repo root)
#   check-negative.sh --self-test
#
# The esphome binary is taken from $ESPHOME (default: `esphome` on PATH).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ESPHOME_BIN="${ESPHOME:-esphome}"

# Run `esphome config` on one file with an isolated, disposable data dir so the check never dirties
# the working tree. Returns 0 when it passed, 2 when it failed after starting a git clone (ESPHome
# logs "Cloning <url>" before every one, git.py in 2026.5.1 and 2026.9.1), 1 when it failed
# otherwise.
_esphome_config() {
  local file="$1" data_dir out rc
  data_dir="$(mktemp -d)"
  out="$(ESPHOME_DATA_DIR="$data_dir" "$ESPHOME_BIN" config "$file" 2>&1)"
  rc=$?
  rm -rf "$data_dir"
  [ "$rc" -eq 0 ] && return 0
  grep -q 'Cloning ' <<<"$out" && return 2
  return 1
}

# Assert every *.yaml under $dir fails `esphome config`. Prints one line per fixture and returns
# non-zero if any fixture unexpectedly SUCCEEDED (or if the directory holds no fixtures).
scan_dir() {
  local dir="$1" rc=0 found=0 f
  [ -d "$dir" ] || { echo "check-negative: no directory $dir"; return 1; }
  while IFS= read -r -d '' f; do
    found=1
    _esphome_config "$f"
    case $? in
      0) echo "check-negative: FAIL — $f passed esphome config but a negative fixture MUST fail"
         rc=1 ;;
      2) echo "check-negative: FAIL — $f fetched over git before failing, so it may be failing on the fetch"
         rc=1 ;;
      *) echo "check-negative: ok — $f failed as required" ;;
    esac
  done < <(find "$dir" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z)
  if [ "$found" -eq 0 ]; then
    echo "check-negative: no negative fixtures found in $dir"
    return 1
  fi
  return "$rc"
}

self_test() {
  local tmp rc=0
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/tests/negative"

  # A fixture that MUST fail: references an undefined substitution. scan_dir must report it as ok.
  cat >"$tmp/tests/negative/bad.yaml" <<'YAML'
esphome:
  name: neg-selftest
esp32:
  board: esp32dev
  framework:
    type: arduino
logger:
  level: ${undefined_substitution}
YAML
  if scan_dir "$tmp/tests/negative" >/dev/null 2>&1; then
    echo "self-test: PASS — a genuinely-failing fixture is accepted as a negative"
  else
    echo "self-test: FAILED — a genuinely-failing fixture was not accepted"; rc=1
  fi

  # Add a fixture that SUCCEEDS (nothing missing). scan_dir must now report a violation, proving the
  # harness catches a negative fixture that stopped failing (a contract regression).
  cat >"$tmp/tests/negative/wrongly_passes.yaml" <<'YAML'
esphome:
  name: neg-selftest-ok
esp32:
  board: esp32dev
  framework:
    type: arduino
YAML
  if scan_dir "$tmp/tests/negative" >/dev/null 2>&1; then
    echo "self-test: FAILED — a passing fixture was NOT flagged as a violation"; rc=1
  else
    echo "self-test: PASS — a passing fixture is correctly flagged as a violation"
  fi

  # Replace the passing fixture with one that fails only because its git source cannot be fetched.
  # scan_dir must flag it: it would fail whatever the rule under test says.
  rm -f "$tmp/tests/negative/wrongly_passes.yaml"
  cat >"$tmp/tests/negative/fails_on_fetch.yaml" <<'YAML'
esphome:
  name: neg-selftest-fetch
esp32:
  board: esp32dev
  framework:
    type: arduino
external_components:
  - source:
      type: git
      url: https://127.0.0.1:9/unreachable.git
      ref: local-test
    components: [unreachable]
YAML
  if scan_dir "$tmp/tests/negative" >/dev/null 2>&1; then
    echo "self-test: FAILED — a fixture failing on a git fetch was NOT flagged"; rc=1
  else
    echo "self-test: PASS — a fixture failing on a git fetch is correctly flagged"
  fi

  rm -rf "$tmp"
  return "$rc"
}

main() {
  case "${1:-}" in
    --self-test) self_test ;;
    "" ) scan_dir "$(dirname "$SCRIPT_DIR")/tests/negative" ;;
    *  ) scan_dir "$1/tests/negative" ;;
  esac
}

main "$@"
