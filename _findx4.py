# -*- coding: utf-8 -*-
"""★ 解析 Lx4 类（kstoken 的设备信息封装）"""
import sys, io, os, zipfile, struct

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
APK = r"C:\Users\yyds\Desktop\ios快手上号器\_android_apps\com.hmt.ks.apk"
z = zipfile.ZipFile(APK)
data = z.read("classes.dex")

hdr = struct.unpack_from("<8sI20s20I", data, 0)
sis, sio = hdr[9], hdr[10]
tis, tio = hdr[11], hdr[12]
mis, mio = hdr[17], hdr[18]
fis, fio = hdr[15], hdr[16]
fds, fdo = hdr[19], hdr[20]

def uleb(p):
    n=0; sh=0
    while True:
        b=data[p]; p+=1
        n |= (b & 0x7f) << sh
        if not (b & 0x80): break
        sh += 7
        if sh > 28: break
    return n, p

def gets(i):
    if i >= sis: return "?"
    off = struct.unpack_from("<I", data, sio + i*4)[0]
    n, p = uleb(off)
    return data[p:p+n].decode("utf-8", "replace").rstrip("\x00")

def gett(i):
    if i >= tis: return "?"
    return gets(struct.unpack_from("<I", data, tio + i*4)[0])

def getm(i):
    if i >= mis: return "?"
    o = mio + i*8
    ci, pi, ni = struct.unpack_from("<HHI", data, o)
    return "%s.%s" % (gett(ci).split("/")[-1].rstrip(";"), gets(ni))

def getf(i):
    if i >= fis: return "?"
    o = fio + i*8
    ci, ti, ni = struct.unpack_from("<HHI", data, o)
    return "%s.%s : %s" % (gett(ci).split("/")[-1].rstrip(";"), gets(ni), gett(ti))

# 找 Lx4
print("=" * 78)
print("★ 查找 Lx4 / Lqe / Ldc 类")
print("=" * 78)
for i in range(fds):
    off = fdo + i*32
    v = struct.unpack_from("<8I", data, off)
    cn = gett(v[0])
    short = cn.split("/")[-1].rstrip(";")
    if short in ("Lx4", "Lqe", "Ldc", "Lxa", "Lks", "Ly4"):
        print()
        print("─" * 78)
        print("  类: %s   extends %s" % (cn, gett(v[2])))
        print("─" * 78)
        cdoff = v[6]
        if not cdoff:
            print("    (无 class_data)")
            continue
        p = cdoff
        sf, p = uleb(p); inf, p = uleb(p); dm, p = uleb(p); vm, p = uleb(p)
        print("    字段: static=%d instance=%d | 方法: direct=%d virtual=%d" % (sf, inf, dm, vm))

        print("    --- 静态字段 ---")
        for _ in range(sf):
            fi, p = uleb(p); a, p = uleb(p)
            print("      %s" % getf(fi))
        print("    --- 实例字段 ---")
        for _ in range(inf):
            fi, p = uleb(p); a, p = uleb(p)
            print("      %s" % getf(fi))
        print("    --- 方法 ---")
        for lab, cnt in (("direct", dm), ("virtual", vm)):
            for _ in range(cnt):
                mi, p = uleb(p); a, p = uleb(p); co, p = uleb(p)
                print("      [%s] %s @0x%x" % (lab, getm(mi), co))

# 也搜所有含 "did" 的字段
print()
print("=" * 78)
print("★ 全 dex 里含 did/device/uuid 的字段名")
print("=" * 78)
for i in range(fis):
    o = fio + i*8
    ci, ti, ni = struct.unpack_from("<HHI", data, o)
    nm = gets(ni)
    low = nm.lower()
    if any(k in low for k in ["did", "device", "uuid", "gid", "egid", "idfa"]):
        print("  %s.%s : %s" % (gett(ci).split("/")[-1].rstrip(";"), nm, gett(ti)))

# 搜所有含 did 的字符串
print()
print("=" * 78)
print("★ 全 dex 里含 did/device 的字符串")
print("=" * 78)
for i in range(sis):
    s = gets(i)
    low = s.lower()
    if ("did" in low or "device" in low) and 2 <= len(s) <= 60:
        print("  [%4d] %r" % (i, s))
