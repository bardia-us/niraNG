param(
    [string]$GoRoot = '',
    [string]$AndroidSdk = 'D:/Android/Sdk',
    [string]$JavaHome = 'C:/Program Files/Android/Android Studio/jbr',
    [string]$NdkVersion = '28.2.13676358',
    [string]$GoProxy = 'https://proxy.golang.org,direct',
    [switch]$Bundle
)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$native=Join-Path $project 'build/native'
$build=Join-Path $native 'xray-pinned'
$commit='5bad0b55f2d002ace13657db11937bddcf48bc3b'
$source=Join-Path $build 'source'
$archive=Join-Path $build 'source.zip'
$upstreamSha='3ce0e6e2bf2dd31701de8706a320495c2fbb68760cc5f667cde4fc69d8dc2a0d'
$oldSha='f52ae053281b9c3e5f01cab1c92b6ae7d750b05a12bf39b6b3649bf931a570da'
New-Item -ItemType Directory -Force -Path $build | Out-Null
if(!(Test-Path -LiteralPath $archive)){
    & curl.exe --fail --location --connect-timeout 15 --max-time 300 -o $archive "https://codeload.github.com/patterniha/AndroidLibXrayLite/zip/$commit"
    if($LASTEXITCODE -ne 0){throw 'Pinned wrapper source download failed'}
}
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $upstreamSha){throw 'Pinned wrapper source archive mismatch'}
$original=Join-Path $build 'libv2ray-original-v26.8.28.aar'
$destination=Join-Path $project 'android/app/libs/libv2ray.aar'
if(!(Test-Path -LiteralPath $original)){
    if((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $oldSha){throw 'Original AAR checkpoint is missing and bundled AAR is not the verified original'}
    Copy-Item -LiteralPath $destination -Destination $original
}
if((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant() -ne $oldSha){throw 'Original AAR checkpoint mismatch'}
if(!$GoRoot){$GoRoot=Join-Path $native 'gomod/golang.org/toolchain@v0.0.1-go1.26.7.windows-amd64'}
$env:GOROOT=(Resolve-Path -LiteralPath $GoRoot).Path
$toolchainArchive=Join-Path $native 'gomod/cache/download/golang.org/toolchain/@v/v0.0.1-go1.26.7.windows-amd64.zip'
& python (Join-Path $PSScriptRoot 'build_xray_toolchain_verify.py') $toolchainArchive $env:GOROOT
if($LASTEXITCODE -ne 0){throw 'Exact Go1.26.7 distribution verification failed'}
$go=Join-Path $env:GOROOT 'bin/go.exe'
if((& $go version) -notmatch 'go1\.26\.7 '){throw 'Telemetry rebuild requires exact upstream Go1.26.7'}
$env:GOPATH=Join-Path $native 'gopath'
$env:GOMODCACHE=Join-Path $native 'gomod'
$env:GOCACHE=Join-Path $native 'gocache'
$env:GOTOOLCHAIN='local'
$env:GOPROXY=$GoProxy
$env:GOSUMDB='sum.golang.org https://sum.golang.org'
$env:ANDROID_HOME=$AndroidSdk
$env:ANDROID_NDK_HOME=Join-Path $AndroidSdk "ndk/$NdkVersion"
$env:JAVA_HOME=$JavaHome
$env:PATH="$build;$GoRoot/bin;$JavaHome/bin;$env:PATH"
$env:GOFLAGS='-mod=readonly -buildvcs=false'
& python -c 'import pathlib,sys,zipfile; archive,source,original=sys.argv[1:]; source=pathlib.Path(source); source.mkdir(exist_ok=True); z=zipfile.ZipFile(archive); prefix=z.namelist()[0]; [(source/pathlib.PurePosixPath(n).name).write_bytes(z.read(n)) for n in z.namelist() if n.startswith(prefix) and "/" not in n[len(prefix):] and n.endswith((".go",".mod",".sum"))]; a=zipfile.ZipFile(original); (source/"assets").mkdir(exist_ok=True); [(source/n).write_bytes(a.read(n)) for n in a.namelist() if n.startswith("assets/") and not n.endswith("/")]' $archive $source $original
if($LASTEXITCODE -ne 0){throw 'Pinned source extraction failed'}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'native/xray/nirang_traffic.go') -Destination (Join-Path $source 'nirang_traffic.go')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'native/xray/nirang_traffic_test.go') -Destination (Join-Path $source 'nirang_traffic_test.go')
Push-Location -LiteralPath $source
try {
    & $go mod download
    if($LASTEXITCODE -ne 0){throw 'Pinned Go dependencies unavailable'}
    & $go mod verify
    if($LASTEXITCODE -ne 0){throw 'Go dependency checksum verification failed'}
    $cachedCore=Join-Path $env:GOMODCACHE 'github.com/patterniha/xray-core@v0.0.0-20260828162656-3115a981a8b6'
    $coreCopy=Join-Path $build 'core-source'
    & python (Join-Path $PSScriptRoot 'build_xray_core_copy.py') $cachedCore $coreCopy
    if($LASTEXITCODE -ne 0){throw 'Pinned core workspace copy verification failed'}
    $overlayDirectory=Join-Path $build 'tun-overlay'
    & python (Join-Path $PSScriptRoot 'build_xray_overlay.py') $project $coreCopy $overlayDirectory
    if($LASTEXITCODE -ne 0){throw 'TUN packet metadata compatibility overlay failed'}
    $originalWrapperMod=[IO.File]::ReadAllBytes((Join-Path $source 'go.mod'))
    & $go mod edit "-replace=github.com/xtls/xray-core=$coreCopy"
    if($LASTEXITCODE -ne 0){throw 'Pinned local core replacement failed'}
    $overlay=Join-Path $overlayDirectory 'overlay.json'
    $env:GOFLAGS='-mod=readonly -buildvcs=false "-overlay='+$overlay+'"'
    & $go test -v ./
    if($LASTEXITCODE -ne 0){throw 'Pinned Xray telemetry regressions failed'}
    & $go test github.com/xtls/xray-core/proxy/tun -run 'TestHandlerCountsTunConnectionTraffic|TestTelemetry' -v
    if($LASTEXITCODE -ne 0){throw 'Pinned TUN byte accounting regression failed'}
    $mobile=Join-Path $env:GOMODCACHE 'golang.org/x/mobile@v0.0.0-20260709172247-6129f5bee9d5'
    Push-Location -LiteralPath $mobile
    try {
        & $go build -o (Join-Path $build 'gomobile.exe') ./cmd/gomobile
        if($LASTEXITCODE -ne 0){throw 'Pinned gomobile build failed'}
        & $go build -o (Join-Path $build 'gobind.exe') ./cmd/gobind
        if($LASTEXITCODE -ne 0){throw 'Pinned gobind build failed'}
    } finally {Pop-Location}
    $output=Join-Path $build 'libv2ray-telemetry.aar'
    & (Join-Path $build 'gomobile.exe') bind -v -o $output -target android/arm,android/arm64,android/386,android/amd64 -androidapi 24 -trimpath -ldflags '-s -w -buildid= -checklinkname=0' ./
    if($LASTEXITCODE -ne 0){throw 'Pinned Xray four-ABI build failed'}
    & python (Join-Path $PSScriptRoot 'build_xray_verify.py') $output $original $go (Join-Path $JavaHome 'bin/javap.exe')
    if($LASTEXITCODE -ne 0){throw 'Pinned native ABI/API/assets verification failed'}
    $metadata=[ordered]@{source='https://github.com/patterniha/AndroidLibXrayLite';commit=$commit;sourceArchiveSha256=$upstreamSha;coreCommit='3115a981a8b6';coreModule='github.com/patterniha/xray-core@v0.0.0-20260828162656-3115a981a8b6';go='go1.26.7';upstreamArtifactGo='go1.26.7';goToolchainModule='golang.org/toolchain@v0.0.1-go1.26.7.windows-amd64';goToolchainSum='h1:lbbNIUXD76tVDW850cljAE22gUR0RdmZ0aVf0cjKnTo=';gomobile='v0.0.0-20260709172247-6129f5bee9d5';ndk=$NdkVersion;androidApi=24;abis=@('arm64-v8a','armeabi-v7a','x86','x86_64');originalSha256=$oldSha;originalAssetBytesRetained=$true;tlsCompatibilityOverride=$false;telemetryPatchSha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'native/xray/nirang_traffic.go') -Algorithm SHA256).Hash.ToLowerInvariant();sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()}
    $metadata['goToolchainArchiveSha256']='ccada8b506d8a99124bd4654f15c74974c5d32f93b705b5c6081b76d629026b4'
    $metadata['wrapperProvenance']='Selected verified Aug28 rebuild base; original wrapper is local(devel), with no embedded VCS commit. Source graph and public API are checked against the original artifact.'
    $metadata['coreLocalReplacement']='verified unmodified pinned source copy plus declared TUN UDP metadata overlay'
    $metadata['coreSourceManifestSha256']=(Get-Content -LiteralPath (Join-Path $build 'core-source-manifest.json') -Raw | ConvertFrom-Json).manifestSha256
    $metadata['corePatch']=Get-Content -LiteralPath (Join-Path $overlayDirectory 'overlay-metadata.json') -Raw | ConvertFrom-Json
    $metadata['nativeVerification']=Get-Content -LiteralPath ([IO.Path]::ChangeExtension($output,'verification.json')) -Raw | ConvertFrom-Json
    $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $build 'libv2ray-build.json') -Encoding UTF8
    if($Bundle){
        Copy-Item -LiteralPath $output -Destination $destination -Force
        Copy-Item -LiteralPath (Join-Path $build 'libv2ray-build.json') -Destination (Join-Path $project 'android/app/libs/libv2ray-build.json') -Force
    }
} finally {
    if($null -ne $originalWrapperMod){[IO.File]::WriteAllBytes((Join-Path $source 'go.mod'),$originalWrapperMod)}
    Pop-Location
}
