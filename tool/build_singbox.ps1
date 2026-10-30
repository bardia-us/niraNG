param(
    [string]$GoRoot = '',
    [string]$AndroidSdk = 'D:/Android/Sdk',
    [string]$JavaHome = 'C:/Program Files/Android/Android Studio/jbr',
    [string]$NdkVersion = '28.2.13676358',
    [string]$GoProxy = 'https://proxy.golang.org,direct',
    [string]$Target = 'android/arm,android/arm64,android/amd64'
)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$native = Join-Path $project 'build/native'
$source = Join-Path $native 'sing-box'
$commit = 'c005f35300ce76427dc285481ec5695f5b179cd2'
$version = '1.14.4'
if (!$GoRoot) { $GoRoot = Join-Path $native 'toolchain/go' }
$go = Join-Path $GoRoot 'bin/go.exe'
if (!(Test-Path -LiteralPath $go)) { throw 'Go 1.25.5 is required; download an official archive and verify its go.dev SHA256 first.' }
if (!(Test-Path -LiteralPath (Join-Path $source 'go.mod'))) {
    & git clone --depth 1 --branch "v$version" https://github.com/SagerNet/sing-box.git $source
    if ($LASTEXITCODE -ne 0) { throw 'Official source checkout failed' }
}
$actual = (& git -C $source rev-parse HEAD).Trim()
if ($actual -ne $commit) { throw "Unexpected sing-box source revision: $actual" }
if ((& git -C $source status --porcelain).Count -ne 0) { throw 'sing-box checkout has local modifications' }
$env:GOROOT = (Resolve-Path -LiteralPath $GoRoot).Path
$env:GOPATH = Join-Path $native 'gopath'
$env:GOMODCACHE = Join-Path $native 'gomod'
$env:GOCACHE = Join-Path $native 'gocache'
$env:GOTOOLCHAIN = 'local'
$env:GOPROXY = $GoProxy
$env:GOSUMDB = 'sum.golang.org'
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_NDK_HOME = Join-Path $AndroidSdk "ndk/$NdkVersion"
$env:JAVA_HOME = $JavaHome
$env:PATH = "$GoRoot/bin;$env:GOPATH/bin;$JavaHome/bin;$env:PATH"
$env:GOFLAGS = '-mod=readonly'
if ((& $go version) -notmatch 'go1\.25\.5 ') { throw 'Build requires pinned Go 1.25.5' }
Push-Location -LiteralPath $source
$originalMod = [IO.File]::ReadAllBytes((Join-Path $source 'go.mod'))
$originalSum = [IO.File]::ReadAllBytes((Join-Path $source 'go.sum'))
$probePatch = Join-Path $PSScriptRoot 'native/singbox/nirang_probe.go'
$probeSource = Join-Path $source 'experimental/libbox/nirang_probe.go'
if (Test-Path -LiteralPath $probeSource) { throw 'Unexpected existing sing-box probe adapter' }
try {
    Copy-Item -LiteralPath $probePatch -Destination $probeSource
    # Both tools are built below from the verified, namespace-isolated module.
    & $go mod download github.com/sagernet/gomobile@v0.1.12
    if ($LASTEXITCODE -ne 0) { throw 'Verified gomobile source download failed' }
    & $go mod download
    if ($LASTEXITCODE -ne 0) { throw 'Verified Go dependency download failed' }
    & $go mod verify
    if ($LASTEXITCODE -ne 0) { throw 'Go dependency verification failed' }
    $mobileSource = Join-Path $env:GOMODCACHE 'github.com/sagernet/gomobile@v0.1.12'
    $patchedMobile = Join-Path $native ('gomobile-nirasbgo-v0.1.12-' + [Guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $patchedMobile) { throw 'Use a fresh native build directory or remove only the prior generated gomobile-nirasbgo-v0.1.12 directory before rebuilding.' }
    Copy-Item -LiteralPath $mobileSource -Destination $patchedMobile -Recurse
    & python (Join-Path $PSScriptRoot 'build_singbox_namespace.py') $patchedMobile
    if ($LASTEXITCODE -ne 0) { throw 'gomobile namespace isolation failed' }
    Push-Location -LiteralPath $patchedMobile
    try {
        & $go build -o (Join-Path $env:GOPATH 'bin/gomobile.exe') ./cmd/gomobile
        if ($LASTEXITCODE -ne 0) { throw 'Isolated gomobile build failed' }
        & $go build -o (Join-Path $env:GOPATH 'bin/gobind.exe') ./cmd/gobind
        if ($LASTEXITCODE -ne 0) { throw 'Isolated gobind build failed' }
    } finally { Pop-Location }
    # Temporary build-checkout replacement lets native C support use the same isolated namespace.
    & $go mod edit "-replace=github.com/sagernet/gomobile=$patchedMobile"
    if ($LASTEXITCODE -ne 0) { throw 'Local verified gomobile replacement failed' }
    # Explicit supported protocol set; omitted optional native integrations fail native validation.
    $tags = 'with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_low_memory'
    $ldflags = "-X github.com/sagernet/sing-box/constant.Version=$version -checklinkname=0 -s -w -buildid="
    $output = Join-Path $source 'libbox.aar'
    & (Join-Path $env:GOPATH 'bin/gomobile.exe') bind -v -o $output -target $Target -androidapi 24 -javapkg io.nekohasekai -libname box -trimpath -buildvcs=false -ldflags $ldflags -tags $tags ./experimental/libbox
    if ($LASTEXITCODE -ne 0) { throw 'Android libbox native build failed' }
    & python (Join-Path $PSScriptRoot 'build_singbox_verify.py') $output (Join-Path $project 'android/app/libs/libv2ray.aar')
    if ($LASTEXITCODE -ne 0) { throw 'Native ABI/runtime isolation verification failed' }
    $destination = Join-Path $project 'android/app/libs/libbox.aar'
    Copy-Item -LiteralPath $output -Destination $destination -Force
    [ordered]@{
        version=$version; source='https://github.com/SagerNet/sing-box'; commit=$commit
        go='go1.25.5'; gomobile='v0.1.12'; ndk=$NdkVersion; androidApi=24
        target=$Target; tags=$tags; artifact='android/app/libs/libbox.aar'
        sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        license='GPL-3.0-or-later'; tlsCompatibilityOverride=$false; runtimeNamespace='nirasbgo'
        namespacePatchSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'build_singbox_namespace.py') -Algorithm SHA256).Hash.ToLowerInvariant()
        probePatchSha256=(Get-FileHash -LiteralPath $probePatch -Algorithm SHA256).Hash.ToLowerInvariant()
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $project 'android/app/libs/libbox-build.json') -Encoding UTF8
} finally {
    [IO.File]::WriteAllBytes((Join-Path $source 'go.mod'), $originalMod)
    [IO.File]::WriteAllBytes((Join-Path $source 'go.sum'), $originalSum)
    if (Test-Path -LiteralPath $probeSource) { Remove-Item -LiteralPath $probeSource -Force }
    Pop-Location
}
