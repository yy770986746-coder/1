# -*- coding: utf-8 -*-
"""检查 deb 内的文件清单 + 二进制依赖"""
import sys, io, os, tarfile, struct

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
DEB = r"C:\Users\yyds\Desktop\ks-ios-deb\ks_KSExtract_1.0.0_iphoneos-arm64e_FULL.deb"

data = open(DEB, "rb").read()
print("deb 大小: %d 字节\n" % len(data))

pos = 8
members = {}
while pos < len(data):
    hdr = data[pos:pos + 60]
    if len(hdr) < 60: break
    name = hdr[:16].decode("latin-1").strip().rstrip("/")
    size = int(hdr[48:58].decode("latin-1").strip())
    body_start = pos + 60
    body = data[body_start:body_start + size]
    members[name] = body
    pos = body_start + size + (size % 2)

print("deb 内成员: %s\n" % list(members.keys()))

# 解 data.tar.xz
for key in members:
    if "data.tar" in key:
        tf = tarfile.open(fileobj=io.BytesIO(members[key]))
        print("=" * 74)
        print("data.tar 内容（这就是安装到设备的全部文件）")
        print("=" * 74)
        total = 0
        for m in tf.getmembers():
            total += m.size
            perm = oct(m.mode)[-3:]
            print("  %-6s %8d  %s" % (perm, m.size, m.name))
        print("\n  共 %d 个文件，解包后 %d 字节" % (len(tf.getmembers()), total))

        # 检查可执行文件
        print()
        print("=" * 74)
        print("可执行文件检查")
        print("=" * 74)
        for m in tf.getmembers():
            if m.name.endswith("/KSExtract") and m.isfile():
                exe = tf.extractfile(m).read()
                print("  %s" % m.name)
                print("  大小: %d 字节" % len(exe))
                print("  类型: %s" % ("Mach-O arm64" if exe[:4] in
                      (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe") else "未知"))
                # 找 dylib 依赖
                import re
                libs = set(re.findall(rb"/usr/lib/[a-zA-Z0-9_.+-]+\.dylib", exe))
                libs |= set(re.findall(rb"@rpath/[a-zA-Z0-9_.+-]+\.dylib", exe))
                print("  依赖的动态库（%d 个）:" % len(libs))
                for l in sorted(libs):
                    print("      %s" % l.decode())
