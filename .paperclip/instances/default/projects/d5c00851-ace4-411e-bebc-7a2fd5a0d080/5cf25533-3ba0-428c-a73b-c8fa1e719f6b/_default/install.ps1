#Requires -Version 5.1
<#
.SYNOPSIS
    Zero-to-hero Paperclip bootstrap for Windows 10/11.
.DESCRIPTION
    Installs Docker Desktop, Node.js, Claude Code CLI, configures network
    access (NordVPN Meshnet or Tailscale Funnel), creates Paperclip data
    directories, and starts Paperclip via Docker Compose.

    Idempotent: safe to run multiple times on the same machine.
.NOTES
    Requires administrator privileges (Docker Desktop requires them).
    PowerShell 5.1+ (Windows 10/11 default).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

function Fail {
    param([string]$Message)
    Write-Host "`n[ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Test-CommandExists {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-DockerRunning {
    try {
        $null = docker info 2>$null
        return $true
    } catch {
        return $false
    }
}

function Refresh-Path {
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User')
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 1 — Elevation check
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Checking for administrator privileges"

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Info "This script requires administrator privileges. Relaunching as administrator..."
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    $psi.Verb = 'RunAs'
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        Fail "Could not relaunch as administrator. Right-click the script and choose 'Run as administrator'."
    }
    exit 0
}

Write-OK "Running as administrator"

# ─────────────────────────────────────────────────────────────────────────────
# Step 2 — Install Docker Desktop
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Checking for Docker Desktop"

$dockerDesktopPath = "$env:PROGRAMFILES\Docker\Docker\Docker Desktop.exe"
$dockerInstalled = Test-Path $dockerDesktopPath

if (-not $dockerInstalled) {
    Write-Info "Docker Desktop not found. Installing via winget..."

    # Try winget first (available on Windows 10 2004+ and Windows 11)
    if (Test-CommandExists 'winget') {
        try {
            winget install --id Docker.DockerDesktop --exact --accept-package-agreements --accept-source-agreements --silent
            Write-OK "Docker Desktop installed via winget"
            $dockerInstalled = $true
        } catch {
            Write-Info "winget install failed. Falling back to direct download..."
            $dockerInstalled = $false
        }
    }

    if (-not $dockerInstalled) {
        # Direct download fallback
        $installerUrl = 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe'
        $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"

        Write-Info "Downloading Docker Desktop installer (~600 MB)..."
        try {
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        } catch {
            Fail "Failed to download Docker Desktop installer: $_`nPlease install Docker Desktop manually from https://www.docker.com/products/docker-desktop/"
        }

        Write-Info "Running Docker Desktop installer (silent)..."
        $proc = Start-Process -FilePath $installerPath -ArgumentList 'install --quiet' -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Fail "Docker Desktop installer exited with code $($proc.ExitCode). Please install manually."
        }
        Write-OK "Docker Desktop installed via direct download"
    }
} else {
    Write-OK "Docker Desktop already installed"
}

# Add current user to docker-users group (idempotent)
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$dockerUsersGroup = Get-LocalGroup -Name 'docker-users' -ErrorAction SilentlyContinue
if ($dockerUsersGroup) {
    $members = Get-LocalGroupMember -Group 'docker-users' -ErrorAction SilentlyContinue
    $alreadyMember = $members | Where-Object { $_.Name -eq $currentUser }
    if (-not $alreadyMember) {
        try {
            Add-LocalGroupMember -Group 'docker-users' -Member $currentUser
            Write-OK "Added $currentUser to docker-users group"
        } catch {
            Write-Info "Could not add to docker-users group (may need manual step after install): $_"
        }
    } else {
        Write-OK "$currentUser is already in docker-users group"
    }
}

# Start Docker Desktop if not running
Write-Step "Waiting for Docker daemon to be ready"

