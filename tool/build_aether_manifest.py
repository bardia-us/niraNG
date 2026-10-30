"""Stage an integrity manifest for explicitly selected already-built Aether ABIs."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parent.parent
MACHINES = {"arm64-v8a": 183, "armeabi-v7a": 40, "x86_64": 62}
PIN = "d58f9d568083129ce2c767c85054021eb3ee6a38"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--abis", nargs="+", choices=list(MACHINES), default=list(MACHINES))
    args = parser.parse_args()
    source = ROOT / "build/aether-upstream/Aether"
    revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if revision != PIN:
        raise ValueError("Unexpected Aether source revision")
    patch = ROOT / "tool/aether-https-peer.patch"
    subprocess.run(["git", "-C", str(source), "apply", "--reverse", "--check", str(patch)], check=True)
    changes = subprocess.check_output(["git", "-C", str(source), "diff", "--name-only"], text=True).splitlines()
    if changes != ["aether/src/https.rs"]:
        raise ValueError("Unexpected Aether source changes")
    evidence = json.loads((ROOT / "build/aether-upstream/tls-tests.json").read_text())
    if evidence["securityPatchSha256"] != sha(patch):
        raise ValueError("Native TLS test evidence does not match the patch")
    baseline = json.loads((ROOT / "tool/aether-artifacts.lock.json").read_text())
    manifest = {"source": "https://github.com/patterniha/Aether", "commit": PIN, "version": "2.4.0",
                "rust": "1.99.1", "ndk": "28.2.13676358", "securityPatch": "nira-https-peer-v1",
                "securityPatchSha256": sha(patch), "serverEntriesSha256": baseline["serverEntriesSha256"],
                "serverEntriesCount": baseline["serverEntriesCount"], "psiphonCommit": baseline["psiphonCommit"],
                "psiphonSource": baseline["psiphonSource"], "abis": {}}
    for abi in args.abis:
        native = ROOT / "android/app/src/main/jniLibs" / abi
        aether = native / "libaether_nira.so"
        data = aether.read_bytes()
        if data[:4] != b"\x7fELF" or struct.unpack_from("<H", data, 18)[0] != MACHINES[abi]:
            raise ValueError("Wrong Aether ABI")
        elf64 = data[4] == 2
        offset = struct.unpack_from("<Q" if elf64 else "<I", data, 32 if elf64 else 28)[0]
        size, count = struct.unpack_from("<HH", data, 54 if elf64 else 42)
        for index in range(count):
            header = offset + index * size
            if struct.unpack_from("<I", data, header)[0] == 1:
                alignment = struct.unpack_from("<Q" if elf64 else "<I", data, header + (48 if elf64 else 28))[0]
                if alignment < 16384:
                    raise ValueError("Aether LOAD segment is not 16KiB aligned")
        psiphon_hash = sha(native / "libpsiphon_nira.so")
        if psiphon_hash != baseline["abis"][abi]["psiphonSha256"]:
            raise ValueError("Psiphon executable hash mismatch")
        manifest["abis"][abi] = {"aetherSha256": sha(aether), "psiphonSha256": psiphon_hash}
    output = ROOT / "android/app/src/main/assets/aether-runtime.json"
    temporary = output.with_name(".aether-runtime.json.tmp")
    temporary.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    temporary.replace(output)
    print("Verified runtime manifest:", ", ".join(args.abis))


if __name__ == "__main__":
    main()
