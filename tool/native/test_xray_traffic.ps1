$ErrorActionPreference='Stop'
$project=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$runtime=Get-Content -LiteralPath (Join-Path $project 'build/checkpoints/20261029-multicore-preparation/test-runtime.json') -Raw | ConvertFrom-Json
$cp=$runtime.jars -join ';'
$base=Join-Path $project 'android/app/src/main/kotlin/dev/nirang/client'
$testBase=Join-Path $project 'android/app/src/test/kotlin/dev/nirang/client'
$files=@('vpn/CoreTrafficDelta.kt','traffic/XrayInboundTraffic.kt','traffic/MeasuredTrafficLedger.kt') | ForEach-Object {Join-Path $base $_}
$tests=@('traffic/XrayInboundTrafficTest.kt','traffic/MeasuredTrafficLedgerTest.kt','vpn/CoreTrafficDeltaTest.kt')
$files+=@($tests | ForEach-Object {Join-Path $testBase $_})
$output=Join-Path $project 'build/native/xray-traffic-tests'
New-Item -ItemType Directory -Force -Path $output | Out-Null
& $runtime.java -cp $cp org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -classpath $cp -d $output @files
if($LASTEXITCODE -ne 0){throw 'Xray traffic tests did not compile'}
$classes=$tests | ForEach-Object {'dev.nirang.client.'+($_ -replace '\.kt$','' -replace '/','.')}
& $runtime.java -cp "$cp;$output" org.junit.runner.JUnitCore @classes
if($LASTEXITCODE -ne 0){throw 'Xray traffic tests failed'}
