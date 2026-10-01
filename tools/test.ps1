[CmdletBinding()]
param(
    [string]$EnginePath,
    [ValidatePattern('^[a-z][a-z0-9_]*$')][string[]]$Suite = @('single_biome_routes', 'loot_upgrade', 'first_four_bosses', 'first_four_mechanics', 'race_relics', 'death_penalty'),
    [switch]$SkipRestart = $true,
    [switch]$ImportOnly,
    [switch]$SkipImport,
    [switch]$Graphical,
    [ValidateSet(0,1,2)][int]$Ruleset = 0
)

$ErrorActionPreference = 'Stop'
if ($ImportOnly -and $SkipImport) { throw '-ImportOnly and -SkipImport cannot be combined.' }
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'engine.ps1')
$resolvedEngine = Resolve-GodotEngine -EnginePath $EnginePath -Console
# Each invocation gets new workspace profiles, isolated from the player's save.
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$testDirectory = Join-Path $PSScriptRoot "godot\test-runs\$runId"
$null = New-Item -ItemType Directory -Path $testDirectory -Force
$roamingDirectory = Join-Path $testDirectory 'userdata\Roaming'
$localDirectory = Join-Path $testDirectory 'userdata\Local'
$null = New-Item -ItemType Directory -Path $roamingDirectory, $localDirectory -Force
$script:GodotTestStageOrdinal = 0

function Get-TestProfile {
    param([string]$Name)
    return (Join-Path $testDirectory "test_$Name.json").Replace('\', '/')
}

function Invoke-GodotStage {
    param([string]$Stage, [string[]]$StageArguments, [switch]$AllowGraphics)
    Write-Host "Running $Stage..."
    # Preserve array identity: splatting a scalar string sends one character per
    # argument in PowerShell, which silently prevents Godot recognizing flags.
    # An explicit silent mixer also releases short-lived AudioStreamPlayback
    # instances; headless's implicit disabled backend may retain them at exit.
    [string[]]$displayArguments = if ($Graphical -and $AllowGraphics) { @() } else { @('--headless', '--audio-driver', 'Dummy') }
    $script:GodotTestStageOrdinal += 1
    $logPath = Join-Path $testDirectory ('{0:D2}_{1}.log' -f $script:GodotTestStageOrdinal, ($Stage -replace '[^a-zA-Z0-9_-]', '_'))
    $previousAppData = $env:APPDATA
    $previousLocalAppData = $env:LOCALAPPDATA
    $previousErrorPreference = $ErrorActionPreference
    try {
        # Some suites create user:// fixtures. Redirect only this process and its
        # Godot child, and always restore the caller's environment afterwards.
        $env:APPDATA = $roamingDirectory
        $env:LOCALAPPDATA = $localDirectory
        # Windows PowerShell 5.1 wraps native stderr as ErrorRecord. Capture its
        # text instead of terminating before the exact diagnostic filter runs.
        $ErrorActionPreference = 'Continue'
        # Native commands update the global automatic variable. A local reset
        # would shadow it and incorrectly report a null exit code afterwards.
        $global:LASTEXITCODE = $null
        & $resolvedEngine @displayArguments --path $projectRoot @StageArguments 2>&1 |
            ForEach-Object { $_.ToString() } | Tee-Object -FilePath $logPath -ErrorAction Stop
        $exitCode = $global:LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorPreference
        $env:APPDATA = $previousAppData
        $env:LOCALAPPDATA = $previousLocalAppData
    }
    if ($null -eq $exitCode) { throw "$Stage could not start Godot. See $logPath" }
    if ($exitCode -ne 0) {
        throw "$Stage failed with exit code $exitCode. Isolated profiles and log: $testDirectory"
    }
    # Godot editor import can report script parse errors while exiting with 0.
    $diagnostics = @(Select-String -LiteralPath $logPath -Pattern '^\s*(SCRIPT ERROR:|ERROR:)' | ForEach-Object { $_.Line })
    $certificateDiagnostic = 'ERROR: Failed to read the root certificate store.'
    if ($diagnostics -ccontains $certificateDiagnostic) {
        Write-Warning 'Godot could not read the Windows root certificate store in this sandbox. This exact startup diagnostic is retained in the log and allowed for these offline tests; other engine/script errors still fail.'
    }
    $unexpectedDiagnostics = @($diagnostics | Where-Object { $_ -cne $certificateDiagnostic })
    if ($unexpectedDiagnostics.Count -gt 0) {
        throw "$Stage reported engine/script errors. See $logPath"
    }
}

if (-not $ImportOnly) {
    foreach ($testName in $Suite) {
        $testPath = Join-Path $projectRoot "tests\test_$testName.gd"
        if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) { throw "Required acceptance suite is missing: $testPath." }
    }
    if (-not $SkipRestart -and -not (Test-Path -LiteralPath (Join-Path $projectRoot 'tests\test_restart.gd') -PathType Leaf)) {
        throw 'Required restart acceptance suite is missing.'
    }
}

if (-not $SkipImport) {
    Invoke-GodotStage -Stage 'resource import' -StageArguments @('--editor', '--import', '--quit', '--', "--test-profile=$(Get-TestProfile 'import')")
}
if ($ImportOnly) { Write-Host "Resource import completed. Isolated profile directory: $testDirectory"; return }
foreach ($testName in $Suite) {
    $scenePath = Join-Path $projectRoot "tests\test_$testName.tscn"
    [string[]]$arguments = if (Test-Path -LiteralPath $scenePath -PathType Leaf) { @("res://tests/test_$testName.tscn") } else { @('--script', "res://tests/test_$testName.gd") }
    # The legacy playthrough suite shares the combat fixture's safety prefix.
    $profileName = if ($testName -eq 'playthrough') { 'combat_playthrough' } else { $testName }
    $arguments += @('--', "--test-profile=$(Get-TestProfile $profileName)")
    # These named historical suites assert the original mechanics/economy.
    # New numerical/default-activation suites deliberately receive no override.
    $legacyDefaultSuites = @('single_biome_routes','loot_upgrade','first_four_bosses','first_four_mechanics','race_relics','death_penalty','equipment_integration','reward_transactions','numerical_versioned_saves')
    $testRuleset = if ($Ruleset -ne 0) { $Ruleset } elseif ($testName -in $legacyDefaultSuites) { 1 } else { 0 }
    if ($testRuleset -ne 0) { $arguments += "--test-ruleset=$testRuleset" }
    Invoke-GodotStage -Stage "$testName acceptance" -StageArguments $arguments -AllowGraphics
}
if (-not $SkipRestart) {
    foreach ($mode in @('write', 'read', 'read')) {
        Invoke-GodotStage -Stage "restart $mode" -StageArguments @('--script', 'res://tests/test_restart.gd', '--', "--test-profile=$(Get-TestProfile 'restart_suite')", "--mode=$mode")
    }
    foreach ($mode in @('abrupt_write', 'abrupt_read', 'abrupt_read')) {
        Invoke-GodotStage -Stage "interruption $mode" -StageArguments @('--script', 'res://tests/test_restart.gd', '--', "--test-profile=$(Get-TestProfile 'restart_abrupt_suite')", "--mode=$mode")
    }
}
Write-Host "All requested acceptance suites passed. Isolated profiles: $testDirectory"
