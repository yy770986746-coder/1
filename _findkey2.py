# -*- coding: utf-8 -*-
"""定点查 kstoken 的键名"""
import sys, io, os, zipfile, re, struct

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
APK = r"C:\Users\yyds\Desktop\ios快手上号器\_android_apps\com.hmt.ks.apk"
z = zipfile.ZipFile(APK)
data = z.read("classes.dex")

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

print("=" * 74)
print("★ 所有 key 名（在 put/get/encodeString 附近的字符串）")
print("=" * 74)
# 找 MMKV 方法名附近的字符串
for kw in [b"encodeString", b"decodeString", b"putString", b"getString"]:
    for m in re.finditer(re.escape(kw), data):
        i = m.start()
        # 看前后 400 字节附近有无可读键名
        chunk = data[max(0,i-500):i+500]
        # 提取连续可打印
        for sm in re.finditer(rb"[\x20-\x7e]{4,50}", chunk):
            s = sm.group(0).decode("ascii")
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_\.\-]{3,49}", s):
                if any(k in s.lower() for k in ["did", "gid", "device", "id", "uuid", "cache", "token", "salt", "cloud"]):
                    print("  %s" % s)
    break

print()
print("=" * 74)
print("★ 全部短键名（按字母序，过滤掉 android/java 标准库）")
print("=" * 74)
import re as _re
interesting = []
for s in strs:
    if not (2 <= len(s) <= 40): continue
    if not _re.fullmatch(r"[A-Za-z_][A-Za-z0-9_\.\-]*", s): continue
    low = s.lower()
    if any(x in low for x in ["android", "java", "google", "kotlin", "androidx",
                               "okhttp", "tencent", "squareup"]):
        continue
    if any(k in low for k in ["did", "gid", "device", "uuid", "cache", "cloud",
                               "install", "ks", "gifshow", "egid", "kwtk"]):
        interesting.append(s)
for s in sorted(set(interesting)):
    print("  %s" % s)

print()
print("=" * 74)
print("★ 'IDDD' 和 'QuickLoginToken' 的上下文")
print("=" * 74)
for pat in [b"IDDD", b"QuickLoginToken"]:
    for m in re.finditer(re.escape(pat), data):
        i = m.start()
        chunk = data[max(0,i-200):i+200]
        txt = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        print("  【%s】@0x%x" % (pat.decode(), i))
        print("    %s" % txt)
        print()

print("=" * 74)
print("★ 全部中文字符串")
print("=" * 74)
seen = set()
for s in strs:
    if _re.search(r"[\u4e00-\u9fff]", s) and 1 < len(s) < 80:
        if s not in seen:
            seen.add(s)
            print("  %s" % s)
