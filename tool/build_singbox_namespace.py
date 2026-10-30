"""Relocate only gomobile's Java/JNI runtime, preserving the verified module cache.

Two Go AARs cannot safely share go.Seq: its reference tracker belongs to one
native runtime. Rebuild sing-box with nirasbgo.Seq and corresponding JNI symbols.
The exact upstream revision is independently pinned by build_singbox.ps1.
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1])


def replace(relative, old, new, count):
    path = root / relative
    text = path.read_text(encoding="utf-8")
    actual = text.count(old)
    if actual != count:
        raise SystemExit(f"Unexpected gomobile source in {relative}: expected {count}, got {actual}")
    path.chmod(0o666)
    path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")


replace("bind/genjava.go", 'return "go"', 'return "nirasbgo"', 1)
replace("bind/genjava.go", "import go.Seq;", "import nirasbgo.Seq;", 1)
replace("bind/java/Seq.java", "package go;", "package nirasbgo;", 1)
replace("bind/java/Seq.java", "import go.Universe;", "import nirasbgo.Universe;", 1)
replace("cmd/gobind/gen.go", 'filepath.Join("java", "go", javaFile)', 'filepath.Join("java", "nirasbgo", javaFile)', 1)
replace("bind/java/seq_android.c.support", "Java_go_Seq_", "Java_nirasbgo_Seq_", 3)
replace("bind/java/seq_android.c.support", "go/Seq", "nirasbgo/Seq", 3)
replace("bind/java/context_android.c", "Java_go_Seq_", "Java_nirasbgo_Seq_", 1)
replace("cmd/gomobile/bind_androidapp.go", "-keep class go.**", "-keep class nirasbgo.**", 1)
print("Relocated verified gomobile Java/JNI runtime to nirasbgo")
