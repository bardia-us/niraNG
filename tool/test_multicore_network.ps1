param([switch]$Native)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$runtime=Get-Content -LiteralPath (Join-Path $project 'build/checkpoints/20261029-multicore-preparation/test-runtime.json') -Raw | ConvertFrom-Json
$cp=$runtime.jars -join ';'
$base=Join-Path $project 'android/app/src/main/kotlin/dev/nirang/client'
$testBase=Join-Path $project 'android/app/src/test/kotlin/dev/nirang/client'
$files=@('model/Models.kt','subscription/StrictProfileJson.kt','subscription/CustomProfileCodec.kt','subscription/CustomXrayConfig.kt','subscription/AetherProfiles.kt','cores/aether/AetherOptions.kt','cores/aether/PsiphonRegions.kt','cores/singbox/SingBoxConfigPolicy.kt','ping/CustomProbeConfig.kt','ping/PrivateProbePorts.kt','ping/ProbeCancellation.kt','ping/SocksHttpLatencyProbe.kt','vpn/OwnedCoreLifecycle.kt','vpn/CoreTeardownFence.kt','vpn/VpnTaskRunner.kt','vpn/AetherPreparationCoordinator.kt') | ForEach-Object {Join-Path $base $_}
$tests=@('ping/CustomProbeConfigTest.kt','ping/SocksHttpLatencyProbeTest.kt','vpn/OwnedCoreLifecycleTest.kt','vpn/CoreTeardownFenceTest.kt','vpn/VpnTaskRunnerTest.kt','vpn/AetherPreparationCoordinatorTest.kt')
$files+=@($tests | ForEach-Object {Join-Path $testBase $_})
$output=Join-Path $project 'build/native/network-tests'
New-Item -ItemType Directory -Force -Path $output | Out-Null
& $runtime.java -cp $cp org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -classpath $cp -d $output @files
if($LASTEXITCODE -ne 0){throw 'Multicore network tests did not compile'}
$classes=$tests | ForEach-Object {'dev.nirang.client.'+($_ -replace '\.kt$','' -replace '/','.')}
& $runtime.java -cp "$cp;$output" org.junit.runner.JUnitCore @classes
if($LASTEXITCODE -ne 0){throw 'Multicore network tests failed; localhost sockets must be permitted'}
if($Native) {
    $nativeRoot=Join-Path $project 'build/native'
    $source=(Resolve-Path -LiteralPath (Join-Path $nativeRoot 'sing-box')).Path
    if(-not $source.StartsWith($project+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Native test checkout is outside workspace'}
    $env:GOROOT=Join-Path $nativeRoot 'toolchain/go'
    $env:GOPATH=Join-Path $nativeRoot 'gopath'
    $env:GOMODCACHE=Join-Path $nativeRoot 'gomod'
    $env:GOCACHE=Join-Path $nativeRoot 'gocache'
    $env:GOTOOLCHAIN='local';$env:GOPROXY='off';$env:CGO_ENABLED='0'
    $env:TEMP=Join-Path $project 'build/jvm-temp';$env:TMP=$env:TEMP
    New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
    $names=@('nirang_probe.go','nirang_probe_test.go')
    foreach($name in $names){if(Test-Path -LiteralPath (Join-Path $source "experimental/libbox/$name")){throw 'Unexpected native test source already exists'}}
    try {
        foreach($name in $names){Copy-Item -LiteralPath (Join-Path $PSScriptRoot "native/singbox/$name") -Destination (Join-Path $source "experimental/libbox/$name")}
        Push-Location -LiteralPath $source
        try {& "$env:GOROOT/bin/go.exe" test -run '^TestNirangProbe' -count=1 -timeout=30s ./experimental/libbox
            if($LASTEXITCODE -ne 0){throw 'Native isolated probe smoke test failed'}
        } finally {Pop-Location}
    } finally {foreach($name in $names){$target=Join-Path $source "experimental/libbox/$name";if(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target}}}
}
