# Shared Windows engine discovery. Dot-source this file from launchers.
$script:GodotToolsRoot = $PSScriptRoot

function Get-GodotExecutables {
    param([Parameter(Mandatory = $true)][string]$Location, [switch]$Console)
    $expanded = [Environment]::ExpandEnvironmentVariables($Location.Trim('"'))
    if (Test-Path -LiteralPath $expanded -PathType Leaf) {
        $item = Get-Item -LiteralPath $expanded
        if ($item.Extension -ne '.exe') { return }
        if ($Console -and $item.BaseName -notmatch '_console$') {
            $consolePath = Join-Path $item.DirectoryName ($item.BaseName + '_console.exe')
            if (Test-Path -LiteralPath $consolePath -PathType Leaf) { $consolePath }
        }
        $item.FullName
        return
    }
    if (Test-Path -LiteralPath $expanded -PathType Container) {
        # Only inspect the selected directory and its immediate children, never a drive.
        $directories = @((Get-Item -LiteralPath $expanded)) + @(Get-ChildItem -LiteralPath $expanded -Directory -ErrorAction SilentlyContinue)
        $executables = @(foreach ($directory in $directories) {
            Get-ChildItem -LiteralPath $directory.FullName -Filter '*godot*.exe' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -eq '.exe' }
        })
        $executables | Sort-Object @{ Expression = {
            if ($_.BaseName -match '(?i)godot_v?(\d+\.\d+(?:\.\d+)?)') { [version]$Matches[1] } else { [version]'0.0' }
        }; Descending = $true }, @{ Expression = {
            if ($Console) { $_.BaseName -notmatch '_console$' } else { $_.BaseName -match '_console$' }
        } } | ForEach-Object { $_.FullName }
        return
    }
    $command = Get-Command -Name $expanded -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $command.Source }
}

function Resolve-GodotEngine {
    [CmdletBinding()]
    param([string]$EnginePath, [switch]$Console)
    $locations = @()
    $explicit = $false
    if ($EnginePath) {
        $locations = @($EnginePath)
        $explicit = $true
    } elseif ($env:GODOT_BIN) {
        $locations = @($env:GODOT_BIN)
        $explicit = $true
    } else {
        $locations = @((Join-Path $script:GodotToolsRoot 'godot'), 'godot', 'godot4', 'C:\Program Files\Godot', 'C:\Program Files (x86)\Godot', 'C:\tools\godot', 'C:\Godot')
        if ($env:LOCALAPPDATA) { $locations += Join-Path $env:LOCALAPPDATA 'Programs\Godot' }
        if ($env:USERPROFILE) { $locations += Join-Path $env:USERPROFILE 'scoop\apps\godot\current' }
    }
    $seen = @{}
    $rejected = @()
    foreach ($location in $locations) {
        foreach ($candidate in @(Get-GodotExecutables -Location $location -Console:$Console)) {
            if ($seen.ContainsKey($candidate)) { continue }
            $seen[$candidate] = $true
            try {
                $versionOutput = (& $candidate --headless --version 2>&1 | Out-String).Trim()
                if ($LASTEXITCODE -eq 0 -and $versionOutput -match '(?m)^4\.(\d+)\.(?:\d+|stable)') {
                    if ([int]$Matches[1] -ge 7) {
                        Write-Host "Godot $versionOutput"
                        return $candidate
                    }
                }
                $rejected += "$candidate ($versionOutput)"
            } catch {
                $rejected += "$candidate ($($_.Exception.Message))"
            }
        }
    }
    $detail = if ($rejected.Count) { " Rejected: $($rejected -join '; ')" } else { '' }
    $source = if ($explicit) { 'The specified Godot location is missing or incompatible.' } else { 'No compatible Godot 4.7+ executable was found.' }
    throw "$source Run .\tools\setup.ps1 to fetch the verified portable runtime, or pass -EnginePath / set GODOT_BIN.$detail"
}
