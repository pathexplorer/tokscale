#!/bin/bash
# Install Tokscale DeepSeek peak/off-peak pricing auto-switcher
#
# Two modes:
#   [1] Full install — all files at default locations (for new users / GitHub sharing)
#   [2] Workspace-only — use existing script at ~/mega/scripts/workspace/tokscale/tokscale-peak-pricing,
#                        create only base.json + systemd units pointing to it
#
# DeepSeek peak hours (UTC): 01:00–04:00 and 06:00–10:00
# During peak, all deepseek-* model prices are multiplied by 2.
#
# Disable:  systemctl --user stop tokscale-peak-pricing.timer && systemctl --user disable tokscale-peak-pricing.timer
# Re-enable: systemctl --user enable --now tokscale-peak-pricing.timer
#
# Edit models:  ~/.config/tokscale/custom-pricing.base.json

set -euo pipefail

# --- Color helpers -----------------------------------------------------------

RESET='\033[0m'
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'

info()  { echo -e "${GREEN}[ok]${RESET} $1"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $1"; }

# --- Prerequisites -----------------------------------------------------------

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it first:"
  echo "  sudo apt install jq   # Debian/Ubuntu"
  echo "  sudo pacman -S jq     # Arch"
  echo "  brew install jq       # macOS"
  exit 1
fi

# --- Mode selection ----------------------------------------------------------

echo ""
echo -e "${BOLD}=== Tokscale Peak Pricing Installer ===${RESET}"
echo ""
echo "  [1] Full install — creates everything at default locations"
echo "      (~/.local/bin/tokscale-peak-pricing, systemd units, base.json)"
echo ""
echo "  [2] Workspace-only — use script at ~/$USER/mega/scripts/workspace/tokscale/tokscale-peak-pricing,"
echo "      create only base.json + systemd units"
echo ""
read -r -p "Choose [1/2]: " mode
echo ""

case "$mode" in
  2)
    MODE="workspace"
    WORKSPACE_SCRIPT="$HOME/mega/scripts/workspace/tokscale/tokscale-peak-pricing"
    if [ ! -f "$WORKSPACE_SCRIPT" ]; then
      echo "Error: workspace script not found at $WORKSPACE_SCRIPT"
      echo "Create it first or choose option 1 for a full install."
      exit 1
    fi
    echo -e "Selected workspace mode: ${BOLD}$WORKSPACE_SCRIPT${RESET}"
    ;;
  *)
    MODE="full"
    echo -e "Selected full install mode"
    ;;
esac
echo ""

# --- Directories -------------------------------------------------------------

mkdir -p "$HOME/.config/tokscale"
mkdir -p "$HOME/.config/systemd/user"

if [ "$MODE" = "full" ]; then
  mkdir -p "$HOME/.local/bin"
fi

# --- custom-pricing.base.json ------------------------------------------------

BASE_FILE="$HOME/.config/tokscale/custom-pricing.base.json"

if [ -f "$BASE_FILE" ]; then
  echo -e "${YELLOW}$BASE_FILE already exists.${RESET}"
  read -r -p "Overwrite? [y/N] " overwrite
  if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
    echo "Skipping base.json (keeping existing file)."
    echo ""
  else
    # Fall through to create below
    :
  fi
fi

# Create base.json if it doesn't exist or user chose to overwrite
if [ ! -f "$BASE_FILE" ] || { [ -f "$BASE_FILE" ] && [ "$overwrite" = "y" ] || [ "$overwrite" = "Y" ]; } 2>/dev/null; then
  cat > "$BASE_FILE" << 'BASEJSON'
{
  "$schema": "https://tokscale.ai/custom-pricing.schema.json",
  "models": {
    "mistral/mistral-small-latest": {
      "input_cost_per_million_tokens": 0.15,
      "output_cost_per_million_tokens": 0.60,
      "cache_read_input_token_cost_per_million_tokens": 0.015,
      "source": "https://mistral.ai/pricing",
      "notes": "Mistral Small 4"
    },
    "deepseek-v4-flash": {
      "input_cost_per_million_tokens": 0.14,
      "output_cost_per_million_tokens": 0.28,
      "cache_read_input_token_cost_per_million_tokens": 0.0028,
      "source": "https://api-docs.deepseek.com/quick_start/pricing/",
      "notes": "DeepSeek V4 Flash"
    },
    "deepseek-v4-pro": {
      "input_cost_per_million_tokens": 0.435,
      "output_cost_per_million_tokens": 0.87,
      "cache_read_input_token_cost_per_million_tokens": 0.0036251,
      "source": "https://api-docs.deepseek.com/quick_start/pricing/",
      "notes": "DeepSeek V4 Pro"
    }
  }
}
BASEJSON
  info "$BASE_FILE"
