#Requires -Version 5.1
<#
.SYNOPSIS
    Idempotency test suite for the Paperclip Windows installer (install.ps1).
.DESCRIPTION
    Verifies that a second run of install.ps1 does not overwrite configuration
    files that were created on the first run. Run AFTER install.ps1 has already
    completed once (e.g. after installer.Tests.ps1 in CI).

    Prerequisite: PAPERCLIP_SKIP_AUTH=1 must be available in the environment,
    or Claude must already be authenticated, for the second install run to be
    non-interactive. CI sets PAPERCLIP_SKIP_AUTH=1; local runs need it too.

    Run:
        $env:PAPERCLIP_SKIP_AUTH = '1'
        Invoke-Pester -Path .\tests\windows\installer.Idempotency.Tests.ps1 -Output Detailed
#>

BeforeAll {
    $script:PaperclipDir  = Join-Path $env:USERPROFILE 'paperclip'
    $script:EnvFile       = Join-Path $script:PaperclipDir '.env'
    $script:ComposeFile   = Join-Path $script:PaperclipDir 'docker-compose.yml'

    # Resolve install.ps1 relative to this file (tests/windows/ → repo root)
    $script:InstallerPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..\install.ps1')).Path

    # Capture baseline state BEFORE the second install run
    $envItem = Get-Item $script:EnvFile
    $script:EnvMtimeBefore    = $envItem.LastWriteTimeUtc
    $script:EnvHashBefore     = (Get-FileHash $script:EnvFile    -Algorithm SHA256).Hash

    $composeItem = Get-Item $script:ComposeFile
    $script:ComposeMtimeBefore  = $composeItem.LastWriteTimeUtc
    $script:ComposeHashBefore   = (Get-FileHash $script:ComposeFile -Algorithm SHA256).Hash

    # Second install run — must be non-interactive
    $env:PAPERCLIP_SKIP_AUTH = '1'
    $script:SecondRunOutput = & $script:InstallerPath *>&1 | Out-String
    $script:SecondRunExitCode = $LASTEXITCODE
    # Restore env (remove variable so it doesn't leak)
    Remove-Item Env:\PAPERCLIP_SKIP_AUTH -ErrorAction SilentlyContinue

    # Re-capture file state AFTER second install run
    $script:EnvMtimeAfter     = (Get-Item $script:EnvFile).LastWriteTimeUtc
    $script:EnvHashAfter      = (Get-FileHash $script:EnvFile    -Algorithm SHA256).Hash
    $script:ComposeMtimeAfter = (Get-Item $script:ComposeFile).LastWriteTimeUtc
    $script:ComposeHashAfter  = (Get-FileHash $script:ComposeFile -Algorithm SHA256).Hash
}

# ─── Second install run exits cleanly ────────────────────────────────────────

Describe "Second install run exits cleanly" {
    It "install.ps1 exits 0 on second run" {
        $script:SecondRunExitCode | Should -Be 0
    }
}

# ─── .env idempotency ─────────────────────────────────────────────────────────

Describe ".env idempotency" {
    It ".env content is unchanged after second install" {
        $script:EnvHashAfter | Should -Be $script:EnvHashBefore
    }

    It ".env mtime is unchanged after second install (file was not overwritten)" {
        $script:EnvMtimeAfter | Should -Be $script:EnvMtimeBefore
    }
}

# ─── docker-compose.yml idempotency ───────────────────────────────────────────

Describe "docker-compose.yml idempotency" {
    It "docker-compose.yml content is unchanged after second install" {
        $script:ComposeHashAfter | Should -Be $script:ComposeHashBefore
    }

    It "docker-compose.yml mtime is unchanged after second install (file was not overwritten)" {
        $script:ComposeMtimeAfter | Should -Be $script:ComposeMtimeBefore
    }
}

# ─── Auth guard ───────────────────────────────────────────────────────────────

Describe "Auth guard (PAPERCLIP_SKIP_AUTH)" {
    It "second run output does not contain interactive auth prompt" {
        $script:SecondRunOutput | Should -Not -Match 'Opening browser for Claude OAuth login'
    }

    It "second run output confirms auth was skipped or already authenticated" {
        ($script:SecondRunOutput -match 'Skipping Claude auth' -or
         $script:SecondRunOutput -match 'Already authenticated') | Should -Be $true
    }
}
