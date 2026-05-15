#!/bin/bash
# export-to-live.sh — Sync repository HEAD to live filesystem
# Idempotent, tracks applied commit in ~/.paperclip/sync-state.json

set -euo pipefail

DRY_RUN="${1:---}"
if [[ "$DRY_RUN" != "--dry-run" ]]; then
  DRY_RUN=false
else
  DRY_RUN=true
fi

# Manifest: repo path → live path
declare -A MANIFEST=(
  # Scripts
  ["scripts/export-to-live.sh"]="~/.paperclip/sync/export-to-live.sh"
  ["scripts/audit-drift.sh"]="~/.paperclip/sync/audit-drift.sh"

  # Configs (add more as needed)
  # ["path/in/repo"]="path/in/live"
)

REPO_HEAD=$(git rev-parse HEAD)
STATE_FILE="${HOME}/.paperclip/sync-state.json"
SYNC_DIR="${HOME}/.paperclip/sync"

if [[ "$DRY_RUN" == true ]]; then
  echo "=== DRY RUN MODE ==="
  echo "Would sync HEAD: $REPO_HEAD"
  echo ""
fi

mkdir -p "$SYNC_DIR" "$(dirname "$STATE_FILE")"

# Check if already synced
if [[ -f "$STATE_FILE" ]]; then
  LAST_SHA=$(jq -r '.last_applied_sha' "$STATE_FILE" 2>/dev/null || echo "")
  if [[ "$LAST_SHA" == "$REPO_HEAD" ]]; then
    echo "Already in sync at $REPO_HEAD (last synced at $(jq -r '.last_applied_at' "$STATE_FILE"))"
    exit 0
  fi
fi

# Sync files
synced_files=()
for repo_path in "${!MANIFEST[@]}"; do
  live_path="${MANIFEST[$repo_path]}"
  live_path="${live_path/\~/$HOME}"

  if [[ ! -f "$repo_path" ]]; then
    echo "ERROR: Source file not found: $repo_path" >&2
    exit 1
  fi

  echo "Syncing: $repo_path → $live_path"

  if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$(dirname "$live_path")"
    cp "$repo_path" "$live_path"
    chmod +x "$live_path" 2>/dev/null || true
    synced_files+=("$repo_path")
  fi
done

if [[ "$DRY_RUN" == false ]]; then
  # Write state
  STATE=$(cat <<EOF
{
  "last_applied_sha": "$REPO_HEAD",
  "last_applied_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "synced_files": [$(printf '"%s"' "${synced_files[@]}" | sed 's/"/\",\"/g')],
  "synced_count": ${#synced_files[@]}
}
EOF
  )
  echo "$STATE" > "$STATE_FILE"
  echo ""
  echo "✓ Sync complete ($(date))"
  echo "State written to $STATE_FILE"
else
  echo ""
  echo "DRY RUN complete. Would sync ${#MANIFEST[@]} files."
fi
