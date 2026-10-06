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
$releaseOutput = Join-Path $projectRoot "build\releases\v$versionName"
New-Item -ItemType Directory -Path $releaseOutput -Force | Out-Null
$architectures = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
foreach ($abi in $architectures) {
    $source = Join-Path $output "app-$abi-release.apk"
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing release APK: $source" }
    $destination = Join-Path $releaseOutput "niraNG-v$versionName-$abi.apk"
    Copy-Item -LiteralPath $source -Destination $destination -Force
    Write-Output $destination
}

# Preserve splits before the universal build can replace Gradle outputs.
if (-not $SkipBuild) {
    # R8 can retain mapped dex files in the Windows daemon after a split build.
    # Gracefully release those handles before changing APK packaging mode.
    if ($env:OS -eq 'Windows_NT') {
        Push-Location (Join-Path $projectRoot 'android')
        try {
            & .\gradlew.bat --stop
            if ($LASTEXITCODE -ne 0) { throw 'Could not release the Gradle build daemon.' }
        } finally {
            Pop-Location
        }
    }
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'Flutter universal release build failed.' }
}
$universalSource = Join-Path $output 'app-release.apk'
if (-not (Test-Path -LiteralPath $universalSource)) { throw "Missing universal APK: $universalSource" }
$universalDestination = Join-Path $releaseOutput "niraNG-v$versionName-universal.apk"
Copy-Item -LiteralPath $universalSource -Destination $universalDestination -Force
Write-Output $universalDestination
