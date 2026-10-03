[CmdletBinding()]
param(
    [string]$EnginePath,
    [ValidatePattern('^[a-z][a-z0-9_]*$')][string[]]$Suite = @('numerical_fresh_profile', 'progressive_monster_roster', 'numerical_instances'),
    [switch]$ImportOnly,
    [switch]$SkipImport,
    [switch]$Graphical,
    [ValidateSet(0,2)][int]$Ruleset = 0
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

$suiteRegistry = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'testing/suites.json') -Encoding UTF8 -Raw | ConvertFrom-Json
function Get-SuiteDefinition {
    param([string]$Name)
    $entry = $suiteRegistry.PSObject.Properties[$Name]
    if ($null -eq $entry) { throw "Unknown acceptance suite: $Name." }
    return $entry.Value
}
if (-not $ImportOnly) {
    foreach ($testName in $Suite) {
        $testPath = Join-Path $projectRoot (Get-SuiteDefinition $testName).script
        if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) { throw "Required acceptance suite is missing: $testPath." }
    }
}

if (-not $SkipImport) {
    Invoke-GodotStage -Stage 'resource import' -StageArguments @('--editor', '--import', '--quit', '--', "--test-profile=$(Get-TestProfile 'import')")
}
if ($ImportOnly) { Write-Host "Resource import completed. Isolated profile directory: $testDirectory"; return }
foreach ($testName in $Suite) {
    $definition = Get-SuiteDefinition $testName
    if ($testName -eq 'b09_2k' -and -not $Graphical) { throw 'b09_2k requires -Graphical and an actual GPU framebuffer.' }
    [string[]]$arguments = if ($definition.scene) { @("res://$($definition.scene)") } else { @('--script', "res://$($definition.script)") }
    # The legacy playthrough suite shares the combat fixture's safety prefix.
    $profileName = if ($testName -eq 'playthrough') { 'combat_playthrough' } else { $testName }
    if ($testName -in @('b09_2k','b09_inventory','b09_equipment','b09_monster_contract')) {
        $arguments += @('--', '--candidate-b09', "--test-profile=user://test_b09_candidate/$testName.json")
        if ($testName -eq 'b09_2k') { $arguments += '--b09-resolution=2560x1440' }
    } else {
        $arguments += @('--', "--test-profile=$(Get-TestProfile $profileName)")
        if ($testName -eq 'b09_equipment_release_gate') { $arguments += '--b09-release-gate' }
    }
    $testRuleset = $Ruleset
    if ($testRuleset -ne 0) { $arguments += "--test-ruleset=$testRuleset" }
    Invoke-GodotStage -Stage "$testName acceptance" -StageArguments $arguments -AllowGraphics
}
Write-Host "All requested acceptance suites passed. Isolated profiles: $testDirectory"
