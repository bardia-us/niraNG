param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
$versionLine = $pubspec | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
if ($versionLine -notmatch '^version:\s*([^+\s]+)') {
    throw 'Could not read the niraNG version from pubspec.yaml.'
}
$versionName = $Matches[1]

if (-not $SkipBuild) {
    & flutter build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed.' }
}

$output = Join-Path $projectRoot 'build\app\outputs\flutter-apk'
$architectures = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
foreach ($abi in $architectures) {
    $source = Join-Path $output "app-$abi-release.apk"
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing release APK: $source" }
    $destination = Join-Path $output "niraNG-v$versionName-$abi.apk"
    Copy-Item -LiteralPath $source -Destination $destination -Force
    Write-Output $destination
}
