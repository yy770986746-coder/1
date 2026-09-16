# -*- coding: utf-8 -*-
"""找 kstoken 里 "device id" 相关的字符串和键"""
import sys, io, os, zipfile, re, struct

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
APK = r"C:\Users\yyds\Desktop\ios快手上号器\_android_apps\com.hmt.ks.apk"
z = zipfile.ZipFile(APK)
data = z.read("classes.dex")

print("=" * 74)
print("1. 直接搜 'device id' / 'deviceid' / 'device_id'")
print("=" * 74)
for pat in [b"device id", b"deviceid", b"device_id", b"DeviceId", b"DEVICE_ID", b"Device ID"]:
    idxs = [m.start() for m in re.finditer(re.escape(pat), data)]
    if idxs:
        print("  %-12s 出现 %d 次" % (pat.decode(), len(idxs)))
        for i in idxs[:4]:
            ctx = data[max(0,i-60):i+90]
            txt = ctx.decode("utf-8", "replace")
            txt = "".join(ch if 32 <= ord(ch) < 127 else "." for ch in txt)
            print("      ...%s..." % txt)
        print()

print("=" * 74)
print("2. ★ dex 字符串池里所有可能的键名")
print("=" * 74)
# 解析 dex string ids
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

# 找可疑的键名（字母数字下划线，3-40 字符）
keys = []
for s in strs:
    if 3 <= len(s) <= 40 and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_\.\-]*", s):
        low = s.lower()
        if any(k in low for k in ["did", "device", "id", "uuid", "gid", "egid",
                                   "cache", "cloud", "install", "ks", "gifshow",
                                   "user", "token", "salt", "set", "put", "write"]):
            keys.append(s)

print("  候选键名 (%d 个):" % len(keys))
for k in sorted(set(keys)):
    print("    %s" % k)

print()
print("=" * 74)
print("3. ★ 所有含点号的 MMKV 风格键名")
print("=" * 74)
for s in sorted(set(strs)):
    if re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+){1,4}", s) and 5 < len(s) < 60:
        print("  %s" % s)

print()
print("=" * 74)
print("4. 所有中文 UI 文案（从 dex）")
print("=" * 74)
seen = set()
for s in strs:
    if re.search(r"[\u4e00-\u9fff]", s) and 1 < len(s) < 60:
        if s not in seen:
            seen.add(s)
            print("  %s" % s)
