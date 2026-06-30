# Tokscale Utils — DeepSeek Peak Pricing & Tmux Dashboard

Scripts for Tokscale usage tracking with automatic DeepSeek peak/off-peak pricing
and an opencode + Tokscale tmux dashboard.

## Files

### `tokscale-peak-pricing`

Pricing switcher triggered by systemd timer at UTC 01:00 / 04:00 / 06:00 / 10:00.

Usage:
- `tokscale-peak-pricing` — normal mode: check UTC hour, switch zone
- `tokscale-peak-pricing disable` — restore base prices, kill Tokscale, clean zone

- Reads `~/.config/tokscale/custom-pricing.base.json` (base prices)
- During peak (UTC 01:00–04:00, 06:00–10:00): doubles all `deepseek-*` model prices
  and writes to `custom-pricing.json`
- During off-peak: copies base file as-is
- Kills running Tokscale processes so the next launch picks up fresh pricing
- Tracks current zone in `/tmp/tokscale-pricing-zone` to avoid redundant writes

### `install-tokscale-peak-pricing.sh`

Installation script with two interactive modes:

- **[1] Full install** — creates everything at default paths
  (`~/.local/bin/tokscale-peak-pricing`, `tokscale-loop`, `opencode_tokscale.sh`,
  `disable-tokscale-peak-pricing.sh`, systemd units, base.json)
- **[2] Workspace-only** — uses this workspace copy of the scripts,
  creates only base.json + systemd units pointing here

Checks for existing `base.json` and prompts before overwriting.
After installation, offers to add alias `optk` to your shell rc file
(auto-detects bash/zsh/fish from `$SHELL`).

Usage: `bash install-tokscale-peak-pricing.sh`

Targets Linux with systemd. Requires: jq, tmux, tokscale, opencode.

### `disable-tokscale-peak-pricing.sh`

One-command disable: stops the systemd timer, restores base prices to
`custom-pricing.json`, removes the zone tracking file, and kills running
Tokscale processes. Use when DeepSeek cancels peak pricing.

Usage: `bash disable-tokscale-peak-pricing.sh`

### `opencode_tokscale.sh`

Creates a 3-pane tmux dashboard:

```
┌──────────────────────┬──────────────┐
│                      │  tokscale    │
│     opencode         │  TUI pane   │
│                      ├──────────────┤
│                      │  bash shell  │
└──────────────────────┴──────────────┘
```

- Left pane (wide): opencode
- Right pane split horizontally: Tokscale TUI (top), bash (bottom)
- Tokscale TUI auto-restarts if killed (e.g., by pricing script)

### `tokscale-loop`

Wrapper that runs `tokscale tui --today -c opencode` in a loop.
If Tokscale exits with a non-zero/non-130 code (e.g., killed by the pricing script),
it restarts after 0.5s. This keeps the TUI alive across pricing zone transitions.

---

## Quick Start

```bash
# Install the pricing auto-switcher
bash install-tokscale-peak-pricing.sh

# Launch the tmux dashboard
bash opencode_tokscale.sh
```

## Disable / Re-enable Pricing Timer

```bash
# Disable completely (timer + restore base prices)
bash disable-tokscale-peak-pricing.sh

# Re-enable
systemctl --user enable --now tokscale-peak-pricing.timer
```

## Add / Edit Models

Edit `~/.config/tokscale/custom-pricing.base.json` — any model key starting with
`deepseek` is automatically doubled during peak hours.
