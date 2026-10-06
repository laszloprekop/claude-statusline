#!/usr/bin/env bash
# Runs statusline.sh against invented input and compares the text (colors and icons
# stripped) with what is expected. Usage: tests/run.sh
cd "$(dirname "$0")/.." || exit 1
STATE=$(mktemp -d); trap 'rm -rf "$STATE"' EXIT
T=2000000000; RESET=$((T + 10800)); FAILED=0

# plain <json> <now>: the two lines, without colors, icons and repeated spaces
plain() {
  echo "$1" | STATUSLINE_STATE="$STATE" STATUSLINE_NOW="$2" bash statusline.sh \
    | sed $'s/\x1b\\[[0-9;]*m//g' | LC_ALL=C sed $'s/\xee[\x80-\xbf][\x80-\xbf]//g; s/\xef[\x80-\xa3][\x80-\xbf]//g' \
    | tr -s ' ' | sed 's/^ //; s/ $//'
}
check() { # check <name> <actual> <expected substring>
  case "$2" in
    *"$3"*) echo "ok   $1" ;;
    *) echo "FAIL $1"; echo "       expected to contain: $3"; echo "       got: $2"; FAILED=1 ;;
  esac
}
json() { # json <session> <prompt> <cost> <5h percent or ""> [extra fields]
  local limits=""
  [ -n "$4" ] && limits=',"rate_limits":{"five_hour":{"used_percentage":'$4',"resets_at":'$RESET'},"seven_day":{"used_percentage":91}}'
  echo '{"session_id":"'$1'","prompt_id":"'$2'","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"workspace":{"current_dir":"/"},"cost":{"total_cost_usd":'$3',"total_duration_ms":3725000},"context_window":{"used_percentage":42.7}'"$limits${5:-}"'}'
}

# --- line 1
OUT=$(plain '{"model":{"id":"claude-haiku-4-5","display_name":"Haiku 4.5"},"workspace":{"current_dir":"/"}}' $T)
check "minimal input" "$OUT" "Haiku 4.5 1x"
OUT=$(plain "$(json a p1 0 "" ',"effort":{"level":"high"},"fast_mode":true,"pr":{"number":42,"review_state":"changes_requested"}')" $T)
check "fast mode doubles the weight" "$OUT" "Opus 5.5 8x ▂▄▅▇█"
check "pull request" "$OUT" "#42 changes requested"
OUT=$(plain '{"model":{"id":"brand-new","display_name":"Mystery"},"workspace":{"current_dir":"/"}}' $T)
check "unknown model has no weight" "$OUT" "Mystery /"

# --- line 2
OUT=$(plain "$(json a p1 0 "")" $T)
check "context bar and session time" "$OUT" "████░░░░░░ 42%"
check "session time over an hour" "$OUT" "1h 02m"
OUT=$(plain "$(json b p1 5 6)" $T)
check "before calibration: account average" "$OUT" "3.0%/h …"
check "limits" "$OUT" "6% $(date -r $RESET +%H:%M 2>/dev/null || date -d @$RESET +%H:%M) 91%"
for c in 5.50 5.48 5.52 5.49; do plain "$(json b p1 $c 6)" $((T + 60)) >/dev/null; done
check "small dips in the total are ignored" "$(cut -f4 "$STATE/sessions/b" | head -1)" "0.520000"
OUT=$(plain "$(json b p1 6 8)" $((T + 300)))
check "two points gained: rough burn rate and turn" "$OUT" "~12%/h ~2.0%"
OUT=$(plain "$(json b p2 6.5 11)" $((T + 360)))
check "five points gained, new prompt" "$OUT" "30%/h 1.7%"
plain "$(json b p3 0.30 11)" $((T + 400)) >/dev/null
check "a drop to near zero counts as a reset" "$(cut -f4 "$STATE/sessions/b" | head -1)" "1.800000"
OUT=$(plain "$(json a p1 0 "" ',"prompt_cache":{"caching_observed":true,"warm":false,"recache_tokens_if_cold":152020}')" $T)
check "cold cache shows the re-store size" "$OUT" "152k"

[ "$FAILED" = 0 ] && echo "all passed"
exit $FAILED
