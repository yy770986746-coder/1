# -*- coding: utf-8 -*-
"""精确 dump 写 MMKV 的那个方法"""
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
    return "%s.%s" % (gett(ci).split("/")[-1].rstrip(";"), gets(ni))

# 收集所有方法的 (类, 方法名, codeoff)
methods = []
for i in range(fds):
    off = fdo + i*32
    v = struct.unpack_from("<8I", data, off)
    cn, cdoff = gett(v[0]), v[6]
    if not cdoff: continue
    try:
        p = cdoff
        sf, p = uleb(p); inf, p = uleb(p); dm, p = uleb(p); vm, p = uleb(p)
        for _ in range(sf+inf):
            _, p = uleb(p); _, p = uleb(p)
        for label, cnt in (("d", dm), ("v", vm)):
            for _ in range(cnt):
                mi, p = uleb(p); a, p = uleb(p); co, p = uleb(p)
                methods.append((cn, getm(mi), co))
    except Exception:
        continue

# 全量 dump 每个方法
def dump(cn, mn, co):
    try:
        regs, ins, outs, tries, dbg, insns = struct.unpack_from("<HHHHII", data, co)
    except Exception:
        return None, None, None
    ip = co + 16
    end = ip + insns*2
    strs, calls, flds = [], [], []
    while ip < end:
        op = data[ip]
        if op == 0x1a:
            strs.append(gets(struct.unpack_from("<H", data, ip+2)[0])); ip += 4
        elif op == 0x1b:
            strs.append(gets(struct.unpack_from("<I", data, ip+2)[0])); ip += 6
        elif op in (0x6e,0x6f,0x70,0x71,0x72):
            calls.append(getm(struct.unpack_from("<H", data, ip+2)[0])); ip += 6
        elif op in (0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a):
            flds.append(getf(struct.unpack_from("<H", data, ip+2)[0])); ip += 4
        elif op in (0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,
                    0x69,0x6a,0x6b,0x6c,0x6d):
            ip += 4
        else:
            ip += 2
    return strs, calls, flds

# ★ 找所有含 "gifshow" 或 ".crc" 或 "force-stop" 的方法
print("=" * 78)
print("★★★ 关键方法（含 gifshow / .crc / force-stop / mmkv）")
print("=" * 78)
seen = set()
for cn, mn, co in methods:
    if not co: continue
    s, c, f = dump(cn, mn, co)
    if s is None: continue
    blob = " ".join(s) + " " + " ".join(c)
    if not any(k in blob for k in ["gifshow", ".crc", "force-stop", "mmkv", "MMKV", "chmod"]):
        continue
    sig = (cn, mn, co)
    if sig in seen: continue
    seen.add(sig)
    print()
    print("─" * 78)
    print("  类: %s" % cn)
    print("  方法: %s  @0x%x" % (mn, co))
    print("─" * 78)
    if s:
        print("  字符串常量 (%d):" % len(s))
        for x in s:
            if len(x) < 120:
                print("    %r" % x)
    if c:
        print("  方法调用 (%d):" % len(c))
        for x in c:
            if any(k in x for k in ["mmkv","MMKV","Process","Runtime","File","String",
                                     "JSON","Gson","chmod","crc","gifshow"]):
                print("    %s" % x)
