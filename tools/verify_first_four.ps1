[CmdletBinding()]
param([switch]$Showcase, [switch]$SkipImport, [string]$EnginePath)

$taskOutputDirectory = Join-Path $PSScriptRoot '..\artifacts'
$null = New-Item -ItemType Directory -Path $taskOutputDirectory -Force

$taskSuites = @('single_biome_routes', 'loot_upgrade', 'first_four_bosses',
    'first_four_mechanics', 'race_relics', 'death_penalty')
if ($Showcase) { $taskSuites += 'storybook_rebuild' }
$taskArguments = @{ Suite = $taskSuites; SkipRestart = $true;
    Graphical = $Showcase; SkipImport = $SkipImport }
if ($EnginePath) { $taskArguments.EnginePath = $EnginePath }
& (Join-Path $PSScriptRoot 'test.ps1') @taskArguments
