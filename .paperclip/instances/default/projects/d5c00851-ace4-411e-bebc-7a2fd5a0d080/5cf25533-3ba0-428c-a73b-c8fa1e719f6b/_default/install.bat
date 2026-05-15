@echo off
setlocal enabledelayedexpansion

:: ─── Self-elevation (request admin if not already elevated) ──────────────────
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd.exe '/c \"%~f0\"' -Verb RunAs -Wait"
    exit /b 0
)

echo.
echo Paperclip Installer
echo ===================
echo.

:: ─── Check PowerShell is available ──────────────────────────────────────────
where powershell >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: PowerShell not found. Please install PowerShell and try again.
    pause
    exit /b 1
)

:: ─── Find install.ps1 next to this .bat ────────────────────────────────────
set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%install.ps1"

if not exist "%PS1_PATH%" (
    echo ERROR: install.ps1 not found next to install.bat
    echo Please download both files and keep them in the same folder.
    pause
    exit /b 1
)

echo Running Paperclip installer...
echo.

:: ─── Run the PowerShell installer ──────────────────────────────────────────
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%"

if %errorLevel% neq 0 (
    echo.
    echo Installation encountered an error (exit code %errorLevel%).
    echo Check the messages above for details.
    pause
    exit /b 1
)

echo.
echo Press any key to close...
pause >nul
