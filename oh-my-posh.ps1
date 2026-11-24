<#
.SYNOPSIS
    Oh My Posh theme management utility.
.DESCRIPTION
    Provides functions to create, list, compare, preview, and set Oh My Posh themes.
    Dot-source this file in your $PROFILE to make functions available.
.EXAMPLE
    . .\oh-my-posh.ps1
    Get-OhMyPoshThemeList
    Set-OhMyPoshTheme -Theme "atomic"
#>

function Create-NewTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ThemeName,
        [string]$BaseTheme = "jandedobbeleer",
        [string]$OutputPath = "$HOME\.mythemes"
    )

    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $themeFile = Join-Path $OutputPath "$ThemeName.omp.json"

    if (Test-Path -Path $themeFile) {
        Write-Error "Theme file already exists: $themeFile"
        return
    }

    try {
        oh-my-posh config export --config $BaseTheme --output $themeFile

        if (Test-Path -Path $themeFile) {
            Write-Host "✓ New theme created: $themeFile" -ForegroundColor Green
            Write-Host "  Based on: $BaseTheme" -ForegroundColor Gray
            if (Get-Command code -ErrorAction SilentlyContinue) { code $themeFile }
            elseif (Get-Command notepad -ErrorAction SilentlyContinue) { notepad $themeFile }
        }
        else {
            Write-Error "Export failed. Ensure '$BaseTheme' is a valid theme."
        }
    }
    catch {
        Write-Error "Error creating theme: $_"
    }
}

function Set-OhMyPoshTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Theme,
        [switch]$Preview,
        [switch]$NoProfileUpdate
    )

    $configPath = $null
    if ($Theme -match '^https?://') { $configPath = $Theme }
    elseif (Test-Path -Path $Theme -PathType Leaf) { $configPath = (Resolve-Path $Theme).Path }
    else {
        $candidate = Join-Path $env:POSH_THEMES_PATH "$Theme.omp.json"
        if (Test-Path $candidate) { $configPath = $candidate }
    }

    if (-not $configPath) {
        Write-Error "Theme '$Theme' not found. Use Get-PoshThemes to list available themes."
        return
    }

    if ($Preview) {
        Write-Host "Previewing theme: $configPath" -ForegroundColor Cyan
        oh-my-posh config export --config $configPath 2>$null
        return
    }

    if (-not $NoProfileUpdate) {
        if (-not (Test-Path $PROFILE)) { New-Item -Path $PROFILE -ItemType File -Force | Out-Null }
        $initLine = "oh-my-posh init pwsh --config `"$configPath`" | Invoke-Expression"
        $profileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue

        if ($profileContent -match 'oh-my-posh init pwsh') {
            $updated = [regex]::Replace(
                $profileContent,
                'oh-my-posh init pwsh[^\r\n]*',
                [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $initLine }
            )
            Set-Content -Path $PROFILE -Value $updated -Encoding utf8
        }
        else {
            Add-Content -Path $PROFILE -Value "`n$initLine" -Encoding utf8
        }
        Write-Host "✓ Theme set to: $configPath" -ForegroundColor Green
        Write-Host "  Profile updated: $PROFILE" -ForegroundColor Gray
    }

    oh-my-posh init pwsh --config "$configPath" | Invoke-Expression
    Write-Host "✓ Theme applied to current session." -ForegroundColor Green
}

function Get-OhMyPoshThemeList {
    [CmdletBinding()]
    param(
        [switch]$IncludeCustom,
        [string]$CustomPath = "$HOME\.mythemes"
    )

    $themes = @()
    # Use the official CLI command to list themes [citation:2]
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        $themes += oh-my-posh get themes 2>$null | ForEach-Object { $_.Trim() }
    }

    if ($IncludeCustom -and (Test-Path $CustomPath)) {
        $custom = Get-ChildItem -Path $CustomPath -Filter "*.omp.json" -File | Select-Object -ExpandProperty BaseName
        $themes += $custom | ForEach-Object { "[custom] $_" }
    }
    $themes | Sort-Object -Unique
}

function Compare-OhMyPoshTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Theme1,
        [Parameter(Mandatory = $true)][string]$Theme2
    )

    function Resolve-ThemePath($name) {
        if (Test-Path $name) { return (Resolve-Path $name).Path }
        $builtin = Join-Path $env:POSH_THEMES_PATH "$name.omp.json"
        if (Test-Path $builtin) { return $builtin }
        return $null
    }

    $path1 = Resolve-ThemePath $Theme1
    $path2 = Resolve-ThemePath $Theme2
    if (-not $path1) { Write-Error "Theme not found: $Theme1"; return }
    if (-not $path2) { Write-Error "Theme not found: $Theme2"; return }

    $keys1 = (Get-Content $path1 -Raw | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object
    $keys2 = (Get-Content $path2 -Raw | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object

    $onlyIn1 = $keys1 | Where-Object { $_ -notin $keys2 }
    $onlyIn2 = $keys2 | Where-Object { $_ -notin $keys1 }

    Write-Host "`n=== Structural Comparison ===" -ForegroundColor Cyan
    if ($onlyIn1) { Write-Host "Keys only in $Theme1 :" -ForegroundColor Yellow; $onlyIn1 | ForEach-Object { Write-Host "  - $_" } }
    if ($onlyIn2) { Write-Host "Keys only in $Theme2 :" -ForegroundColor Yellow; $onlyIn2 | ForEach-Object { Write-Host "  - $_" } }
    if (-not $onlyIn1 -and -not $onlyIn2) { Write-Host "Top-level key structure is identical." -ForegroundColor Green }
}

function Export-OhMyPoshThemePreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Theme,
        [string]$OutputPath = "$HOME\theme-preview.png"
    )

    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

    try {
        # Correct syntax uses 'config export image' [citation:7]
        oh-my-posh config export image --config $Theme --output $OutputPath
        if (Test-Path $OutputPath) {
            Write-Host "✓ Preview exported: $OutputPath" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Export failed: $_"
    }
}

function Reload-OhMyPoshTheme {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $PROFILE)) { Write-Error "No profile file found at $PROFILE"; return }
    $initLine = Get-Content $PROFILE | Where-Object { $_ -match 'oh-my-posh init pwsh' }
    if (-not $initLine) { Write-Error "No Oh My Posh init line found in profile."; return }

    try {
        . $PROFILE
        Write-Host "✓ Profile reloaded and theme reapplied." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to reload profile: $_"
    }
}