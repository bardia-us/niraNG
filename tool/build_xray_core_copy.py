"""Copy and verify every pinned core file before using a declared local overlay."""
import hashlib,json,pathlib,shutil,sys
cached,copy=map(pathlib.Path,sys.argv[1:3])
if not copy.exists():shutil.copytree(cached,copy)
source={p.relative_to(cached).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in cached.rglob('*') if p.is_file()}
actual={p.relative_to(copy).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in copy.rglob('*') if p.is_file()}
assert actual==source,'Local pinned core copy differs from checksum-verified module cache'
manifest={'module':'github.com/patterniha/xray-core@v0.0.0-20260828162656-3115a981a8b6','files':source,'manifestSha256':hashlib.sha256(json.dumps(source,sort_keys=True,separators=(',',':')).encode()).hexdigest()}
(copy.parent/'core-source-manifest.json').write_text(json.dumps(manifest,indent=2))
print(f'Pinned core copy verified: {len(source)} files, manifest SHA256 {manifest["manifestSha256"]}')
