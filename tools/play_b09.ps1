param([string]$EnginePath = "")
$ErrorActionPreference = "Stop"
$taskRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'engine.ps1')
$b09Engine = Resolve-GodotEngine -EnginePath $EnginePath -Console
& $b09Engine --path $taskRoot "res://scenes/gameplay/levels/b09/preview.tscn" -- --candidate-b09 --test-profile=user://test_b09_candidate/profile.json
exit $LASTEXITCODE
