#!/bin/bash
# Disable Tokscale peak pricing: stop timer, restore base prices, clean up
#
# Usage: bash disable-tokscale-peak-pricing.sh

set -euo pipefail

echo "Stopping and disabling peak pricing timer..."
systemctl --user stop tokscale-peak-pricing.timer 2>/dev/null || true
systemctl --user disable tokscale-peak-pricing.timer 2>/dev/null || true

echo "Restoring base prices..."
tokscale-peak-pricing disable

echo ""
echo "Done. Peak pricing is fully disabled."
echo "  - Timer stopped and disabled"
echo "  - Base prices restored to custom-pricing.json"
echo "  - Zone tracking file removed"
echo ""
echo "To re-enable later: systemctl --user enable --now tokscale-peak-pricing.timer"
