# -*- coding: utf-8 -*-
"""完整解析 FAT dylib"""
import sys, io, os, struct

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
path = r"C:\Users\yyds\Desktop\ios快手上号器\_dylib\KSDid.dylib"
data = open(path, "rb").read()

print("=" * 78)
print("FAT 头")
print("=" * 78)
magic = struct.unpack_from(">I", data, 0)[0]
print("  magic = 0x%08x" % magic)
n = struct.unpack_from(">I", data, 4)[0]
print("  含 %d 个架构" % n)

ARCH = {16777228: "arm64", 16777222: "arm64_32", 12: "armv7",
        16777223: "x86_64", 7: "i386", 16777228: "arm64"}
SUB = {0: "", 1: " (v8)", 2: " (arm64e!)", 0x80000002: " (arm64e?)"}

archs = []
for i in range(n):
    o = 8 + i * 20
    ct, cs, off, sz, al = struct.unpack_from(">iiIII", data, o)
    an = ARCH.get(ct, str(ct))
    sub = cs & 0xff
    subn = SUB.get(sub, " sub=%d" % sub)
    print("  [%d] %s%s  offset=%d size=%d" % (i, an, subn, off, sz))
    archs.append((an, sub, off, sz))

print()
print("=" * 78)
print("★ 关键：arm64e (subtype=2) 存在吗？")
print("=" * 78)
has_arm64 = any(a == "arm64" and s != 2 for a, s, _, _ in archs)
has_arm64e = any(a == "arm64" and s == 2 for a, s, _, _ in archs)
print("  纯 arm64 : %s" % ("✓ 有" if has_arm64 else "✗ 无"))
print("  arm64e   : %s" % ("✓ 有" if has_arm64e else "✗ 无"))

print()
print("=" * 78)
print("每个架构的 Load Commands")
print("=" * 78)
for an, sub, off, sz in archs:
    m = struct.unpack_from("<I", data, off)[0]
    is64 = (m == 0xfeedfacf)
    cputype, cpusubtype, ftype, ncmds, sizeofcmds, flags = \
        struct.unpack_from("<iiIIII", data, off + 4)
    print()
    print("  ── %s (subtype=%d) ──" % (an, cpusubtype & 0xff))
    print("     ftype=%d (6=dylib) ncmds=%d" % (ftype, ncmds))
    p = off + (32 if is64 else 28)
    cs_ok = False
    deps = []
    for i in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, p)
        if cmd == 0x1d:
            co, csz = struct.unpack_from("<II", data, p + 8)
            cs_ok = True
            print("     LC_CODE_SIGNATURE off=%d size=%d" % (co, csz))
        elif cmd == 0xc:
            no = struct.unpack_from("<I", data, p + 8)[0]
            nm = data[p+no:p+no+100].split(b"\x00")[0].decode("utf-8", "replace")
            deps.append(nm)
        p += cmdsize
    if not cs_ok:
        print("     ⚠ 无签名！")
    for dp in deps:
        print("     依赖: %s" % dp)

print()
print("=" * 78)
print("★ 结论")
print("=" * 78)
if has_arm64 and has_arm64e:
    print("  双架构（arm64 + arm64e）—— 正常")
elif has_arm64:
    print("  只有 arm64 —— 正常（iOS 15 上够用）")
elif has_arm64e:
    print("  ⚠ 只有 arm64e —— 这就是问题！快手主程是 arm64")
else:
    print("  ⚠ 架构异常: %s" % archs)
