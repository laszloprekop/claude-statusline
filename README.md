# claude-statusline

A two-line status line for [Claude Code](https://code.claude.com), written for people on a
Pro or Max subscription: it shows how fast a session uses the 5-hour budget. When tokens are
paid for one by one (an API key, or extra usage after the limit), it shows dollars instead.

![The status line in Ghostty](docs/screenshot.png)

## What it shows

Line 1, left to right:

| Part | Meaning |
|---|---|
| `Opus 5.5` | The model. |
| `4x` | Model weight: the model's list price per token against Haiku 4.5, the cheapest model. Haiku 4.5 is 1x, Sonnet 5.5 2x, Opus 5.5 4x, Opus 5 5x, Fable 5.1 10x. Fast mode doubles it. Yellow from 3x, red from 8x. |
| Five rising blocks | Effort. The blocks up to the current level (low, medium, high, xhigh, max) are lit, the rest are faded. A bolt follows when fast mode is on. |
| Folder | The current folder. |
| Branch | The git branch, then `+n` staged files (green) and `~n` modified files (yellow). |
| Pull request | Number and review state of the branch's open pull request, colored by state. |

Line 2, left to right:

| Part | Meaning |
|---|---|
| Bar and percent | How full the context window is. Yellow from 70%, red from 90%. |
| Fire, `12%/h` | Burn rate: this session's last 10 minutes, as percent of the 5-hour budget per hour. Yellow from 10, red from 20 (20%/h empties a full budget within the window). |
| Speech bubble, `0.9%` | What the current turn (everything since your last prompt) took from the 5-hour budget. Yellow from 2%, red from 5% (20 such turns empty the budget). |
| Tray with arrow out, `22%` | Output share: the part of the turn's cost spent on thinking and writing. This is the most that a lower effort could save. The rest is input, which shrinks with `/compact` or `/clear`. |
| Clock | Session time. |
| Hourglass | Percent of the 5-hour limit used, and the time left until it resets. Yellow from 70%, red from 90%. |
| Calendar | Percent of the 7-day limit used. Same colors. |
| `$`, `$314/$500` | Spend against a spend limit, when a Claude apps gateway sets one. |
| Database | The time left until the prompt cache goes cold. Once cold, a snowflake and the number of tokens the next message has to store again. |

Every part after the folder is left out when Claude Code does not send its data.

## Colors: what to change when a session burns fast

A number in the plain text color is normal. Yellow is high, red is very high. Icons and the
bar are green when normal.

The percentages are parts of your own budget, so the colors follow the plan without the
script knowing it: the same turn is a larger percent on Pro than on Max, and turns red sooner.

When the turn (speech bubble) is yellow or red, its color is passed on to the part that
caused most of it:

| What is colored | What it means | What lowers it |
|---|---|---|
| Output share | Half or more of the turn was thinking and writing. | A lower effort, or a narrower request. |
| Context percent, with a calmer bar | Most of the turn was input: the conversation re-read at every step. | `/compact`, `/clear`, or fewer large files and tool results. |
| Model weight | Every token costs this many times a Haiku token. | A lighter model for the task. |

## Paid tokens

Claude Code sends no 5-hour limit with an API key, on Bedrock or Vertex, or behind a gateway.
A subscriber is in the same position once the 5-hour limit reaches 100% and work goes on with
extra usage. A percent of the budget means nothing then, so the fire and the speech bubble
switch to dollars at list price, followed by the session total:

```
 $3.20/h   $0.42  Σ $4.10
```

Colors: the rate is yellow from $5/h and red from $15/h, the turn yellow from $0.50 and red
from $2. Set your own in the `statusLine` command, as "high, very high":

```json
"command": "STATUSLINE_USD_HOUR='10 30' STATUSLINE_USD_TURN='1 4' bash ~/.claude/statusline.sh"
```

The dollars are Claude Code's own estimate, not the bill.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/laszloprekop/claude-statusline/main/install.sh | bash
```

This downloads `statusline.sh` to `~/.claude/` and sets `statusLine` in
`~/.claude/settings.json`. The previous settings are kept as `settings.json.bak-statusline`.

By hand: save `statusline.sh` anywhere and add this to `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/statusline.sh",
  "refreshInterval": 30
}
```

`refreshInterval` runs the script every 30 seconds as well as on every update, so the two
countdowns (limit reset, cache) keep moving while the session is idle.

To remove it, delete the `statusLine` entry, the script and `~/.claude/statusline-state/`.

## Requirements

- `bash` (3.2 or later), `jq`, `git`, `awk`.
- A [Nerd Font](https://www.nerdfonts.com) for the icons. Ghostty has the icons built in.
  Without one, the icons show as empty boxes and the text still reads correctly.
- macOS. The script is written to run on Linux too, but that has not been tested.
- The limit figures (hourglass, calendar, burn rate in percent) need a claude.ai Pro or Max
  subscription. Without one, see [Paid tokens](#paid-tokens).

## How the burn rate works

Claude Code reports the 5-hour limit as a whole percent for the whole account. That is too
coarse for one turn and it mixes all sessions. So the script calibrates:

1. Every session's status line records how much that session has spent, using Claude Code's
   list-price cost estimate as a hidden unit.
2. When the account's percentage rises, the script divides what all sessions on the machine
   spent by the points gained. The result is "cost per 1%".
3. Each session's own spending is converted to percent with that value.

What you see while it learns:

- `2.6%/h …` (faded): nothing learned yet. This is the whole account's average over the
  current window. It lasts until the 5-hour percentage has risen by 2 points.
- `~12%/h`: a rough value, measured over fewer than 5 points.
- `12%/h`: measured over 5 points or more. The value is kept between windows.

State lives in `~/.claude/statusline-state/`. Session files idle for two days are removed.

## Limits

- The calibration is an estimate, not Anthropic's accounting. It assumes the limit counts
  tokens in about the same proportions as the price list.
- Usage the script cannot see (Claude on another machine, claude.ai, the phone app) raises
  the percentage without any recorded spending, which makes local sessions look more
  expensive than they are.
- The model weight is a price ratio, not a published limit ratio. The table in the script
  was read from the [pricing page](https://platform.claude.com/docs/en/about-claude/pricing)
  on 2026-10-06 and has to be updated by hand.
- Effort has no multiplier: it does not change the price of a token, only how many tokens
  the model writes. The output share is the measured effect.
- Subagents are not part of the output share.
- A subscriber sees dollars for a moment at the start of a session and after a window ends,
  until the next response brings the limit data back.
- Without `refreshInterval`, the status line only runs when the conversation updates, so
  the two countdowns stand still while the session is idle.

## Tests

```sh
tests/run.sh
```

Runs the script against invented input and compares the text.

## License

MIT
