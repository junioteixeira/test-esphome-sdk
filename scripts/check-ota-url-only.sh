#!/usr/bin/env bash
#
# check-ota-url-only.sh — an OTA download sends no credentials, and its url reaches no log.
#
# THE INVARIANT (README "Updating over the air"): the platform's `ota` command carries a url whose
# query string holds a single-use ticket, and the platform answers that url with a redirect to blob
# storage. Two things break it, and neither shows up in `esphome config` or in a compile:
#
#   (a) Credentials on the flash action. `ota.http_request.flash` with `username:`/`password:` sends
#       HTTP Basic auth, and ESP-IDF 5.5.1 re-sends that Authorization header across the redirect.
#       The storage service rejects any request that carries one, so every update fails with
#       "OTA update error 18" and nothing on the device says why.
#   (b) A log tag left open. ESPHome 2026.9.1 prints a failing request's url under `http_request`
#       and the OTA url under `http_request.ota` at INFO. The platform ingests device logs, so an
#       open tag turns the ticket into a credential stored server-side. modules/ota.yaml must pin
#       `http_request: NONE` and set an `http_request.ota` level.
#
# Usage:
#   check-ota-url-only.sh [ROOT]     # scan ROOT/modules and ROOT/hardware (default: repo root)
#   check-ota-url-only.sh --self-test
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# (a) Print `file:line` for every username:/password: key nested under an ota.http_request.flash
# action. The action's block is every following line indented deeper than the action key.
_flash_credentials() {
  awk '
    function indent(s){ match(s, /^ */); return RLENGTH }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*-?[[:space:]]*ota\.http_request\.flash:/ {
      inflash = 1; base = indent($0); next
    }
    inflash {
      if ($0 ~ /^[[:space:]]*$/) next
      if (indent($0) <= base) { inflash = 0 }
      else if ($0 ~ /^[[:space:]]*["'\'']?(username|password)["'\'']?[[:space:]]*:/) {
        print FILENAME ":" FNR ": " $0
      }
    }
  ' "$@"
}

check_root() {
  local root="$1" rc=0 files=() f hits
  local d
  for d in modules hardware; do
    [ -d "$root/$d" ] || continue
    while IFS= read -r -d '' f; do files+=("$f"); done \
      < <(find "$root/$d" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z)
  done

  if [ "${#files[@]}" -gt 0 ]; then
    hits="$(_flash_credentials "${files[@]}")"
    if [ -n "$hits" ]; then
      echo "check-ota-url-only: FAIL — ota.http_request.flash carries credentials; the url must carry the ticket:"
      printf '  %s\n' "$hits"
      rc=1
    fi
  fi

  local ota="$root/modules/ota.yaml"
  if [ -f "$ota" ]; then
    if ! grep -qE '^[[:space:]]+http_request:[[:space:]]*NONE[[:space:]]*(#.*)?$' "$ota"; then
      echo "check-ota-url-only: FAIL — ${ota}: logger logs must pin 'http_request: NONE'"
      rc=1
    fi
    if ! grep -qE '^[[:space:]]+http_request\.ota:[[:space:]]*[^[:space:]]' "$ota"; then
      echo "check-ota-url-only: FAIL — ${ota}: logger logs must set a level for 'http_request.ota'"
      rc=1
    fi
  fi

  [ "$rc" -eq 0 ] && echo "check-ota-url-only: ok — no flash action sends credentials, and both url-logging tags are pinned"
  return "$rc"
}

# ── self-test ─────────────────────────────────────────────────────────────────────────────────

_expect() {
  local want="$1" root="$2" label="$3"
  if check_root "$root" >/dev/null 2>&1; then
    [ "$want" = pass ] && echo "self-test: PASS — ${label}" || { echo "self-test: FAILED — ${label} (expected FAIL, got pass)"; return 1; }
  else
    [ "$want" = fail ] && echo "self-test: PASS — ${label}" || { echo "self-test: FAILED — ${label} (expected pass, got FAIL)"; return 1; }
  fi
}

_ota_fixture() {
  local dir="$1" logs="$2" flash_extra="$3"
  mkdir -p "$dir/modules"
  {
    echo "logger:"
    echo "  logs:"
    printf '%s\n' "$logs"
    echo "script:"
    echo "  - id: script_ota_from_command"
    echo "    then:"
    echo "      - ota.http_request.flash:"
    echo "          url: !lambda 'return url;'"
    echo "          md5: !lambda 'return md5;'"
    [ -n "$flash_extra" ] && printf '%s\n' "$flash_extra"
    echo "  - id: script_rollback"
    echo "    then:"
    echo "      - lambda: |-"
    echo "          password: not-a-key-of-the-flash-action"
  } >"$dir/modules/ota.yaml"
}

self_test() {
  local tmp rc=0
  tmp="$(mktemp -d)"
  local logs_ok=$'    http_request: NONE\n    http_request.ota: WARN'

  _ota_fixture "$tmp/good" "$logs_ok" ""
  _expect pass "$tmp/good" "url-only flash action and both tags pinned" || rc=1

  _ota_fixture "$tmp/basic" "$logs_ok" $'          username: !lambda \'return device_id;\'\n          password: !lambda \'return ticket;\''
  _expect fail "$tmp/basic" "flash action with username/password is rejected" || rc=1

  _ota_fixture "$tmp/pwonly" "$logs_ok" $'          "password": !lambda \'return ticket;\''
  _expect fail "$tmp/pwonly" "a quoted password key alone is rejected" || rc=1

  _ota_fixture "$tmp/opentag" $'    http_request.ota: WARN' ""
  _expect fail "$tmp/opentag" "http_request tag not pinned to NONE is rejected" || rc=1

  _ota_fixture "$tmp/debugtag" $'    http_request: DEBUG\n    http_request.ota: WARN' ""
  _expect fail "$tmp/debugtag" "http_request at DEBUG is rejected" || rc=1

  _ota_fixture "$tmp/noota" $'    http_request: NONE' ""
  _expect fail "$tmp/noota" "missing http_request.ota level is rejected" || rc=1

  mkdir -p "$tmp/hw/hardware"
  _ota_fixture "$tmp/hw" "$logs_ok" ""
  printf '%s\n' "script:" "  - id: x" "    then:" "      - ota.http_request.flash:" \
    "          url: https://example.invalid/fw.bin" "          password: s" >"$tmp/hw/hardware/board.yaml"
  _expect fail "$tmp/hw" "a hardware file's flash action with a password is rejected" || rc=1

  rm -rf "$tmp"
  return "$rc"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

check_root "${1:-$SCRIPT_DIR/..}"
