$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$runtime = Get-Content -LiteralPath (Join-Path $project 'build/checkpoints/20261029-multicore-preparation/test-runtime.json') -Raw | ConvertFrom-Json
$classpath = ($runtime.jars + @('D:/Android/Sdk/platforms/android-36/android.jar')) -join ';'
$out = Join-Path $project 'build/native/aether-policy-tests'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$source = Join-Path $project 'android/app/src/main/kotlin/dev/nirang/client/cores/aether'
$tests = Join-Path $project 'android/app/src/test/kotlin/dev/nirang/client/cores/aether'
$sources = @(Get-ChildItem -LiteralPath $source -Filter '*.kt' -ErrorAction SilentlyContinue | ForEach-Object FullName)
$sources += @(Get-ChildItem -LiteralPath $tests -Filter '*.kt' | ForEach-Object FullName)
& $runtime.java -cp $classpath org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -classpath $classpath -d $out @sources
if ($LASTEXITCODE -ne 0) { throw 'Aether test compilation failed' }
$classes = @(Get-ChildItem -LiteralPath $tests -Filter '*Test.kt' | ForEach-Object { 'dev.nirang.client.cores.aether.' + $_.BaseName })
$resources = Join-Path $project 'android/app/src/test/resources'
& $runtime.java -cp "$out;$classpath;$resources" org.junit.runner.JUnitCore @classes
if ($LASTEXITCODE -ne 0) { throw 'Aether policy tests failed' }
