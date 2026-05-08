#!/bin/bash
# audit-drift.sh — Detect drift between live filesystem and last-applied repo commit
# Exits non-zero if drift is detected

set -euo pipefail

STATE_FILE="${HOME}/.paperclip/sync-state.json"
SYNC_DIR="${HOME}/.paperclip/sync"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "ERROR: No sync state found at $STATE_FILE" >&2
  echo "Run 'export-to-live.sh' first to establish baseline" >&2
  exit 1
fi

LAST_SHA=$(jq -r '.last_applied_sha' "$STATE_FILE")
LAST_FILES=$(jq -r '.synced_files[]' "$STATE_FILE")

echo "Checking drift against last applied SHA: $LAST_SHA"
echo ""

has_drift=0

for repo_path in $LAST_FILES; do
  if [[ ! -f "$repo_path" ]]; then
    echo "DRIFT: File removed from repo: $repo_path"
    has_drift=1
    continue
  fi

  # Check if file was modified since sync
  repo_hash=$(sha256sum < "$repo_path" 2>/dev/null || echo "")
  live_path="${SYNC_DIR}/$(basename "$repo_path")"

  if [[ ! -f "$live_path" ]]; then
    echo "DRIFT: Live file missing: $live_path"
    has_drift=1
    continue
  fi

  live_hash=$(sha256sum < "$live_path" 2>/dev/null || echo "")

  if [[ "$repo_hash" != "$live_hash" ]]; then
    echo "DRIFT: File modified in live or repo: $repo_path"
    has_drift=1
  fi
done

echo ""
if [[ $has_drift -eq 0 ]]; then
  echo "✓ No drift detected. Live is in sync with repo HEAD."
  exit 0
else
  echo "✗ Drift detected. Run 'export-to-live.sh' to resync, or investigate changes."
  exit 1
fi
