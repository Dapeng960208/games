param(
    [string]$EnginePath = "",
    [ValidateSet('1280x720','1920x1080','2560x1440','3840x2160')][string]$Resolution = '2560x1440'
)
$ErrorActionPreference = "Stop"
$taskRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'engine.ps1')
$b09Engine = Resolve-GodotEngine -EnginePath $EnginePath -Console
& $b09Engine --path $taskRoot --resolution $Resolution "res://scenes/gameplay/levels/b09/preview.tscn" -- --candidate-b09 --test-profile=user://test_b09_candidate/profile.json "--b09-resolution=$Resolution"
exit $LASTEXITCODE
