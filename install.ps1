<#
.SYNOPSIS
    Automated Oh My Posh installer for PowerShell on Windows.
.DESCRIPTION
    Installs Oh My Posh via winget, installs a Nerd Font, configures the
    PowerShell profile, and dot-sources the oh-my-posh.ps1 helper script.
.EXAMPLE
    .\install.ps1
    .\install.ps1 -Theme "atomic" -Font "meslo"
#>

[CmdletBinding()]
param(
    [string]$Theme = "jandedobbeleer",
    [string]$Font = "meslo",
    [string]$HelperScript = "$HOME\oh-my-posh.ps1",
    [switch]$SkipFont
)

$ErrorActionPreference = "Stop"

function Write-Step($Message) {
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-Success($Message) {
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Warn($Message) {
    Write-Host "! $Message" -ForegroundColor Yellow
}

# --- Step 1: Install Oh My Posh ---
Write-Step "Installing Oh My Posh"

$ompExists = Get-Command oh-my-posh -ErrorAction SilentlyContinue
if ($ompExists) {
    $version = oh-my-posh --version 2>$null
    Write-Success "Oh My Posh already installed (version $version)"
} else {
    Write-Host "Installing via winget..."
    winget install JanDeDobbeleer.OhMyPosh --source winget --accept-package-agreements --accept-source-agreements
    
    # Refresh PATH for current session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
    
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Success "Oh My Posh installed successfully"
    } else {
        Write-Warn "Installation may have succeeded but 'oh-my-posh' is not on PATH yet."
        Write-Warn "Please restart your terminal and re-run this script."
        return
    }
}

# --- Step 2: Install Nerd Font ---
if (-not $SkipFont) {
    Write-Step "Installing Nerd Font: $Font"
    try {
        oh-my-posh font install $Font
        Write-Success "Font '$Font' installed"
        Write-Host "  Remember to set this font in your terminal settings." -ForegroundColor Gray
    } catch {
        Write-Warn "Font installation failed: $_"
        Write-Host "  You can install it manually from https://www.nerdfonts.com/" -ForegroundColor Gray
    }
} else {
    Write-Warn "Skipping font installation (-SkipFont)"
}

# --- Step 3: Ensure PowerShell Profile Exists ---
Write-Step "Configuring PowerShell profile"

if (-not (Test-Path $PROFILE)) {
    New-Item -Path $PROFILE -ItemType File -Force | Out-Null
    Write-Success "Created profile: $PROFILE"
} else {
    Write-Success "Profile exists: $PROFILE"
}

# --- Step 4: Verify Helper Script Exists ---
Write-Step "Checking helper script"

if (Test-Path $HelperScript) {
    Write-Success "Found helper script: $HelperScript"
} else {
    Write-Warn "Helper script not found at: $HelperScript"
    Write-Host "  The profile will still be configured, but theme management functions" -ForegroundColor Gray
    Write-Host "  (Create-NewTheme, Set-OhMyPoshTheme, etc.) will not be available." -ForegroundColor Gray
    Write-Host "  You can copy oh-my-posh.ps1 to that location later." -ForegroundColor Gray
}

# --- Step 5: Update Profile ---
Write-Step "Updating profile with Oh My Posh initialization"

$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
$changed = $false

# 5a: Add helper script dot-source if not present
if (Test-Path $HelperScript) {
    $marker = "# oh-my-posh.ps1 helper functions"
    if ($profileContent -notmatch [regex]::Escape($marker)) {
        $helperBlock = @"

$marker
. "$HelperScript"
"@
        Add-Content -Path $PROFILE -Value $helperBlock -Encoding utf8
        Write-Success "Added helper script dot-source to profile"
        $changed = $true
    } else {
        Write-Success "Helper script already referenced in profile"
    }
}

# 5b: Add/replace Oh My Posh init line
$configPath = "$env:POSH_THEMES_PATH\$Theme.omp.json"
$initLine = "oh-my-posh init pwsh --config `"$configPath`" | Invoke-Expression"

if ($profileContent -match 'oh-my-posh init pwsh') {
    # Replace existing init line
    $updated = [regex]::Replace(
        $profileContent,
        'oh-my-posh init pwsh[^\r\n]*',
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $initLine }
    )
    Set-Content -Path $PROFILE -Value $updated -Encoding utf8
    Write-Success "Updated existing init line to use theme: $Theme"
    $changed = $true
} else {
    Add-Content -Path $PROFILE -Value "`n$initLine" -Encoding utf8
    Write-Success "Added init line with theme: $Theme"
    $changed = $true
}

# --- Step 6: Set Execution Policy (if needed) ---
Write-Step "Checking execution policy"

$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentPolicy -eq "Restricted" -or $currentPolicy -eq "Undefined") {
    Write-Warn "Execution policy is '$currentPolicy'. Profile scripts may not load."
    Write-Host "  Run this to fix it:" -ForegroundColor Gray
    Write-Host "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Gray
} else {
    Write-Success "Execution policy: $currentPolicy"
}

# --- Step 7: Apply in Current Session ---
Write-Step "Applying configuration to current session"

try {
    if (Test-Path $HelperScript) {
        . $HelperScript
    }
    oh-my-posh init pwsh --config "$configPath" | Invoke-Expression
    Write-Success "Theme applied to current session"
} catch {
    Write-Warn "Could not apply theme in current session: $_"
}

# --- Summary ---
Write-Step "Installation Complete"
Write-Host @"

Next steps:
  1. Restart your terminal (or run: . `$PROFILE)
  2. Set your terminal font to a Nerd Font (e.g., "MesloLGM Nerd Font")
  3. Use `Get-OhMyPoshThemeList` to see available themes
  4. Use `Set-OhMyPoshTheme <name>` to switch themes

"@ -ForegroundColor White