if (-not (Test-DockerRunning)) {
    Write-Info "Starting Docker Desktop..."
    $dockerDesktopExe = "$env:PROGRAMFILES\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerDesktopExe) {
        Start-Process $dockerDesktopExe
    }

    $maxWaitSeconds = 120
    $waited = 0
    $ready = $false
    while ($waited -lt $maxWaitSeconds) {
        Start-Sleep -Seconds 5
        $waited += 5
        Write-Info "Waiting for Docker daemon... ($waited/$maxWaitSeconds s)"
        if (Test-DockerRunning) {
            $ready = $true
            break
        }
    }

    if (-not $ready) {
        Fail "Docker daemon did not start within $maxWaitSeconds seconds.`nPlease start Docker Desktop manually and re-run this script."
    }
}

Write-OK "Docker daemon is running"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3 — Install Node.js
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Checking for Node.js"

$nodeInstalled = Test-CommandExists 'node'

if (-not $nodeInstalled) {
    Write-Info "Node.js not found. Installing via winget (OpenJS.NodeJS.LTS)..."

    if (-not (Test-CommandExists 'winget')) {
        Fail "winget is not available. Please install Node.js manually from https://nodejs.org/ and re-run this script."
    }

    winget install --id OpenJS.NodeJS.LTS --exact --accept-package-agreements --accept-source-agreements --silent

    Refresh-Path

    if (-not (Test-CommandExists 'node')) {
        Fail "Node.js was installed but 'node' is not in PATH. Please open a new terminal and re-run this script."
    }

    Write-OK "Node.js installed: $(node --version)"
} else {
    Write-OK "Node.js already installed: $(node --version)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4 — Install Claude Code CLI
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Checking for Claude Code CLI"

$claudeInstalled = Test-CommandExists 'claude'

if (-not $claudeInstalled) {
    Write-Info "Installing Claude Code CLI via npm..."
    npm install -g @anthropic-ai/claude-code
    if ($LASTEXITCODE -ne 0) {
        Fail "npm install failed with exit code $LASTEXITCODE. Check your Node.js/npm installation."
    }

    Refresh-Path

    if (-not (Test-CommandExists 'claude')) {
        Fail "Claude Code CLI was installed but 'claude' is not in PATH. Please open a new terminal and re-run this script."
    }

    Write-OK "Claude Code CLI installed: $(claude --version)"
} else {
    Write-OK "Claude Code CLI already installed: $(claude --version)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — Claude authentication
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Claude authentication"

$claudeAuthed = $false
try {
    claude auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $claudeAuthed = $true }
} catch { }

if ($claudeAuthed) {
    Write-OK "Already authenticated with Claude"
} else {
    Write-Info "Opening browser for Claude OAuth login. Sign in with your Claude Max account."
    Write-Info "If the browser does not open automatically, check the terminal for a URL."
    claude auth login

    if ($LASTEXITCODE -ne 0) {
        Fail "Claude authentication failed (exit code $LASTEXITCODE). Please re-run the script and complete the browser login."
    }

    Write-OK "Claude authentication complete"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 6 — Network access: NordVPN Meshnet or Tailscale Funnel
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Configuring network access for phone/remote connections"

$accessUrl = $null

if ($env:PAPERCLIP_SKIP_NETWORK) {
    Write-Info "Skipping network setup (PAPERCLIP_SKIP_NETWORK is set) — Paperclip will be accessible on localhost only"
} elseif ((Test-Path "$env:PROGRAMFILES\NordVPN\nordvpn.exe") -or (Test-CommandExists 'nordvpn')) {
    Write-Info "NordVPN detected. Enabling Meshnet..."

    & nordvpn set meshnet on
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Warning: 'nordvpn set meshnet on' failed. Meshnet may already be enabled or NordVPN may need to be logged in."
    } else {
        Write-OK "NordVPN Meshnet enabled"
    }

    # Capture .nord hostname (device name in lowercase with .nord suffix)
    $hostname = $env:COMPUTERNAME.ToLower()
    $accessUrl = "http://$hostname.nord:3100"

    Write-Host "`n" -NoNewline
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "  │  NordVPN Meshnet Access                                     │" -ForegroundColor Yellow
    Write-Host "  │                                                             │" -ForegroundColor Yellow
    Write-Host "  │  Your Paperclip will be at:                                 │" -ForegroundColor Yellow
    Write-Host "  │    $accessUrl" -ForegroundColor Yellow
    Write-Host "  │                                                             │" -ForegroundColor Yellow
    Write-Host "  │  Phone requirements:                                        │" -ForegroundColor Yellow
    Write-Host "  │    1. Install NordVPN on your phone                         │" -ForegroundColor Yellow
    Write-Host "  │    2. Log in with the same NordVPN account                  │" -ForegroundColor Yellow
    Write-Host "  │    3. Enable Meshnet in NordVPN settings on your phone      │" -ForegroundColor Yellow
    Write-Host "  │    4. Open the URL above in your phone browser              │" -ForegroundColor Yellow
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow

} else {
    Write-Info "NordVPN not found. Installing Tailscale for remote access..."

    if (-not (Test-CommandExists 'winget')) {
        Fail "winget is required to install Tailscale. Please install Tailscale manually from https://tailscale.com/download and re-run."
    }

    $tailscaleInstalled = Test-CommandExists 'tailscale'
    if (-not $tailscaleInstalled) {
        winget install --id Tailscale.Tailscale --exact --accept-package-agreements --accept-source-agreements --silent

        Refresh-Path
    } else {
        Write-OK "Tailscale already installed"
    }

    if (-not (Test-CommandExists 'tailscale')) {
        Fail "Tailscale was installed but 'tailscale' is not in PATH. Please open a new terminal and re-run this script."
    }

    Write-Info "Connecting to Tailscale network (browser login may open)..."
    tailscale up
    if ($LASTEXITCODE -ne 0) {
        Fail "tailscale up failed with exit code $LASTEXITCODE. Please check your Tailscale installation."
    }

    Write-Info "Enabling Tailscale Funnel on port 3100..."
    tailscale funnel 3100
    if ($LASTEXITCODE -ne 0) {
        Fail "tailscale funnel failed with exit code $LASTEXITCODE.`nMake sure Funnel is enabled on your account at https://login.tailscale.com/admin/dns"
    }

    # Capture the HTTPS URL
    $tailscaleStatus = tailscale status --json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($tailscaleStatus -and $tailscaleStatus.Self -and $tailscaleStatus.Self.DNSName) {
        $tsHostname = $tailscaleStatus.Self.DNSName.TrimEnd('.')
        $accessUrl = "https://$tsHostname"
    } else {
        $accessUrl = "https://<your-machine>.ts.net  (run 'tailscale status' to confirm)"
    }

    Write-Host "`n" -NoNewline
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "  │  Tailscale Funnel Access                                    │" -ForegroundColor Cyan
    Write-Host "  │                                                             │" -ForegroundColor Cyan
    Write-Host "  │  Your Paperclip will be at:                                 │" -ForegroundColor Cyan
    Write-Host "  │    $accessUrl" -ForegroundColor Cyan
    Write-Host "  │                                                             │" -ForegroundColor Cyan
    Write-Host "  │  Phone requirements:                                        │" -ForegroundColor Cyan
    Write-Host "  │    • No app needed — just open the URL in your phone browser│" -ForegroundColor Cyan
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 7 — Create directory tree and write .env
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Setting up Paperclip data directories and configuration"

$paperclipRoot = Join-Path $env:USERPROFILE 'paperclip'
$dirs = @(
    $paperclipRoot,
    (Join-Path $paperclipRoot 'db'),
    (Join-Path $paperclipRoot 'storage'),
    (Join-Path $paperclipRoot 'secrets'),
    (Join-Path $paperclipRoot 'projects')
)

foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Info "Created: $dir"
    }
}

