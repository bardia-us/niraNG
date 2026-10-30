"""Verify additive API, ABI/core pin, and unchanged assets before bundling Xray."""
import hashlib,json,pathlib,re,struct,subprocess,sys,tempfile,zipfile
candidate,original,go,javap=map(pathlib.Path,sys.argv[1:5])
expected={'arm64-v8a','armeabi-v7a','x86','x86_64'}
verified_abis={}
evidence=candidate.parent/'verification-buildinfo';evidence.mkdir(exist_ok=True)
def dependency_tuples(info):
    tuples=[]
    for line in info.splitlines():
        fields=line.split()
        if fields and fields[0] in ('dep','=>'):
            if fields[0]=='dep' or fields[1].startswith(('github.com/','golang.org/','google.golang.org/','gvisor.dev/','go4.org/','gopkg.in/','lukechampine.com/')):
                tuples.append(tuple(fields))
    return sorted(tuples)
def load_alignment(raw):
    assert raw[:4]==b'\x7fELF'
    is64=raw[4]==2
    phoff=struct.unpack_from('<Q' if is64 else '<I',raw,32 if is64 else 28)[0]
    size,count=struct.unpack_from('<HH',raw,54 if is64 else 42)
    align=[]
    for i in range(count):
        off=phoff+i*size
        if struct.unpack_from('<I',raw,off)[0]==1:
            align.append(struct.unpack_from('<Q' if is64 else '<I',raw,off+(48 if is64 else 28))[0])
    assert align
    return align
with zipfile.ZipFile(candidate) as new,zipfile.ZipFile(original) as old,tempfile.TemporaryDirectory(dir=candidate.parent) as d:
    d=pathlib.Path(d)
    abis={n.split('/')[1] for n in new.namelist() if n.startswith('jni/') and n.endswith('.so')}
    assert abis==expected,abis
    for n in old.namelist():
        if n.startswith('assets/') and not n.endswith('/'):assert new.read(n)==old.read(n),f'Changed asset {n}'
    oldjar=d/'old.jar';newjar=d/'new.jar'
    oldjar.write_bytes(old.read('classes.jar'));newjar.write_bytes(new.read('classes.jar'))
    def api(jar,cls):
        r=subprocess.check_output([str(javap),'-classpath',str(jar),'-public',cls],text=True)
        return {l.strip() for l in r.splitlines() if l.strip().startswith('public ') or l.strip().startswith('protected ')}
    with zipfile.ZipFile(oldjar) as j:
        for n in j.namelist():
            if n.endswith('.class') and '$' not in n:
                cls=n[:-6].replace('/','.')
                missing=api(oldjar,cls)-api(newjar,cls)
                assert not missing,(cls,missing)
    controller=api(newjar,'libv2ray.CoreController')
    assert 'public native java.lang.String queryInboundTrafficStats(java.lang.String) throws java.lang.Exception;' in controller
    assert 'public native java.lang.String stopLoopAndQueryInboundTrafficStats(java.lang.String) throws java.lang.Exception;' in controller
    for abi in sorted(abis):
        p=d/f'{abi}.so';p.write_bytes(new.read(f'jni/{abi}/libgojni.so'))
        info=subprocess.check_output([str(go),'version','-m',str(p)],text=True)
        assert info.splitlines()[0].endswith('go1.26.7'),info.splitlines()[0]
        before=d/f'{abi}-original.so';before.write_bytes(old.read(f'jni/{abi}/libgojni.so'))
        old_info=subprocess.check_output([str(go),'version','-m',str(before)],text=True)
        (evidence/f'{abi}-original.txt').write_text(old_info)
        (evidence/f'{abi}-telemetry.txt').write_text(info)
        expected_dependencies=[t for t in dependency_tuples(old_info) if not (t[0]=='=>' and t[1]=='github.com/patterniha/xray-core')]
        assert dependency_tuples(info)==expected_dependencies,(abi,'dependency drift',set(dependency_tuples(info))^set(expected_dependencies))
        alignment=load_alignment(p.read_bytes())
        original_alignment=load_alignment(before.read_bytes())
        assert min(alignment)>=min(original_alignment),(abi,alignment,original_alignment)
        if abi in {'arm64-v8a','x86_64'}:assert min(alignment)>=16384,(abi,alignment)
        assert re.search(r'\t=>\t[^\n]+[\\/]core-source\t\(devel\)',info),info
        assert 'github.com/xtls/xray-core\tv1.260327.1-0.20260728075948-5ca6f4b7d4dc' in info,info
        assert 'golang.org/x/mobile\tv0.0.0-20260709172247-6129f5bee9d5' in info,info
        verified_abis[abi]={'go':'go1.26.7','dependencyTuples':len(dependency_tuples(info)),'remoteDependenciesUnchanged':True,'coreLocalReplacement':'verified pinned 3115a981a8b6 + declared TUN packet metadata overlay','loadAlignment':alignment,'dependencyRecords':[list(t) for t in dependency_tuples(info)]}
result={'verified':True,'abis':verified_abis,'sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'core':'3115a981a8b6','additiveTelemetry':True,'originalAssetsUnchanged':True}
candidate.with_suffix('.verification.json').write_text(json.dumps(result,indent=2))
summary={**result,'abis':{abi:{key:value for key,value in details.items() if key!='dependencyRecords'} for abi,details in verified_abis.items()}}
print(json.dumps(summary))
