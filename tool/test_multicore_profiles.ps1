$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$runtime=Get-Content -LiteralPath (Join-Path $project 'build/checkpoints/20261029-multicore-preparation/test-runtime.json') -Raw | ConvertFrom-Json
$cp=$runtime.jars -join ';'
$base=Join-Path $project 'android/app/src/main/kotlin/dev/nirang/client'
$testBase=Join-Path $project 'android/app/src/test/kotlin/dev/nirang/client'
$files=@('model/Models.kt','subscription/SubscriptionParser.kt','subscription/TlsCertificatePolicy.kt','subscription/StrictProfileJson.kt','subscription/CustomProfileCodec.kt','subscription/CustomXrayConfig.kt','subscription/AetherProfiles.kt','subscription/LocalAetherProfileStore.kt','cores/aether/AetherOptions.kt','cores/aether/PsiphonRegions.kt') | ForEach-Object {Join-Path $base $_}
if(Test-Path (Join-Path $base 'vpn/CoreTrafficDelta.kt')){$files+=Join-Path $base 'vpn/CoreTrafficDelta.kt'}
$files+=@('vpn/AetherPreparationCoordinator.kt','vpn/CustomCoreSwitchPolicy.kt') | ForEach-Object {Join-Path $base $_}
$tests=@('subscription/CustomProfileCodecTest.kt','subscription/CustomXrayConfigTest.kt','subscription/AetherProfilesTest.kt','subscription/LocalAetherProfileStoreTest.kt','subscription/SubscriptionParserTest.kt','vpn/CoreTrafficDeltaTest.kt','vpn/AetherPreparationCoordinatorTest.kt','vpn/CustomCoreSwitchPolicyTest.kt')
$files+=@($tests | ForEach-Object {Join-Path $testBase $_})
$output=Join-Path $project 'build/native/multicore-profile-tests'
New-Item -ItemType Directory -Force -Path $output | Out-Null
& $runtime.java -cp $cp org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect -jvm-target 17 -classpath $cp -d $output @files
if($LASTEXITCODE -ne 0){throw 'Multicore profile tests did not compile'}
$classes=$tests | ForEach-Object {'dev.nirang.client.'+($_ -replace '\.kt$','' -replace '/','.')}
$resources=Join-Path $project 'android/app/src/test/resources'
& $runtime.java -cp "$cp;$output;$resources" org.junit.runner.JUnitCore @classes
if($LASTEXITCODE -ne 0){throw 'Multicore profile tests failed'}
