"""Verify/stage official Psiphon executables and the authenticated public bootstrap list.

Never stages the upstream Aether executable: it lacks the required nira TLS patch.
Run after downloading the three v2.4.0 archives into build/aether-upstream.
"""
import base64
import hashlib
import json
from pathlib import Path
import re
import struct
import tarfile
import urllib.request
import zlib

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "build/aether-upstream"
ARCHIVES = {
    "arm64-v8a": ("arm64", "2857c8ec11090bacb40c94dc1126af1abb59d8270e86992fc239affb61dd2f48", 183),
    "armeabi-v7a": ("armv7", "d3d37017151c482e04eab857f87e212ba39eb6f5694f31f6e307d1d2e987b75b", 40),
    "x86_64": ("x86_64", "7ec197b85d157e4c38e68d181c28bd15d4f02e59f23fcf508d4b92e14e7d7bca", 62),
}
SERVER_URL = "https://s3.amazonaws.com//psiphon/web/mjr4-p23r-puwl/server_list_compressed"
PIN = "d58f9d568083129ce2c767c85054021eb3ee6a38"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    metadata = {"aetherCommit": PIN, "psiphonCommit": "83aa73b9b982e7421e00117f5b0c5aceb5dda452",
                "psiphonSource": "https://github.com/CluvexStudio/psiphon-tunnel-core", "abis": {}}
    for abi, (name, checksum, machine) in ARCHIVES.items():
        archive = WORK / f"aether-android-{name}.tar.gz"
        if digest(archive.read_bytes()) != checksum:
            raise ValueError(f"Archive checksum mismatch: {abi}")
        with tarfile.open(archive, "r:gz") as tar:
            executable = tar.extractfile("pt/psiphon-tunnel-core").read()
            if executable[:4] != b"\x7fELF" or struct.unpack_from("<H", executable, 18)[0] != machine:
                raise ValueError(f"Wrong ELF ABI: {abi}")
            revisions = set(re.findall(rb"vcs\.revision=([a-f0-9]{40})", executable))
            if revisions != {metadata["psiphonCommit"].encode("ascii")} or b"vcs.modified=true" in executable:
                raise ValueError(f"Unexpected Psiphon source provenance: {abi}")
            destination = ROOT / "android/app/src/main/jniLibs" / abi
            destination.mkdir(parents=True, exist_ok=True)
            (destination / "libpsiphon_nira.so").write_bytes(executable)
            notices = ROOT / "android/app/src/main/assets/licenses/aether" / abi
            notices.mkdir(parents=True, exist_ok=True)
            for member in tar.getmembers():
                if member.isfile() and member.name.startswith("LICENSES/"):
                    # Flat, known release-license names; no archive path extraction.
                    (notices / Path(member.name).name).write_bytes(tar.extractfile(member).read())
        metadata["abis"][abi] = {"archiveSha256": checksum, "psiphonSha256": digest(executable),
                                  "archiveUrl": f"https://github.com/patterniha/Aether/releases/download/v2.4.0/aether-android-{name}.tar.gz"}

    compressed = WORK / "psiphon-servers.dat"
    if not compressed.exists():
        with urllib.request.urlopen(SERVER_URL, timeout=45) as response:
            data = response.read(8 * 1024 * 1024 + 1)
        if len(data) > 8 * 1024 * 1024:
            raise ValueError("Bootstrap list too large")
        compressed.write_bytes(data)
    source = (WORK / "Aether/aether/src/psiphon.rs").read_text(encoding="utf-8")
    match = re.search(r"SERVER_LIST_SIGNATURE_KEY: &str = concat!\((.*?)\);", source, re.S)
    key = "".join(re.findall(r'"([^"]*)"', match.group(1)))
    inflater = zlib.decompressobj()
    decoded = inflater.decompress(compressed.read_bytes(), 16 * 1024 * 1024 + 1)
    if len(decoded) > 16 * 1024 * 1024 or not inflater.eof:
        raise ValueError("Invalid or oversized compressed Psiphon list")
    package = json.loads(decoded)
    if base64.b64decode(package["signingPublicKeyDigest"], validate=True) != hashlib.sha256(key.encode()).digest():
        raise ValueError("Unexpected Psiphon signing key")
    entries = package["data"].encode("utf-8")
    public_key = serialization.load_der_public_key(base64.b64decode(key, validate=True))
    public_key.verify(base64.b64decode(package["signature"], validate=True), entries,
                      padding.PKCS1v15(), hashes.SHA256())
    count = len([line for line in entries.splitlines() if line.strip()])
    if count < 50:
        raise ValueError("Incomplete Psiphon bootstrap list")
    assets = ROOT / "android/app/src/main/assets"
    (assets / "aether-psiphon-server-entries.dat").write_bytes(entries)
    metadata.update(serverEntriesSha256=digest(entries), serverEntriesCount=count, serverEntriesSource=SERVER_URL,
                    signedPackageSha256=digest(compressed.read_bytes()))
    (ROOT / "tool/aether-artifacts.lock.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Verified three Psiphon ELF executables and {count} RSA-authenticated bootstrap entries")


if __name__ == "__main__":
    main()
