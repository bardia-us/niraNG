param(
    [string]$RuntimeManifest = 'build/checkpoints/20261029-multicore-preparation/test-runtime.json'
)
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $taskRoot
try {
    $runtime = Get-Content -LiteralPath $RuntimeManifest -Raw | ConvertFrom-Json
    $cp = $runtime.jars -join ';'
    $output = Join-Path $taskRoot 'build/jvm-temp/aether-restart-host'
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    $productionRoot = 'android/app/src/main/kotlin/dev/nirang/client'
    $testRoot = 'android/app/src/test/kotlin/dev/nirang/client'
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'vpn_restart_tests') -Filter '*.kt' | ForEach-Object FullName)
    $sources += @(
        "$productionRoot/vpn/VpnRestartCoordinator.kt", "$productionRoot/vpn/AsyncNativeStop.kt",
        "$productionRoot/vpn/AetherProfileSave.kt", "$productionRoot/vpn/AetherPreparationCoordinator.kt",
        "$productionRoot/vpn/CoreTeardownFence.kt", "$productionRoot/vpn/ConnectionOperationGate.kt",
        "$productionRoot/cores/aether/AetherOptions.kt", "$productionRoot/cores/aether/PsiphonRegions.kt",
        "$productionRoot/cores/aether/AetherProcessOwner.kt",
        "$testRoot/vpn/AetherProfileSaveTest.kt", "$testRoot/vpn/AetherPreparationCoordinatorTest.kt",
        "$testRoot/vpn/CoreTeardownFenceTest.kt", "$testRoot/vpn/ConnectionOperationGateTest.kt",
        "$testRoot/cores/aether/AetherProcessOwnerTest.kt"
    )
    & $runtime.java '-cp' $cp org.jetbrains.kotlin.cli.jvm.K2JVMCompiler '-no-stdlib' '-no-reflect' '-classpath' $cp '-d' $output @sources
    if ($LASTEXITCODE -ne 0) { throw "Host Kotlin compilation failed: $LASTEXITCODE" }
    & $runtime.java '-cp' ($cp+';'+$output) org.junit.runner.JUnitCore `
        dev.nirang.client.vpn.VpnRestartCoordinatorHostTest `
        dev.nirang.client.vpn.AetherProfileSaveTest `
        dev.nirang.client.vpn.AetherPreparationCoordinatorTest `
        dev.nirang.client.vpn.CoreTeardownFenceTest `
        dev.nirang.client.vpn.ConnectionOperationGateTest `
        dev.nirang.client.cores.aether.AetherProcessOwnerTest
    if ($LASTEXITCODE -ne 0) { throw "Host restart tests failed: $LASTEXITCODE" }
} finally { Pop-Location }
