# -*- coding: utf-8 -*-
"""分析 kstoken 的 'Generate MMKV from JSON' 功能"""
import sys, io, os, zipfile, re, struct

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
APK = r"C:\Users\yyds\Desktop\ios快手上号器\_android_apps\com.hmt.ks.apk"
z = zipfile.ZipFile(APK)
data = z.read("classes.dex")

print("=" * 74)
print("★ 'Generate' 附近的字符串（DEX 字符串池顺序 = 代码顺序）")
print("=" * 74)
hdr = struct.unpack_from("<8sI20s20I", data, 0)
sis, sio = hdr[9], hdr[10]
def uleb(p):
    n=0; sh=0
    while True:
        b=data[p]; p+=1
        n |= (b & 0x7f) << sh
        if not (b & 0x80): break
        sh += 7
        if sh > 28: break
    return n, p
strs = []
for i in range(sis):
    off = struct.unpack_from("<I", data, sio + i*4)[0]
    n, p = uleb(off)
    strs.append(data[p:p+n].decode("utf-8", "replace").rstrip("\x00"))

# 找 Generate 的索引
for i, s in enumerate(strs):
    if "Generate" in s and len(s) < 80:
        print("  [%4d] %s" % (i, s))
        # 打印前后 40 个字符串
        print("        ── 附近字符串 ──")
        for j in range(max(0,i-25), min(len(strs), i+25)):
            t = strs[j]
            if 1 <= len(t) <= 70 and not t.startswith(("L", "[L")):
                mark = " ★" if j == i else ""
                print("          [%4d] %s%s" % (j, t, mark))
        print()

print("=" * 74)
print("★ 'IDDD' 索引附近的字符串")
print("=" * 74)
for i, s in enumerate(strs):
    if s == "IDDD":
        print("  [%4d] IDDD" % i)
        for j in range(max(0,i-30), min(len(strs), i+30)):
            t = strs[j]
            if 1 <= len(t) <= 70 and not t.startswith(("L", "[L")):
                mark = " ★" if j == i else ""
                print("          [%4d] %s%s" % (j, t, mark))
        break

print()
print("=" * 74)
print("★ 所有 'gifshow_' 开头的键（完整列表）")
print("=" * 74)
for s in strs:
    if s.startswith("gifshow_") and len(s) < 60:
        print("  %s" % s)

print()
print("=" * 74)
print("★ JSON 相关字符串（它生成的格式）")
print("=" * 74)
for s in strs:
    if ("{" in s or "}" in s or ":" in s) and 3 < len(s) < 90:
        if re.search(r"[a-z_A-Z]+", s):
            print("  %r" % s)
