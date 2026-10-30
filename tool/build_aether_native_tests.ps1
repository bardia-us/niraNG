param([ValidateSet('nira_https_requires_peer_authentication','nira_https','nira_hostname')][string]$Filter = 'nira_https')
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$source = Join-Path $project 'build/aether-upstream/Aether'
$vcvars = 'C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvars64.bat'
$lines = & cmd.exe /d /s /c "`"$vcvars`" && set"
foreach($line in $lines) { if($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') } }
$env:RUSTUP_HOME = Join-Path $project 'build/aether-toolchain/rustup'
$env:CARGO_HOME = Join-Path $project 'build/aether-toolchain/cargo'
$env:LIBCLANG_PATH = Join-Path $project 'build/aether-toolchain/libclang/libclang-18.1.1.data/platlib/clang/native'
$env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER = 'C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.44.35207/bin/Hostx64/x64/link.exe'
$env:CMAKE_GENERATOR = 'Ninja'
$env:PATH = "$env:CARGO_HOME/bin;D:/Android/Sdk/cmake/3.22.1/bin;$(Join-Path $project 'build/aether-toolchain/nasm/nasm-2.16.03');$env:PATH;C:/Program Files/Git/usr/bin"
# The pinned boring-sys source contains a NASM-only whitespace bug in its generated include flag.
# Use its task-local, post-quantum-patched source; quote the include, changing no crypto source.
$boring = Get-ChildItem "$source/aether/target/debug/build" -Filter 'boring-sys-*' -Directory |
    ForEach-Object { Join-Path $_.FullName 'out/boringssl' } | Where-Object { Test-Path "$_/CMakeLists.txt" } | Select-Object -First 1
if($boring) {
    $cmake = Join-Path $boring 'CMakeLists.txt'
    $old = 'set(CMAKE_ASM_NASM_FLAGS "${CMAKE_ASM_NASM_FLAGS} -I${CMAKE_CURRENT_SOURCE_DIR}/gen/")'
    $new = 'set(CMAKE_ASM_NASM_FLAGS "${CMAKE_ASM_NASM_FLAGS} -I\"${CMAKE_CURRENT_SOURCE_DIR}/gen/\"")'
    $text = [IO.File]::ReadAllText($cmake)
    [IO.File]::WriteAllText($cmake, $text.Replace($old,$new), [Text.UTF8Encoding]::new($false))
    $env:HOST_BORING_BSSL_SOURCE_PATH = $boring
    $env:HOST_BORING_BSSL_ASSUME_PATCHED = '1'
}
& "$env:CARGO_HOME/bin/cargo.exe" +1.99.1 test --locked --manifest-path "$source/aether/Cargo.toml" --lib $Filter
if($LASTEXITCODE -ne 0) { throw 'Aether native TLS regression tests failed' }
if($Filter -eq 'nira_https') {
    @{securityPatchSha256=(Get-FileHash (Join-Path $PSScriptRoot 'aether-https-peer.patch') -Algorithm SHA256).Hash.ToLowerInvariant();filter=$Filter;utc=[DateTime]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $project 'build/aether-upstream/tls-tests.json') -Encoding utf8NoBOM
}
