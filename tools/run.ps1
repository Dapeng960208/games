[CmdletBinding()]
param([switch]$Editor, [string]$EnginePath)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'engine.ps1')
$resolvedEngine = Resolve-GodotEngine -EnginePath $EnginePath
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot') -PathType Leaf)) {
    throw "Godot project is missing from $projectRoot."
}
$launchArguments = @('--path', $projectRoot)
if ($Editor) { $launchArguments += '--editor' }
& $resolvedEngine @launchArguments
if ($LASTEXITCODE -ne 0) { throw "Godot exited with code $LASTEXITCODE." }