Write-OK "Directory tree ready at $paperclipRoot"

# Generate or preserve JWT secret (idempotent)
$envFile = Join-Path $paperclipRoot '.env'

if (Test-Path $envFile) {
    Write-OK ".env already exists — preserving existing configuration"
} else {
    # Generate a 64-character hex JWT secret using .NET crypto (no openssl needed on Windows)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 32
    $rng.GetBytes($bytes)
    $jwtSecret = [BitConverter]::ToString($bytes) -replace '-', ''
    $rng.Dispose()

    $publicUrl = if ($accessUrl) { $accessUrl } else { 'http://localhost:3100' }

    $envContent = @"
PAPERCLIP_PORT=3100
BETTER_AUTH_SECRET=$jwtSecret
PAPERCLIP_PUBLIC_URL=$publicUrl
HOST=0.0.0.0
PORT=3100
PAPERCLIP_HOME=/paperclip
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=private
"@

    Set-Content -Path $envFile -Value $envContent -Encoding UTF8
    Write-OK ".env written to $envFile"
}

# Write docker-compose.yml next to .env (idempotent)
$composeFile = Join-Path $paperclipRoot 'docker-compose.yml'

if (-not (Test-Path $composeFile)) {
    $composeContent = @'
services:
  paperclip:
    image: ghcr.io/paperclipai/paperclip:latest
    ports:
      - "${PAPERCLIP_PORT:-3100}:3100"
    volumes:
      - .:/paperclip
    env_file: .env
    restart: unless-stopped
'@
    Set-Content -Path $composeFile -Value $composeContent -Encoding UTF8
    Write-OK "docker-compose.yml written to $composeFile"
} else {
    Write-OK "docker-compose.yml already exists — preserving"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 8 — Start Paperclip
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Starting Paperclip via Docker Compose"

Push-Location $paperclipRoot
try {
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Fail "docker compose up failed with exit code $LASTEXITCODE. Check Docker Desktop is running and try again."
    }
    Write-OK "Paperclip containers started"
} finally {
    Pop-Location
}

