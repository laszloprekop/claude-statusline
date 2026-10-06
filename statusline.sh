#!/usr/bin/env bash
# Claude Code status line: https://github.com/laszloprekop/claude-statusline
# Two lines, grown from the multi-line example in https://code.claude.com/docs/en/statusline
#   Model 4x ▂▄▅▇█     dir    branch +staged ~modified    #n state
#   ████░░░░░░ 42%    15%/h  0.3%  35%    24m    38%  21:40    12%    21:05
# Icons are Nerd Font glyphs (Ghostty has them built in), not emoji. Groups are separated
# by white space only. Every part after the folder is left out when its data is missing.

input=$(cat)

# One jq call; the unit separator keeps empty fields in place
IFS=$'\x1f' read -r MODEL DIR PCT DURATION_MS EFFORT FAST \
  FIVE_H FIVE_H_RESET WEEK PR_NUM PR_STATE PR_KIND \
  CACHE_SEEN CACHE_WARM CACHE_EXPIRES TRANSCRIPT \
  COST SESSION PROMPT CACHE_TTL RECACHE MODEL_ID < <(echo "$input" | jq -r '[
    .model.display_name // "Claude",
    .workspace.current_dir // .cwd // "",
    (.context_window.used_percentage // 0 | floor),
    (.cost.total_duration_ms // 0 | floor),
    .effort.level // "",
    (.fast_mode // false),
    (.rate_limits.five_hour.used_percentage // "" | if . == "" then . else round end),
    (.rate_limits.five_hour.resets_at // "" | if . == "" then . else floor end),
    (.rate_limits.seven_day.used_percentage // "" | if . == "" then . else round end),
    .pr.number // "",
    .pr.review_state // "",
    .pr.kind // "",
    (.prompt_cache.caching_observed // false),
    (.prompt_cache.warm // false),
    (.prompt_cache.expires_at // "" | if . == "" then . else floor end),
    .transcript_path // "",
    .cost.total_cost_usd // 0,
    .session_id // "",
    .prompt_id // "",
    .prompt_cache.ttl // "",
    (.prompt_cache.recache_tokens_if_cold // "" | if . == "" then . else floor end),
    .model.id // ""
  ] | map(tostring) | join("\u001f")')
[ -n "$PCT" ] || PCT=0
[ -n "$DURATION_MS" ] || DURATION_MS=0
NOW=${STATUSLINE_NOW:-$(date +%s)}

# The terminal theme's own colors, so the line follows Ghostty
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'
MAGENTA='\033[35m'; CYAN='\033[36m'; DIM='\033[2m'; RESET='\033[0m'
SEP='   '

# epoch seconds as local HH:MM (BSD date on macOS, GNU date on Linux)
clock() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M; }

# green under 70%, yellow 70-89%, red from 90%
level_color() {
  if [ "$1" -ge 90 ]; then printf '%s' "$RED"
  elif [ "$1" -ge 70 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"; fi
}

# --- line 1 ---------------------------------------------------------------

# Effort: all five steps, the ones above the current level faded
case "$EFFORT" in
  low) LIT=1 ;; medium) LIT=2 ;; high) LIT=3 ;; xhigh) LIT=4 ;; max) LIT=5 ;; *) LIT=0 ;;
esac
# Model weight: the model's list price per token against Haiku 4.5 (the cheapest), from
# https://platform.claude.com/docs/en/about-claude/pricing as of 2026-10-06. Output is 5
# times input on every model, so one number covers both. READ_W is the price of a cache
# read against a normal input token. Fast mode doubles the price.
WEIGHT=""; READ_W=0.1
case "$MODEL_ID" in
  *fable-5-1*|*mythos-5-1*) WEIGHT=10; READ_W=0.025 ;;
  *fable*|*mythos*) WEIGHT=10 ;;
  *opus-5-5*) WEIGHT=4; READ_W=0.05 ;;
  *opus-5*|*opus-4-[5-8]*) WEIGHT=5 ;;
  *sonnet-5*) WEIGHT=2 ;;
  *sonnet-4*) WEIGHT=3 ;;
  *haiku-4-5*) WEIGHT=1 ;;
esac
[ -n "$WEIGHT" ] && [ "$FAST" = "true" ] && WEIGHT=$((WEIGHT * 2))

