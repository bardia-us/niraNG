"""Fail closed on missing ABIs, duplicated Go Java runtimes, or mixed JNI namespaces."""
import hashlib
import io
import pathlib
import re
import struct
import sys
import zipfile

aar = pathlib.Path(sys.argv[1])
xray = pathlib.Path(sys.argv[2])
machines = {"arm64-v8a": 183, "armeabi-v7a": 40, "x86_64": 62}
with zipfile.ZipFile(aar) as box, zipfile.ZipFile(xray) as xr:
    with zipfile.ZipFile(io.BytesIO(box.read("classes.jar"))) as classes:
        names = set(classes.namelist())
        assert "nirasbgo/Seq.class" in names and "nirasbgo/Universe.class" in names
        assert not any(name.startswith("go/") for name in names), "unisolated Go Java runtime"
        assert b"startProbe" in classes.read("io/nekohasekai/libbox/CommandServer.class"), "missing isolated probe API"
        for name in names:
            if name.endswith(".class"):
                assert not re.search(rb"(?:L|\x00\x06)go/Seq", classes.read(name)), f"unisolated JNI descriptor in {name}"
        with zipfile.ZipFile(io.BytesIO(xr.read("classes.jar"))) as xclasses:
            duplicate = {n for n in names.intersection(xclasses.namelist()) if n.endswith(".class")}
            assert not duplicate, f"duplicate Java classes: {sorted(duplicate)}"
    for abi, machine in machines.items():
        name = f"jni/{abi}/libbox.so"
        native = box.read(name)
        assert native[:4] == b"\x7fELF" and native[5] == 1
        assert struct.unpack_from("<H", native, 18)[0] == machine
        for symbol in (b"Java_nirasbgo_Seq_init", b"Java_nirasbgo_Seq_setContext", b"Java_nirasbgo_Seq_destroyRef"):
            assert symbol in native, f"missing isolated JNI symbol {symbol} in {abi}"
        assert b"Java_go_Seq_" not in native, f"unisolated native JNI runtime in {abi}"
        print(f"{abi}: {len(native)} bytes, SHA256 {hashlib.sha256(native).hexdigest()}")
print(f"AAR verified: SHA256 {hashlib.sha256(aar.read_bytes()).hexdigest()}")
