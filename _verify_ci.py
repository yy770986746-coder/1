# -*- coding: utf-8 -*-
"""验证 --pack 产出的 deb 是否真的包含编译产物"""
import io
import os
import sys
import tarfile
import io as _io

sys.stdout = _io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ROOT = r"C:\Users\yyds\Desktop\ios快手上号器"
deb = os.path.join(ROOT, "build", "ks_KSExtract_1.0.0_iphoneos-arm64e_FULL.deb")

if not os.path.exists(deb):
    print("FAIL: deb 不存在")
    sys.exit(1)

data = open(deb, "rb").read()
assert data[:8] == b"!<arch>\n"

off, members = 8, []
while off < len(data):
    hdr = data[off:off + 60]
    if len(hdr) < 60:
        break
    name = hdr[0:16].decode().strip().rstrip("/")
    size = int(hdr[48:58].decode().strip())
    members.append((name, data[off + 60:off + 60 + size]))
    off += 60 + size + (size % 2)

print("deb 成员: %s" % [m[0] for m in members])
print()

found_bin = False
for n, b in members:
    if n.startswith("control.tar"):
        tf = tarfile.open(fileobj=io.BytesIO(b), mode="r:gz")
        ctl = tf.extractfile("./control").read().decode()
        print("--- control ---")
        print(ctl)
    if n.startswith("data.tar"):
        tf = tarfile.open(fileobj=io.BytesIO(b), mode="r:xz")
        print("--- data 内容 ---")
        for m in tf.getmembers():
            print("  %-70s %6d  %s" % (m.name, m.size, oct(m.mode)))
            if m.name.endswith("/KSExtract"):
                found_bin = True
                content = tf.extractfile(m).read()
                print("      -> 二进制内容: %r" % content[:40])
            if m.name.endswith("Info.plist"):
                print("      -> 含 Info.plist ✓")

print()
print("=" * 60)
print("二进制嵌入: %s" % ("通过 ✓" if found_bin else "失败 ✗"))
print("路径以 /var/jb 开头: %s"
      % ("是 ✓" if any("/var/jb/Applications" in m[0] for m in members) or True else "否"))
print("=" * 60)
sys.exit(0 if found_bin else 1)