Write-Info "Waiting for Paperclip to respond on port 3100 (up to 40 s)..."
$healthUrl  = 'http://localhost:3100/health'
$startTime  = Get-Date
$healthy    = $false
while (((Get-Date) - $startTime).TotalSeconds -lt 40) {
    try {
        $r = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $healthy = $true; break }
    } catch { }
    Start-Sleep -Seconds 2
}
if (-not $healthy) {
    Fail "Paperclip did not respond on port 3100 within 40 s. Run 'docker compose logs' in $paperclipRoot for details."
}
Write-OK "Paperclip is up and healthy"

# ─────────────────────────────────────────────────────────────────────────────
# Step 9 — Print summary
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n"
Write-Host "  ╔═════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║           Paperclip is up and running!                         ║" -ForegroundColor Magenta
Write-Host "  ╠═════════════════════════════════════════════════════════════════╣" -ForegroundColor Magenta
Write-Host "  ║                                                                 ║" -ForegroundColor Magenta
Write-Host "  ║  Local URL:     http://localhost:3100                           ║" -ForegroundColor Magenta
if ($accessUrl) {
Write-Host "  ║  Remote URL:    $accessUrl" -ForegroundColor Magenta
}
Write-Host "  ║                                                                 ║" -ForegroundColor Magenta
Write-Host "  ║  Data location: $paperclipRoot" -ForegroundColor Magenta
Write-Host "  ║                                                                 ║" -ForegroundColor Magenta
Write-Host "  ║  Manage Paperclip:                                              ║" -ForegroundColor Magenta
Write-Host "  ║    Stop:    cd $paperclipRoot; docker compose down              ║" -ForegroundColor Magenta
Write-Host "  ║    Start:   cd $paperclipRoot; docker compose up -d             ║" -ForegroundColor Magenta
Write-Host "  ║    Logs:    cd $paperclipRoot; docker compose logs -f           ║" -ForegroundColor Magenta
Write-Host "  ║    Update:  cd $paperclipRoot; docker compose pull; docker compose up -d  ║" -ForegroundColor Magenta
Write-Host "  ║                                                                 ║" -ForegroundColor Magenta
Write-Host "  ╚═════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""
