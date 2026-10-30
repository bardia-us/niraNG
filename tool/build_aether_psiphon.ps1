param([string]$GoProxy = 'https://proxy.golang.org,direct')
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$source = Join-Path $project 'build/aether-upstream/psiphon'
$pin = '83aa73b9b982e7421e00117f5b0c5aceb5dda452'
if((& git -C $source rev-parse HEAD).Trim() -ne $pin) {throw 'Unexpected Psiphon source revision'}
if(@(& git -C $source status --porcelain).Count -ne 0) {throw 'Psiphon source must be clean'}
$go = Join-Path $project 'build/native/toolchain/go/bin/go.exe'
# Go authenticates the exact requested host toolchain module through its checksum database.
$env:GOTOOLCHAIN = 'go1.26.3'
$env:GOSUMDB = 'sum.golang.org'
$env:GOPROXY = $GoProxy
$env:GOPATH = Join-Path $project 'build/aether-toolchain/go-path'
$env:GOMODCACHE = Join-Path $project 'build/aether-toolchain/go-mod'
$env:GOCACHE = Join-Path $project 'build/aether-toolchain/go-cache'
$env:GOMAXPROCS = '4'
$env:GOOS = 'linux'
$env:GOARCH = 'amd64'
$env:CGO_ENABLED = '0'
$env:GOFLAGS = '-mod=vendor -p=4'
$destination = Join-Path $project 'build/aether-upstream/psiphon-built/x86_64/psiphon-tunnel-core'
New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
Push-Location -LiteralPath $source
try {
    & $go build -trimpath -buildvcs=true -ldflags '-s -w -R 16384' -o $destination ./ConsoleClient
    if($LASTEXITCODE -ne 0) {throw 'Pinned Psiphon x86_64 build failed'}
    & $go version -m $destination
    if($LASTEXITCODE -ne 0) {throw 'Psiphon build metadata check failed'}
} finally {Pop-Location}
Write-Output 'Built pinned x86_64 Psiphon; inspect 16KiB ELF alignment before replacing the official baseline.'
