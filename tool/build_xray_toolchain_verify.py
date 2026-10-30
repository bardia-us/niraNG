"""Verify the exact Go1.26.7 distribution before executing its tools.

The pinned module archive was authenticated by `go mod download` against the
signed sum.golang.org record 60245927; its module h1 checksum is retained below.
"""
import hashlib,pathlib,sys,zipfile
archive,root=map(pathlib.Path,sys.argv[1:3])
expected='ccada8b506d8a99124bd4654f15c74974c5d32f93b705b5c6081b76d629026b4'
assert hashlib.sha256(archive.read_bytes()).hexdigest()==expected,'Go1.26.7 archive SHA256 mismatch'
prefix='golang.org/toolchain@v0.0.1-go1.26.7.windows-amd64/'
count=0
with zipfile.ZipFile(archive) as z:
    for n in z.namelist():
        assert n.startswith(prefix),n
        relative=n[len(prefix):]
        if not relative or n.endswith('/'):continue
        assert '..' not in pathlib.PurePosixPath(relative).parts,n
        assert (root/relative).read_bytes()==z.read(n),f'Go toolchain file mismatch: {relative}'
        count+=1
print(f'Exact Go1.26.7 toolchain verified: {count} files; module h1:lbbNIUXD76tVDW850cljAE22gUR0RdmZ0aVf0cjKnTo=')