STEPS=(▂ ▄ ▅ ▇ █)
HEAD="${CYAN}${MODEL}${RESET}"
[ -n "$WEIGHT" ] && HEAD="$HEAD ${YELLOW}${WEIGHT}x${RESET}"
if [ "$LIT" -gt 0 ]; then
  ON=""; OFF=""
  for i in 0 1 2 3 4; do
    if [ "$i" -lt "$LIT" ]; then ON="$ON${STEPS[$i]}"; else OFF="$OFF${STEPS[$i]}"; fi
  done
  HEAD="$HEAD ${CYAN}${ON}${RESET}${DIM}${CYAN}${OFF}${RESET}"
fi
[ "$FAST" = "true" ] && HEAD="$HEAD ${YELLOW}${RESET}"

NAME="${DIR##*/}"; [ -n "$NAME" ] || NAME="$DIR"
LINE1="$HEAD${SEP}${BLUE}${RESET} ${NAME}"

# Git branch and uncommitted changes (skip optional locks)
if [ -n "$DIR" ] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=$(git -C "$DIR" --no-optional-locks branch --show-current 2>/dev/null)
  STAGED=$(git -C "$DIR" --no-optional-locks diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  MODIFIED=$(git -C "$DIR" --no-optional-locks diff --numstat 2>/dev/null | wc -l | tr -d ' ')
  if [ -n "$BRANCH" ]; then
    LINE1="$LINE1${SEP}${MAGENTA}${RESET} $BRANCH"
    [ "$STAGED" -gt 0 ] && LINE1="$LINE1 ${GREEN}+${STAGED}${RESET}"
    [ "$MODIFIED" -gt 0 ] && LINE1="$LINE1 ${YELLOW}~${MODIFIED}${RESET}"
  fi
fi

if [ -n "$PR_NUM" ]; then
  case "$PR_STATE" in
    approved) PR_COLOR="$GREEN" ;;
    changes_requested) PR_COLOR="$RED" ;;
    pending) PR_COLOR="$YELLOW" ;;
    *) PR_COLOR="$DIM" ;;
  esac
  if [ "$PR_KIND" = "mr" ]; then PR_MARK='!'; else PR_MARK='#'; fi
  LINE1="$LINE1${SEP}${PR_COLOR}${RESET} ${PR_MARK}${PR_NUM}"
  [ -n "$PR_STATE" ] && LINE1="$LINE1 ${PR_COLOR}${PR_STATE//_/ }${RESET}"
fi

echo -e "$LINE1"

# --- line 2 ---------------------------------------------------------------

FILLED=$((PCT / 10)); [ "$FILLED" -gt 10 ] && FILLED=10
EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
LINE2="$(level_color "$PCT")${FILL// /█}${DIM}${PAD// /░}${RESET} ${PCT}%"

