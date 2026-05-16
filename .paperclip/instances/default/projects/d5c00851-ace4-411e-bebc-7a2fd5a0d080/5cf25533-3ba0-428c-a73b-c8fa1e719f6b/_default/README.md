# Paperclip Installer

Run your own Paperclip instance on macOS or Windows in one command.

## Prerequisites

- **Claude Max subscription** — required for AI agent authentication
- **8 GB RAM** minimum
- **Internet connection**
- macOS 12 (Monterey) or later / Windows 10 or 11

---

## Quick Download (one-click)

> **Easiest option — no terminal required.**

| Platform | Download | Notes |
|---|---|---|
| macOS | [install.command](https://github.com/ArtificialJerome/skynet-paperclip/releases/latest) | Double-click in Finder (right-click → Open on first run) |
| Windows | [install.bat + install.ps1](https://github.com/ArtificialJerome/skynet-paperclip/releases/latest) | Download both to the same folder, double-click install.bat |

Or open the installer page: [paperclip-installer landing page](https://artificialjerome.github.io/paperclip-installer)

---

## Terminal install

### macOS

```bash
curl -fsSL https://github.com/ArtificialJerome/skynet-paperclip/releases/latest/download/install.sh | bash
```

### Windows

Open PowerShell **as Administrator**, then run:

```powershell
irm https://github.com/ArtificialJerome/skynet-paperclip/releases/latest/download/install.ps1 | iex
```

---

## What the installer does

The script runs 9 steps, all idempotent (safe to re-run):

1. Checks your OS version and architecture
2. Installs **Docker Desktop** (downloads the correct build if missing)
3. Installs **Node.js** via nvm (macOS) or winget (Windows)
4. Installs the **Claude Code CLI** (`npm install -g @anthropic-ai/claude-code`)
5. Opens a browser for **Claude Max account sign-in** (OAuth)
6. Configures **phone / remote access** — see below
7. Creates `~/paperclip/` with a generated config and `docker-compose.yml`
8. Starts Paperclip with `docker compose up -d`
9. Prints your access URL and management commands

The whole process takes 5–15 minutes depending on your internet speed.

---

## Accessing Paperclip from your phone

The installer automatically picks the best method:

| Condition | Method | How to connect from phone |
|---|---|---|
| NordVPN is installed | **NordVPN Meshnet** — `http://<hostname>.nord:3100` | Install NordVPN on your phone, enable Meshnet, open the URL |
| NordVPN not found | **Tailscale Funnel** — `https://<machine>.ts.net` | No app needed — open the HTTPS URL in any browser |

The exact URL is printed at the end of the install. You can also find it by running the installer again (it will skip steps already complete) or by checking `tailscale status`.

---

## Stop and start Paperclip

```bash
cd ~/paperclip

# Stop
docker compose down

# Start
docker compose up -d

# View logs
docker compose logs -f
```

On Windows, replace `~/paperclip` with `%USERPROFILE%\paperclip`.

---

## Update

```bash
cd ~/paperclip
docker compose pull
docker compose up -d
```

This pulls the latest `ghcr.io/paperclipai/paperclip:latest` image and restarts the container. Active sessions will be briefly interrupted during the restart.

---

## Troubleshooting

**Docker won't start**
Open Docker Desktop manually and wait for the whale icon to appear in your menu bar / system tray. Then run `docker compose up -d` from `~/paperclip`.

**Claude auth errors**
Re-run `claude auth login` in your terminal. Make sure you sign in with the account that has an active **Claude Max** subscription.

**Tailscale Funnel URL not working**
1. Run `tailscale status` — confirm your device is connected.
2. Check that Funnel is enabled for your account at [login.tailscale.com/admin/dns](https://login.tailscale.com/admin/dns) → HTTPS Certificates / Funnel.
3. Re-run `tailscale funnel 3100` if the URL is missing.

**NordVPN Meshnet device not visible on phone**
Make sure both your computer and phone are logged in to **the same NordVPN account** and Meshnet is enabled in the NordVPN app on both devices.

**Port conflict on 3100**
Edit `~/paperclip/.env`, change `PAPERCLIP_PORT` to an unused port, then restart: `docker compose up -d`.

---

## Data location

All Paperclip data lives in `~/paperclip/` on your host machine — it is never inside the container. Docker bind mounts keep your data safe across image updates.
