# -*- coding: utf-8 -*-
"""★ 反汇编 MainActivity 的 4 个按钮 onClick + MMKV 写入方法"""
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

# 收集所有方法
allm = []
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
        for lab, cnt in (("d", dm), ("v", vm)):
            for _ in range(cnt):
                mi, p = uleb(p); a, p = uleb(p); co, p = uleb(p)
                allm.append((cn, getm(mi), co))
    except Exception:
        continue

def disasm(co, maxlines=120):
    try:
        regs, ins, outs, tries, dbg, insns = struct.unpack_from("<HHHHII", data, co)
    except Exception:
        return
    ip = co + 16
    end = ip + insns*2
    out = []
    n = 0
    while ip < end and n < maxlines:
        op = data[ip]
        nm = None; extra = ""; size = 2
        if op == 0x0e: nm = "return-void"
        elif op == 0x0f: nm = "return"
        elif op == 0x11: nm = "return-object"
        elif op == 0x1a:
            nm = "const-string"; size = 4
            extra = repr(gets(struct.unpack_from("<H", data, ip+2)[0]))
        elif op == 0x1b:
            nm = "const-string/jumbo"; size = 6
            extra = repr(gets(struct.unpack_from("<I", data, ip+2)[0]))
        elif op == 0x1c:
            nm = "const-class"; size = 4
            extra = gett(struct.unpack_from("<H", data, ip+2)[0])
        elif op == 0x22:
            nm = "new-instance"; size = 4
            extra = gett(struct.unpack_from("<H", data, ip+2)[0])
        elif op in (0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a):
            nm = {0x52:"iget",0x53:"iget-wide",0x54:"iget-object",0x55:"iget-boolean",
                  0x56:"iget-byte",0x57:"iget-char",0x58:"iget-short",
                  0x59:"iput",0x5a:"iput-object"}.get(op,"ifield"); size = 4
            extra = getf(struct.unpack_from("<H", data, ip+2)[0])
        elif op in (0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,
                    0x69,0x6a,0x6b,0x6c,0x6d):
            nm = {0x60:"sget",0x61:"sget-wide",0x62:"sget-object",0x63:"sget-boolean",
                  0x64:"sget-byte",0x65:"sget-char",0x66:"sget-short",
                  0x67:"sput",0x68:"sput-wide",0x69:"sput-object",0x6a:"sput-boolean",
                  0x6b:"sput-byte",0x6c:"sput-char",0x6d:"sput-short"}.get(op,"sfield"); size = 4
            extra = getf(struct.unpack_from("<H", data, ip+2)[0])
        elif op in (0x6e,0x6f,0x70,0x71,0x72):
            nm = {0x6e:"invoke-virtual",0x6f:"invoke-super",0x70:"invoke-direct",
                  0x71:"invoke-static",0x72:"invoke-interface"}[op]; size = 6
            extra = getm(struct.unpack_from("<H", data, ip+2)[0])
        elif op in (0x38,0x39,0x3a,0x3b,0x3c,0x3d,0x3e,0x3f,0x40,0x41,0x42,0x43,0x44):
            nm = {0x38:"if-eqz",0x39:"if-nez",0x3a:"if-ltz",0x3b:"if-gez",
                  0x3c:"if-gtz",0x3d:"if-lez"}.get(op,"if"); size = 4
        elif op == 0x0c: nm = "move-result-object"
        elif op == 0x0a: nm = "move-result"
        elif op == 0x04: nm = "move-wide"
        else: nm = "op_0x%02x" % op
        suffix = ("  " + extra) if extra else ""
        out.append("  @%05x  %-20s%s" % (ip, nm, suffix))
        ip += size
        n += 1
    return out

# ★ 找所有调用 MMKV.a 的方法（写入）
print("=" * 78)
print("★ 所有调用 MMKV 写入的方法")
print("=" * 78)
for cn, mn, co in allm:
    if not co: continue
    try:
        regs, ins, outs, tries, dbg, insns = struct.unpack_from("<HHHHII", data, co)
    except Exception:
        continue
    ip = co + 16
    end = ip + insns*2
    calls = []
    strs = []
    while ip < end:
        op = data[ip]
        if op == 0x1a:
            strs.append(gets(struct.unpack_from("<H", data, ip+2)[0])); ip += 4
        elif op == 0x1b:
            strs.append(gets(struct.unpack_from("<I", data, ip+2)[0])); ip += 6
        elif op in (0x6e,0x6f,0x70,0x71,0x72):
            calls.append(getm(struct.unpack_from("<H", data, ip+2)[0])); ip += 6
        elif op in (0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a): ip += 4
        elif op in (0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,
                    0x69,0x6a,0x6b,0x6c,0x6d): ip += 4
        else: ip += 2

    blob = " ".join(strs) + " " + " ".join(calls)
    # 写入特征：有 encode / put / edit / commit / apply，或含 device id
    if any(k in blob for k in ["encode", "putString", "putInt", "commit", "apply",
                                "device id", "DeviceId", "setValue", "write"]):
        print()
        print("─" * 78)
        print("  类: %s" % cn)
        print("  方法: %s  @0x%x" % (mn, co))
        print("─" * 78)
        if strs:
            print("  字符串:")
            for s in strs[:25]:
                if len(s) < 100: print("    %r" % s)
        if calls:
            print("  调用:")
            for c in calls[:30]: print("    %s" % c)
