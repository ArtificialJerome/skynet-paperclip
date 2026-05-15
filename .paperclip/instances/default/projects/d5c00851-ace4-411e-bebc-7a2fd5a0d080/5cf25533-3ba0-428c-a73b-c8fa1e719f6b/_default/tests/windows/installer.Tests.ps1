#Requires -Version 5.1
<#
.SYNOPSIS
    Pester integration test suite for the Paperclip Windows installer (install.ps1).
.DESCRIPTION
    Verifies a successful install.ps1 run left the machine in the expected state.
    Run AFTER the installer has completed; does not re-run the installer itself.

    Prerequisites on the test machine:
        Install-Module -Name Pester -Force -SkipPublisherCheck
    Run:
        Invoke-Pester -Path .\tests\windows\installer.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:PaperclipDir  = Join-Path $env:USERPROFILE 'paperclip'
    $script:EnvFile       = Join-Path $script:PaperclipDir '.env'
    $script:ComposeFile   = Join-Path $script:PaperclipDir 'docker-compose.yml'
    $script:HealthUrl     = 'http://localhost:3100/health'
    $script:ApiBase       = 'http://localhost:3100'

    # Parse .env into a hashtable once
    $script:EnvVars = @{}
    if (Test-Path $script:EnvFile) {
        Get-Content $script:EnvFile | Where-Object { $_ -match '^\s*([^#=]+)=(.*)$' } | ForEach-Object {
            $script:EnvVars[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
}

# ─── Prerequisite binaries ────────────────────────────────────────────────────

Describe "Prerequisite binaries" {
    It "docker is in PATH" {
        (Get-Command docker -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It "docker daemon is running" {
        { docker info 2>&1 | Out-Null } | Should -Not -Throw
        $LASTEXITCODE | Should -Be 0
    }

    It "node is in PATH" {
        (Get-Command node -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It "node version is 18 or newer" {
        $ver = node --version
        $major = [int]($ver -replace 'v(\d+)\..*', '$1')
        $major | Should -BeGreaterOrEqual 18
    }

    It "npm is in PATH" {
        (Get-Command npm -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It "claude is in PATH" {
        (Get-Command claude -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }

    It "winget is in PATH (required for future updates)" {
        (Get-Command winget -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
    }
}

# ─── Data directory layout ────────────────────────────────────────────────────

Describe "Data directory layout" {
    It "~/paperclip exists" {
        $script:PaperclipDir | Should -Exist
    }

    It "~/paperclip/db exists" {
        Join-Path $script:PaperclipDir 'db' | Should -Exist
    }

    It "~/paperclip/storage exists" {
        Join-Path $script:PaperclipDir 'storage' | Should -Exist
    }

    It "~/paperclip/secrets exists" {
        Join-Path $script:PaperclipDir 'secrets' | Should -Exist
    }

    It "~/paperclip/projects exists" {
        Join-Path $script:PaperclipDir 'projects' | Should -Exist
    }
}

# ─── .env file ───────────────────────────────────────────────────────────────

Describe ".env file" {
    It ".env exists" {
        $script:EnvFile | Should -Exist
    }

    It "contains BETTER_AUTH_SECRET" {
        $script:EnvVars.ContainsKey('BETTER_AUTH_SECRET') | Should -Be $true
    }

    It "BETTER_AUTH_SECRET is a 64-character hex string" {
        $secret = $script:EnvVars['BETTER_AUTH_SECRET']
        $secret | Should -Match '^[0-9a-fA-F]{64}$'
    }

    It "contains PAPERCLIP_PORT" {
        $script:EnvVars.ContainsKey('PAPERCLIP_PORT') | Should -Be $true
    }

    It "PAPERCLIP_PORT is 3100" {
        $script:EnvVars['PAPERCLIP_PORT'] | Should -Be '3100'
    }

    It "contains PAPERCLIP_HOME" {
        $script:EnvVars.ContainsKey('PAPERCLIP_HOME') | Should -Be $true
    }

    It "PAPERCLIP_HOME is /paperclip" {
        $script:EnvVars['PAPERCLIP_HOME'] | Should -Be '/paperclip'
    }

    It "contains PAPERCLIP_PUBLIC_URL" {
        $script:EnvVars.ContainsKey('PAPERCLIP_PUBLIC_URL') | Should -Be $true
    }

    It "PAPERCLIP_PUBLIC_URL is a valid URL" {
        $url = $script:EnvVars['PAPERCLIP_PUBLIC_URL']
        $url | Should -Match '^https?://'
    }

    It "contains HOST=0.0.0.0 (binds to all interfaces)" {
        $script:EnvVars['HOST'] | Should -Be '0.0.0.0'
    }

    It "does NOT contain legacy PAPERCLIP_JWT_SECRET" {
        $script:EnvVars.ContainsKey('PAPERCLIP_JWT_SECRET') | Should -Be $false
    }

    It "does NOT contain legacy PAPERCLIP_DB_PATH" {
        $script:EnvVars.ContainsKey('PAPERCLIP_DB_PATH') | Should -Be $false
    }
}

# ─── docker-compose.yml ───────────────────────────────────────────────────────

Describe "docker-compose.yml" {
    BeforeAll {
        $script:ComposeRaw = if (Test-Path $script:ComposeFile) {
            Get-Content $script:ComposeFile -Raw
        } else { '' }
    }

    It "docker-compose.yml exists" {
        $script:ComposeFile | Should -Exist
    }

    It "image is ghcr.io/paperclipai/paperclip:latest" {
        $script:ComposeRaw | Should -Match 'ghcr\.io/paperclipai/paperclip:latest'
    }

    It "volume mount uses unified .:/paperclip (not split /data/db paths)" {
        $script:ComposeRaw | Should -Match '\.\s*:/paperclip'
        $script:ComposeRaw | Should -Not -Match '/data/db'
    }

    It "restart policy is unless-stopped" {
        $script:ComposeRaw | Should -Match 'unless-stopped'
    }

    It "env_file directive is present" {
        $script:ComposeRaw | Should -Match 'env_file'
    }
}

# ─── Running container ────────────────────────────────────────────────────────

Describe "Container state" {
    It "paperclip container exists" {
        $containers = docker ps -a --format '{{.Names}}' 2>&1
        $containers | Should -Match 'paperclip'
    }

    It "paperclip container is running" {
        $running = docker ps --format '{{.Names}}' 2>&1
        $running | Should -Match 'paperclip'
    }

    It "container is using the correct image" {
        $image = docker ps --filter 'name=paperclip' --format '{{.Image}}' 2>&1
        $image | Should -Match 'paperclipai/paperclip'
    }

    It "container port 3100 is published to the host" {
        $ports = docker ps --filter 'name=paperclip' --format '{{.Ports}}' 2>&1
        $ports | Should -Match '3100'
    }
}

# ─── Health and API ───────────────────────────────────────────────────────────

Describe "Health and API" {
    BeforeAll {
        # Allow up to 30 s for Paperclip to come up
        $ready = $false
        for ($i = 0; $i -lt 6; $i++) {
            try {
                $r = Invoke-WebRequest -Uri $script:HealthUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                if ($r.StatusCode -eq 200) { $ready = $true; break }
            } catch { }
            Start-Sleep -Seconds 5
        }
        $script:IsReady = $ready
    }

    It "health endpoint returns 200" {
        $script:IsReady | Should -Be $true
    }

    It "health response body contains ok/status field" {
        $r = Invoke-WebRequest -Uri $script:HealthUrl -UseBasicParsing -TimeoutSec 10
        $body = $r.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
        ($body.status -eq 'ok' -or $body.ok -eq $true) | Should -Be $true
    }

    It "root responds (not a 500)" {
        $r = Invoke-WebRequest -Uri $script:ApiBase -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
        $r.StatusCode | Should -BeLessOrEqual 404
    }
}

# ─── Idempotency ─────────────────────────────────────────────────────────────

Describe "Idempotency guards" {
    It ".env mtime is preserved (installer did not overwrite it)" {
        # Capture the current mtime; re-run the env-check logic from the script
        # (we do not actually call the installer here — just verify .env is older than 60s,
        #  which means it was not freshly regenerated during this test run)
        $age = (Get-Date) - (Get-Item $script:EnvFile).LastWriteTime
        $age.TotalSeconds | Should -BeGreaterThan 60
    }

    It "docker-compose.yml mtime is preserved" {
        $age = (Get-Date) - (Get-Item $script:ComposeFile).LastWriteTime
        $age.TotalSeconds | Should -BeGreaterThan 60
    }
}

# ─── Network binding ─────────────────────────────────────────────────────────

Describe "Network binding" {
    It "port 3100 is listening on 0.0.0.0 (accessible from LAN)" {
        $listeners = netstat -ano | Select-String '0\.0\.0\.0:3100'
        $listeners | Should -Not -BeNullOrEmpty
    }

    It "Paperclip responds on localhost:3100" {
        $r = Invoke-WebRequest -Uri $script:HealthUrl -UseBasicParsing -TimeoutSec 10
        $r.StatusCode | Should -Be 200
    }
}
