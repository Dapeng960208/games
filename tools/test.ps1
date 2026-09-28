[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$enginePath = Join-Path $PSScriptRoot 'godot\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Portable Godot console runner is missing: $enginePath."
}
$testNames = @('core', 'combat', 'ui', 'ui_edges')
foreach ($testName in $testNames) {
    $testPath = Join-Path $projectRoot "tests\test_$testName.gd"
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
        throw "Required acceptance suite is missing: $testPath."
    }
}
function Invoke-GodotStage {
    param([string]$Stage, [string[]]$StageArguments)
    Write-Host "Running $Stage..."
    & $enginePath --headless --path $projectRoot @StageArguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Stage failed with exit code $LASTEXITCODE."
    }
}
Invoke-GodotStage -Stage 'resource import' -StageArguments @('--editor', '--import', '--quit', '--', '--test-profile=user://test_import.json')
foreach ($testName in $testNames) {
    if ($testName -eq 'combat') {
        Invoke-GodotStage -Stage 'combat acceptance' -StageArguments @('res://tests/test_combat.tscn', '--', '--test-profile=user://test_combat.json')
    } else {
        Invoke-GodotStage -Stage "$testName acceptance" -StageArguments @(
            '--script', "res://tests/test_$testName.gd", '--', "--test-profile=user://test_$testName.json"
        )
    }
}
foreach ($mode in @('write', 'read', 'read')) {
    Invoke-GodotStage -Stage "restart $mode" -StageArguments @('--script', 'res://tests/test_restart.gd', '--', '--test-profile=user://test_restart_suite.json', "--mode=$mode")
}
foreach ($mode in @('abrupt_write', 'abrupt_read', 'abrupt_read')) {
    Invoke-GodotStage -Stage "interruption $mode" -StageArguments @('--script', 'res://tests/test_restart.gd', '--', '--test-profile=user://test_restart_abrupt_suite.json', "--mode=$mode")
}
Write-Host 'All acceptance suites passed.'
