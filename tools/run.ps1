[CmdletBinding()]
param([switch]$Editor)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$enginePath = Join-Path $PSScriptRoot 'godot\Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Portable Godot is missing: $enginePath. Keep the tools/godot folder beside this launcher."
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot') -PathType Leaf)) {
    throw "Godot project is missing from $projectRoot."
}
$launchArguments = @('--path', $projectRoot)
if ($Editor) { $launchArguments += '--editor' }
& $enginePath @launchArguments