param([switch]$All)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$runtimeFile = Join-Path $project 'build/checkpoints/20261029-multicore-preparation/test-runtime.json'
$runtime = Get-Content -LiteralPath $runtimeFile -Raw | ConvertFrom-Json
$classpath = $runtime.jars -join ';'
$out = Join-Path $project 'build/native/singbox-policy-tests'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$source = Join-Path $project 'android/app/src/main/kotlin/dev/nirang/client/cores/singbox'
$tests = Join-Path $project 'android/app/src/test/kotlin/dev/nirang/client/cores/singbox'
$sources = @((Join-Path $source 'SingBoxConfigPolicy.kt'))
if (Test-Path (Join-Path $source 'SingBoxLifecycle.kt')) { $sources += Join-Path $source 'SingBoxLifecycle.kt' }
if (Test-Path (Join-Path $source 'SingBoxSocketProtection.kt')) { $sources += Join-Path $source 'SingBoxSocketProtection.kt' }
if (Test-Path (Join-Path $source 'SingBoxAppPolicy.kt')) { $sources += Join-Path $source 'SingBoxAppPolicy.kt' }
$sources += @(Get-ChildItem -LiteralPath $tests -Filter '*.kt' | ForEach-Object FullName)
& $runtime.java -cp $classpath org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -classpath $classpath -d $out @sources
if ($LASTEXITCODE -ne 0) { throw 'sing-box policy test compilation failed' }
$classes = @(Get-ChildItem -LiteralPath $tests -Filter '*Test.kt' | ForEach-Object { 'dev.nirang.client.cores.singbox.' + $_.BaseName })
& $runtime.java -cp "$out;$classpath" org.junit.runner.JUnitCore @classes
if ($LASTEXITCODE -ne 0) { throw 'sing-box policy tests failed' }
