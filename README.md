# Skynet Paperclip Repository

One-way sync of Paperclip configuration and scripts from this repository to
live operational environments.

## Overview

This repository is the single source of truth for:

- Operational scripts (sync, audit, drift detection)
- Deployment manifests and configurations
- Automation rules and triggers

Changes made here flow **one-way to production** via the sync scripts below.

## Quick start

### Clone the repo

```bash
git clone https://github.com/ArtificialJerome/skynet-paperclip.git
cd skynet-paperclip
```

### Run the sync script locally

```bash
./scripts/export-to-live.sh [--dry-run]
```

This reads the current `HEAD` of the repo and writes tracked files to their
mapped live locations (see manifest in `scripts/export-to-live.sh`).

### Check for drift

```bash
./scripts/audit-drift.sh
```

Compares your live environment against the last-applied repo commit. Exits
non-zero if drift is detected.

## How to propose changes

1. **Create a branch** and make your changes
2. **Open a PR** (no direct pushes to `main`)
3. **Wait for approval** from `@ArtificialJerome` (see `CODEOWNERS`)
4. **Merge** using squash-merge for clean history

See `CONTRIBUTING.md` for detailed guidelines.

## Sync model

```text
Repository (main branch)
    ↓
    export-to-live.sh
    ↓
Live filesystem (~/.paperclip, /etc/skynet, etc.)
```

The sync script is **idempotent** and tracks the applied commit in `~/.paperclip/sync-state.json`.

### Sync state

After each successful sync, `~/.paperclip/sync-state.json` stores:

- Last applied commit SHA
- Timestamp of last sync
- Files that were synced

### Dry-run

Before running in production:

```bash
./scripts/export-to-live.sh --dry-run
```

Shows what would be written without making changes.

## Troubleshooting

### Script fails

1. Run with `--dry-run` to see what's failing
2. Check that all paths in the manifest are accessible
3. Verify file permissions (must have write access to target locations)

### Drift detected

Run `audit-drift.sh` to see what's changed, then:

- Either `export-to-live.sh` to bring live back in sync
- Or open an issue if the drift is intentional

## Files in this repo

| Path | Purpose |
|---|---|
| `.github/workflows/ci.yml` | Automated checks (linting, secret scanning) |
| `.github/CODEOWNERS` | Review requirements |
| `CONTRIBUTING.md` | How to contribute |
| `scripts/export-to-live.sh` | Sync repo to live |
| `scripts/audit-drift.sh` | Detect drift |

## Support

Questions? Open an issue or contact Jerome.
