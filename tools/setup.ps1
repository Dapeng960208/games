[CmdletBinding()]
param([ValidatePattern('^4\.\d+(\.\d+)?-stable$')][string]$Version = '4.7.2-stable')

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ([version]($Version -replace '-stable$', '') -lt [version]'4.7') { throw 'This project requires Godot 4.7 or newer.' }
if (-not [Environment]::Is64BitOperatingSystem) { throw 'This portable setup requires 64-bit Windows.' }
# TLS 1.2 is needed when this script is run in Windows PowerShell 5.1.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$downloadDirectory = Join-Path $PSScriptRoot 'downloads'
$runtimeDirectory = Join-Path $PSScriptRoot 'godot'
$null = New-Item -ItemType Directory -Path $downloadDirectory, $runtimeDirectory -Force
$headers = @{ 'User-Agent' = 'AbyssSalvager-LocalSetup'; 'Accept' = 'application/vnd.github+json' }
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/godotengine/godot-builds/releases/tags/$Version" -Headers $headers
if ($release.draft -or $release.prerelease -or $release.tag_name -ne $Version) { throw 'Expected an official stable Godot release.' }
$archiveName = "Godot_v${Version}_win64.exe.zip"
$archiveAsset = @($release.assets | Where-Object { $_.name -eq $archiveName })
$checksumAsset = @($release.assets | Where-Object { $_.name -eq 'SHA512-SUMS.txt' })
if ($archiveAsset.Count -ne 1 -or $checksumAsset.Count -ne 1) { throw 'Official Windows archive or checksum manifest is missing.' }
$archiveUrl = [string]$archiveAsset[0].browser_download_url
$checksumUrl = [string]$checksumAsset[0].browser_download_url
$officialPrefix = "https://github.com/godotengine/godot-builds/releases/download/$Version/"
if (-not $archiveUrl.StartsWith($officialPrefix) -or -not $checksumUrl.StartsWith($officialPrefix)) { throw 'Unexpected release download host or path.' }
$archivePath = Join-Path $downloadDirectory $archiveName
$checksumPath = Join-Path $downloadDirectory "$Version-SHA512-SUMS.txt"
Write-Host "Fetching official checksums for Godot $Version..."
Invoke-WebRequest -UseBasicParsing -Uri $checksumUrl -OutFile $checksumPath
$checksumLine = @(Get-Content -Encoding UTF8 -LiteralPath $checksumPath | Where-Object { $_ -match ('^[0-9a-fA-F]{128}\s+\*?' + [regex]::Escape($archiveName) + '$') })
if ($checksumLine.Count -ne 1) { throw 'No unambiguous SHA512 checksum exists for the Windows archive.' }
$expectedHash = ($checksumLine[0] -split '\s+')[0]
$archiveVerified = (Test-Path -LiteralPath $archivePath -PathType Leaf) -and ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA512).Hash -eq $expectedHash)
if (-not $archiveVerified) {
    Write-Host "Downloading $archiveName ($([math]::Round($archiveAsset[0].size / 1MB, 1)) MB)..."
    Invoke-WebRequest -UseBasicParsing -Uri $archiveUrl -OutFile $archivePath
}
$actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA512).Hash
if ($actualHash -ne $expectedHash) { throw "SHA512 verification failed. The untrusted archive was not extracted: $archivePath" }
$sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($archiveAsset[0].digest -and $archiveAsset[0].digest -ne "sha256:$sha256") { throw 'GitHub release SHA256 digest does not match the archive.' }
Write-Host 'Archive checksums verified. Extracting local portable runtime...'
Expand-Archive -LiteralPath $archivePath -DestinationPath $runtimeDirectory -Force
# Godot self-contained mode keeps its editor settings/data beside this engine.
$null = New-Item -ItemType File -Path (Join-Path $runtimeDirectory '_sc_') -Force
$engine = Join-Path $runtimeDirectory "Godot_v${Version}_win64_console.exe"
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'The verified archive did not contain the expected console executable.' }
$engineVersion = (& $engine --headless --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'The downloaded engine could not execute --version.' }
$receipt = [ordered]@{
    release = $Version
    release_url = $release.html_url
    published_at = $release.published_at
    archive_url = $archiveUrl
    checksum_url = $checksumUrl
    archive_sha512 = $actualHash.ToLowerInvariant()
    archive_sha256 = $sha256
    verified_at = [DateTime]::UtcNow.ToString('o')
    executable = $engine
    executable_version = $engineVersion
}
$receipt | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runtimeDirectory 'verified-release.json')
Write-Host "Ready: $engineVersion"
Write-Host $engine