# Budget burn: how fast this session uses the 5-hour limit, and what the current turn took.
#    15%/h   this session's last 10 minutes, as percent of the 5-hour budget per hour
#    0.3%    the current turn (since the last prompt), as percent of that budget
# Claude Code only sends the limit as a whole percent for the whole account, so the script
# learns how much list-price cost equals one percent: it adds up what all sessions on this
# machine spent while the percentage rose. A "~" marks a still rough value, "…" none yet.
# State: sessions/<id> (line 1: prompt, turn base, last total, running sum; then "time sum"
# samples), window (reset time, percent and machine sum at first sight), factor ($ per 1%).
if [ -n "$SESSION" ]; then
  SD="${STATUSLINE_STATE:-$HOME/.claude/statusline-state}"; SF="$SD/sessions/$SESSION"
  mkdir -p "$SD/sessions" 2>/dev/null
  [ -e "$SF" ] || : > "$SF"
  read -r TURN_USD WIN_USD < <(awk -F'\t' -v now="$NOW" -v cost="$COST" -v prompt="$PROMPT" -v out="$SD/tmp.$$" '
    NR == 1 { sp = $1; base = $2; last = $3; cum = $4; have = 1; next }
    { split($0, a, " "); if (a[1] >= now - 600) { n++; ts[n] = a[1]; c[n] = a[2] } }
    END {
      if (!have) { sp = prompt; base = 0; last = cost; cum = 0 }
      # the reported total sometimes dips a little: ignore that and wait until it passes
      # the highest value seen; a drop to under half is a reset (/clear), so count afresh
      d = cost - last
      if (d < 0) { if (cost < last / 2) d = cost; else { d = 0; cost = last } }
      old = cum; cum += d
      if (prompt != sp) base = old              # a new prompt started
      first = (n > 0) ? c[1] : old
      printf "%s\t%.6f\t%.6f\t%.6f\n", prompt, base, cost, cum > out
      for (i = 1; i <= n; i++) print ts[i], c[i] > out
      if (n == 0 || now - ts[n] >= 10) printf "%d %.6f\n", now, cum > out
      printf "%.6f %.6f\n", cum - base, cum - first
    }' "$SF")
  mv -f "$SD/tmp.$$" "$SF" 2>/dev/null

  F_USD=""; F_PCT=""; F_RESET=""
  [ -r "$SD/factor" ] && read -r F_USD F_PCT F_RESET < "$SD/factor"
  if [ -n "$FIVE_H" ] && [ -n "$FIVE_H_RESET" ]; then
    SPENT=$(awk -F'\t' 'FNR == 1 { s += $4 } END { printf "%.6f", s }' "$SD"/sessions/* 2>/dev/null)
    W_RESET=""; W_PCT=""; W_SPENT=""
    [ -r "$SD/window" ] && read -r W_RESET W_PCT W_SPENT < "$SD/window"
    if [ "$W_RESET" != "$FIVE_H_RESET" ]; then
      # a new 5-hour window: start measuring from here, and drop sessions idle for 2 days
      find "$SD/sessions" -type f -mtime +2 -delete 2>/dev/null
      SPENT=$(awk -F'\t' 'FNR == 1 { s += $4 } END { printf "%.6f", s }' "$SD"/sessions/* 2>/dev/null)
      echo "$FIVE_H_RESET $FIVE_H $SPENT" > "$SD/window"
    else
      DPCT=$((FIVE_H - W_PCT))
      # trust a measurement over at least 2 points; a later window replaces the stored
      # value only once it is about as well measured (10 points at most)
      if [ "$DPCT" -ge 2 ]; then
        NEED=2
        if [ -n "$F_PCT" ]; then
          if [ "$F_RESET" = "$FIVE_H_RESET" ]; then NEED="$F_PCT"
          elif [ "$F_PCT" -lt 10 ]; then NEED="$F_PCT"; else NEED=10; fi
        fi
        if [ "$DPCT" -ge "$NEED" ]; then
          NEW=$(awk -v s="$SPENT" -v s0="$W_SPENT" -v d="$DPCT" 'BEGIN { f = (s - s0) / d; if (f > 0) printf "%.6f", f }')
          if [ -n "$NEW" ]; then
            echo "$NEW $DPCT $FIVE_H_RESET" > "$SD/factor"; F_USD="$NEW"; F_PCT="$DPCT"
          fi
        fi
      fi
    fi
  fi

  if [ -n "$F_USD" ]; then
    read -r RATE_FMT RATE_INT TURN_FMT < <(awk -v t="$TURN_USD" -v w="$WIN_USD" -v f="$F_USD" 'BEGIN {
      r = w * 6 / f; p = t / f
      printf (r < 10 ? "%.1f" : "%.0f"), r; printf " %d ", r; printf (p < 10 ? "%.1f" : "%.0f"), p }')
    # 20%/h empties a full 5-hour budget within the window
    if [ "$RATE_INT" -ge 20 ]; then FIRE_COLOR="$RED"
    elif [ "$RATE_INT" -ge 10 ]; then FIRE_COLOR="$YELLOW"
    elif [ "$RATE_FMT" = "0.0" ]; then FIRE_COLOR="$DIM"
    else FIRE_COLOR="$GREEN"; fi
    ROUGH=""; [ "$F_PCT" -lt 5 ] && ROUGH="~"
    LINE2="$LINE2${SEP}${FIRE_COLOR}${RESET} ${ROUGH}${RATE_FMT}%${DIM}/h${RESET} ${CYAN}${RESET} ${ROUGH}${TURN_FMT}%"
  elif [ -n "$FIVE_H" ] && [ -n "$FIVE_H_RESET" ]; then
    # nothing learned yet: the whole account's average over this window so far, faded,
    # with "…" to say the per-session figure is still being learned
    AVG=$(awk -v u="$FIVE_H" -v reset="$FIVE_H_RESET" -v now="$NOW" 'BEGIN {
      h = (now - (reset - 18000)) / 3600; if (h < 0.1) h = 0.1
      r = u / h; printf (r < 10 ? "%.1f" : "%.0f"), r }')
    LINE2="$LINE2${SEP}${DIM} ${AVG}%/h …${RESET}"
  else
    LINE2="$LINE2${SEP}${DIM} …${RESET}"
  fi
fi

# Output share (tray with arrow out): the part of the turn's cost spent on thinking and
# writing, which is what effort changes. The rest is input: the conversation being re-read
# plus new material, which a shorter conversation changes. Tokens since the last prompt, from the tail of the transcript,
# weighted as the price list does: output 5, input 1, cache write 2 (1h) or 1.25, cache read READ_W.
if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
  if [ "$CACHE_TTL" = "1h" ]; then WRITE_W=2; else WRITE_W=1.25; fi
  OUT_PCT=$(tail -n 500 "$TRANSCRIPT" 2>/dev/null | jq -rn --argjson w "$WRITE_W" --argjson r "$READ_W" '
    reduce (inputs | select(.isSidechain != true)) as $m ({};
      if $m.type == "user" and ($m.message.content | type) == "string" then {}
      elif $m.type == "assistant" and $m.message.usage != null
      then .[$m.message.id // $m.uuid] = $m.message.usage
      else . end)
    | [.[]]
    | ((map(.output_tokens // 0) | add // 0) * 5) as $out
    | (map((.input_tokens // 0) + (.cache_creation_input_tokens // 0) * $w
        + (.cache_read_input_tokens // 0) * $r) | add // 0) as $ctx
    | if $out + $ctx > 0 then ($out * 100 / ($out + $ctx) | round) else empty end' 2>/dev/null)
  if [ -n "$OUT_PCT" ]; then
    LINE2="$LINE2 ${MAGENTA}${RESET} ${OUT_PCT}%"
  fi
fi

# Session time
MINS=$((DURATION_MS / 60000))
if [ "$MINS" -ge 60 ]; then TIME_FMT="$((MINS / 60))h $(printf '%02d' $((MINS % 60)))m"
elif [ "$MINS" -ge 1 ]; then TIME_FMT="${MINS}m"
else TIME_FMT="$((DURATION_MS / 1000))s"; fi
LINE2="$LINE2${SEP}${CYAN}${RESET} $TIME_FMT"

# Usage limits (hourglass: 5-hour window, calendar: 7-day window): only sent to
# claude.ai subscribers, after the first response
if [ -n "$FIVE_H" ]; then
  LINE2="$LINE2${SEP}$(level_color "$FIVE_H")${RESET} ${FIVE_H}%"
  [ -n "$FIVE_H_RESET" ] && LINE2="$LINE2 ${DIM} $(clock "$FIVE_H_RESET")${RESET}"
fi
[ -n "$WEEK" ] && LINE2="$LINE2${SEP}$(level_color "$WEEK")${RESET} ${WEEK}%"

# Prompt cache: the time it goes cold, or a snowflake and the re-store size once it has
if [ "$CACHE_SEEN" = "true" ]; then
  if [ "$CACHE_WARM" = "true" ] && [ -n "$CACHE_EXPIRES" ] && [ "$CACHE_EXPIRES" -gt "$NOW" ]; then
    LINE2="$LINE2${SEP}${DIM} $(clock "$CACHE_EXPIRES")${RESET}"
  else
    # cold: the tokens the next message has to store again
    if [ -n "$RECACHE" ] && [ "$RECACHE" -ge 1000 ]; then COLD_FMT="$(( (RECACHE + 500) / 1000 ))k"
    else COLD_FMT="${RECACHE:-cold}"; fi
    LINE2="$LINE2${SEP}${BLUE}${RESET} ${COLD_FMT}"
  fi
fi

echo -e "$LINE2"