fi

# --- tokscale-peak-pricing script (full mode only) ---------------------------

if [ "$MODE" = "full" ]; then
  cat > "$HOME/.local/bin/tokscale-peak-pricing" << 'SCRIPT'
#!/bin/bash
# Tokscale peak/off-peak pricing switcher for DeepSeek
#
# Checks current UTC hour against DeepSeek peak windows (01:00-04:00, 06:00-10:00).
# During peak: multiplies all deepseek-* model prices by 2 in custom-pricing.json.
# During off-peak: restores base prices from custom-pricing.base.json.
# Only writes to disk (and restarts Tokscale) when the zone actually changes.

set -euo pipefail

BASE_FILE="$HOME/.config/tokscale/custom-pricing.base.json"
OUTPUT_FILE="$HOME/.config/tokscale/custom-pricing.json"
ZONE_FILE="/tmp/tokscale-pricing-zone"

current_hour=$(date -u +%H)
current_hour=$((10#$current_hour))

if { [ "$current_hour" -ge 1 ] && [ "$current_hour" -lt 4 ]; } || \
   { [ "$current_hour" -ge 6 ] && [ "$current_hour" -lt 10 ]; }; then
  zone="peak"
else
  zone="off-peak"
fi

if [ -f "$ZONE_FILE" ] && [ "$(cat "$ZONE_FILE")" = "$zone" ]; then
  exit 0
fi

echo "$zone" > "$ZONE_FILE"

if [ "$zone" = "peak" ]; then
  jq '
    .models |= with_entries(
      if .key | startswith("deepseek")
      then .value |= (
        .input_cost_per_million_tokens *= 2 |
        .output_cost_per_million_tokens *= 2 |
        .cache_read_input_token_cost_per_million_tokens *= 2
      )
      else .
      end
    )
  ' "$BASE_FILE" > "$OUTPUT_FILE.tmp"
  mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
else
  cp "$BASE_FILE" "$OUTPUT_FILE"
fi

if command -v notify-send &>/dev/null; then
  notify-send -t 5000 "Tokscale Pricing" "Switched to $zone pricing for DeepSeek models"
fi

pkill -f "@tokscale/cli-linux-x64-gnu/bin/tokscale" 2>/dev/null || true
SCRIPT
  chmod +x "$HOME/.local/bin/tokscale-peak-pricing"
  info "$HOME/.local/bin/tokscale-peak-pricing"
  SCRIPT_PATH="%h/.local/bin/tokscale-peak-pricing"
else
  SCRIPT_PATH="%h/mega/scripts/workspace/tokscale/tokscale-peak-pricing"
  info "Using existing script at $WORKSPACE_SCRIPT"
fi

# --- systemd units -----------------------------------------------------------

cat > "$HOME/.config/systemd/user/tokscale-peak-pricing.service" << SERVICE
[Unit]
Description=Update Tokscale custom pricing for DeepSeek peak hours

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
SERVICE
info "$HOME/.config/systemd/user/tokscale-peak-pricing.service"

cat > "$HOME/.config/systemd/user/tokscale-peak-pricing.timer" << 'TIMER'
[Unit]
Description=Switch Tokscale pricing at DeepSeek peak/off-peak transitions

# Fires at peak transition boundaries (UTC):
#   01:00 UTC → peak starts    (04:00 EEST)
#   04:00 UTC → off-peak       (07:00 EEST)
#   06:00 UTC → peak starts    (09:00 EEST)
#   10:00 UTC → off-peak       (13:00 EEST)
[Timer]
OnCalendar=*-*-* 01,04,06,10:00:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
TIMER
info "$HOME/.config/systemd/user/tokscale-peak-pricing.timer"

# --- Enable and start --------------------------------------------------------

systemctl --user daemon-reload
systemctl --user enable tokscale-peak-pricing.timer
systemctl --user start tokscale-peak-pricing.timer

echo ""
echo -e "${BOLD}=== Installation complete ===${RESET}"
echo ""
echo "Timer is active. Next triggers:"
systemctl --user status tokscale-peak-pricing.timer --no-pager 2>&1 | grep Trigger
echo ""
echo "To disable (before DeepSeek pricing actually starts):"
echo "  systemctl --user stop tokscale-peak-pricing.timer && systemctl --user disable tokscale-peak-pricing.timer"
echo ""
echo "To re-enable later:"
echo "  systemctl --user enable --now tokscale-peak-pricing.timer"
echo ""
echo "To add/edit models, edit:  $BASE_FILE"
echo "Any model key starting with 'deepseek' is auto-doubled during peak."
