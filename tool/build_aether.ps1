param(
    [string]$Ndk = 'D:/Android/Sdk/ndk/28.2.13676358',
    [ValidateSet('arm64-v8a','armeabi-v7a','x86_64')][string[]]$Abis = @('arm64-v8a','armeabi-v7a','x86_64'),
    [switch]$Stage
)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$source = Join-Path $project 'build/aether-upstream/Aether'
$pin = 'd58f9d568083129ce2c767c85054021eb3ee6a38'
if (!(Test-Path "$source/aether/Cargo.lock")) { throw 'Clone patterniha/Aether v2.4.0 into build/aether-upstream/Aether first' }
if ((& git -C $source rev-parse HEAD).Trim() -ne $pin) { throw 'Unexpected Aether source revision' }
$patch = Join-Path $PSScriptRoot 'aether-https-peer.patch'
& git -C $source apply --reverse --check $patch 2>$null
if ($LASTEXITCODE -ne 0) {
    & git -C $source apply --check $patch
    if ($LASTEXITCODE -ne 0) { throw 'Aether security patch does not apply cleanly' }
    & git -C $source apply $patch
    if ($LASTEXITCODE -ne 0) { throw 'Aether security patch failed' }
}
$env:RUSTUP_HOME = Join-Path $project 'build/aether-toolchain/rustup'
$env:CARGO_HOME = Join-Path $project 'build/aether-toolchain/cargo'
$cargo = Join-Path $env:CARGO_HOME 'bin/cargo.exe'
& "$env:CARGO_HOME/bin/rustfmt.exe" +1.99.1 --version | Out-Null
if($LASTEXITCODE -ne 0) {throw 'Install the pinned rustfmt component: boring-sys requires formatted generated bindings on armv7'}
$env:LIBCLANG_PATH = Join-Path $project 'build/aether-toolchain/libclang/libclang-18.1.1.data/platlib/clang/native'
$env:PATH = "$env:CARGO_HOME/bin;D:/Android/Sdk/cmake/3.22.1/bin;C:/Program Files/Git/usr/bin;$env:PATH"
$env:CMAKE_GENERATOR = 'Ninja'
$env:ANDROID_NDK_HOME = $Ndk
$toolchain = (Join-Path $Ndk 'toolchains/llvm/prebuilt/windows-x86_64').Replace('\','/')
$triples = @{'arm64-v8a'='aarch64-linux-android';'armeabi-v7a'='armv7-linux-androideabi';'x86_64'='x86_64-linux-android'}
$manifest = [ordered]@{source='https://github.com/patterniha/Aether';commit=$pin;version='2.4.0';rust='1.99.1';ndk='28.2.13676358';securityPatch='nira-https-peer-v1';securityPatchSha256=(Get-FileHash $patch -Algorithm SHA256).Hash.ToLowerInvariant();abis=[ordered]@{}}
if($Stage) {
    $testEvidence = Get-Content -LiteralPath (Join-Path $project 'build/aether-upstream/tls-tests.json') -Raw | ConvertFrom-Json
    if($testEvidence.securityPatchSha256 -ne $manifest.securityPatchSha256) {throw 'Run all native TLS tests on this exact patch before staging'}
    $changes = @(& git -C $source diff --name-only)
    if($changes.Count -ne 1 -or $changes[0] -ne 'aether/src/https.rs') {throw 'Unexpected modifications in the pinned native source'}
    $artifacts = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'aether-artifacts.lock.json') -Raw | ConvertFrom-Json
    $manifest.serverEntriesSha256 = $artifacts.serverEntriesSha256
    $manifest.serverEntriesCount = $artifacts.serverEntriesCount
    $manifest.psiphonSource = $artifacts.psiphonSource
    $manifest.psiphonCommit = $artifacts.psiphonCommit
}
foreach($abi in $Abis) {
    $triple = $triples[$abi]
    $target = if($abi -eq 'armeabi-v7a') {'armv7a-linux-androideabi29'} else {"${triple}29"}
    $under = $triple.Replace('-','_')
    $upper = $under.ToUpperInvariant()
    [Environment]::SetEnvironmentVariable("CARGO_TARGET_${upper}_LINKER", "$toolchain/bin/$target-clang.cmd", 'Process')
    [Environment]::SetEnvironmentVariable("CARGO_TARGET_${upper}_RUSTFLAGS", '-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-Wl,-z,common-page-size=16384', 'Process')
    [Environment]::SetEnvironmentVariable("CC_$under", "$toolchain/bin/clang.exe", 'Process')
    [Environment]::SetEnvironmentVariable("CXX_$under", "$toolchain/bin/clang++.exe", 'Process')
    [Environment]::SetEnvironmentVariable("CFLAGS_$under", "--target=$target", 'Process')
    [Environment]::SetEnvironmentVariable("CXXFLAGS_$under", "--target=$target", 'Process')
    [Environment]::SetEnvironmentVariable("AR_$under", "$toolchain/bin/llvm-ar.exe", 'Process')
    [Environment]::SetEnvironmentVariable("BORING_BSSL_RUST_CPPLIB_$under", 'static:-bundle=c++', 'Process')
    $resource = (Get-ChildItem "$toolchain/lib/clang" -Directory | Select-Object -First 1).FullName.Replace('\','/')
    $headers = if($abi -eq 'armeabi-v7a') {'arm-linux-androideabi'} else {$triple}
    [Environment]::SetEnvironmentVariable("BINDGEN_EXTRA_CLANG_ARGS_$under", "--target=$target --sysroot=$toolchain/sysroot -isystem $resource/include -isystem $toolchain/sysroot/usr/include -isystem $toolchain/sysroot/usr/include/$headers", 'Process')
    & $cargo +1.99.1 build --locked --release --manifest-path "$source/aether/Cargo.toml" --target $triple --bin aether
    if($LASTEXITCODE -ne 0) {throw "Aether build failed for $abi"}
    $binary = "$source/aether/target/$triple/release/aether"
    $dynamic = & "$toolchain/bin/llvm-readelf.exe" --dynamic-table $binary
    if($LASTEXITCODE -ne 0 -or ($dynamic -match 'libc\+\+_shared.so')) {throw 'Aether requires an unpackaged shared C++ runtime'}
    if($Stage) {
        $dest = Join-Path $project "android/app/src/main/jniLibs/$abi"
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item -LiteralPath $binary -Destination "$dest/libaether_nira.so"
        if(!(Test-Path "$dest/libpsiphon_nira.so")) {throw 'Stage checksum-verified official Psiphon executable first'}
        if((Get-FileHash "$dest/libpsiphon_nira.so").Hash.ToLowerInvariant() -ne $artifacts.abis.$abi.psiphonSha256) {throw 'Official Psiphon executable hash mismatch'}
        $manifest.abis[$abi] = [ordered]@{aetherSha256=(Get-FileHash "$dest/libaether_nira.so").Hash.ToLowerInvariant();psiphonSha256=(Get-FileHash "$dest/libpsiphon_nira.so").Hash.ToLowerInvariant()}
    }
}
if($Stage) {
    $manifestPath = Join-Path $project 'android/app/src/main/assets/aether-runtime.json'
    $temporaryManifest = Join-Path $project 'android/app/src/main/assets/.aether-runtime.json.tmp'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporaryManifest -Encoding utf8NoBOM
    [IO.File]::Move($temporaryManifest, $manifestPath, $true)
}
