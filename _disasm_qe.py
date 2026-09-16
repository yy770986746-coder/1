# -*- coding: utf-8 -*-
"""★ 反汇编 Lqe.onClick（4个按钮的处理）"""
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

OP = {0x0e:"return-void",0x0f:"return",0x10:"return-wide",0x11:"return-object",
      0x0a:"move-result",0x0c:"move-result-object",0x01:"move",0x07:"move-object",
      0x12:"const/4",0x13:"const/16",0x14:"const",0x15:"const/high16",
      0x1a:"const-string",0x1b:"const-string/jumbo",0x1c:"const-class",
      0x1f:"check-cast",0x22:"new-instance",0x23:"new-array",0x26:"fill-array-data",
      0x27:"throw",0x28:"goto",0x29:"goto/16",0x2b:"packed-switch",0x2c:"sparse-switch",
      0x38:"if-eqz",0x39:"if-nez",0x3a:"if-ltz",0x3b:"if-gez",0x3c:"if-gtz",0x3d:"if-lez",
      0x44:"aget",0x45:"aget-wide",0x46:"aget-object",
      0x52:"iget",0x53:"iget-wide",0x54:"iget-object",0x55:"iget-boolean",
      0x59:"iput",0x5a:"iput-wide",0x5b:"iput-object",0x5c:"iput-boolean",
      0x60:"sget",0x61:"sget-wide",0x62:"sget-object",0x63:"sget-boolean",
      0x67:"sput",0x68:"sput-wide",0x69:"sput-object",0x6a:"sput-boolean",
      0x6e:"invoke-virtual",0x6f:"invoke-super",0x70:"invoke-direct",
      0x71:"invoke-static",0x72:"invoke-interface"}

def disasm(co, name, maxn=300):
    try:
        regs, ins, outs, tries, dbg, insns = struct.unpack_from("<HHHHII", data, co)
    except Exception:
        return
    print()
    print("=" * 78)
    print("★ %s  @0x%x  (regs=%d insns=%d)" % (name, co, regs, insns))
    print("=" * 78)
    ip = co + 16
    end = ip + insns*2
    n = 0
    while ip < end and n < maxn:
        op = data[ip]
        nm = OP.get(op, "op_0x%02x" % op)
        extra = ""; size = 2
        if op == 0x1a:
            extra = "  " + repr(gets(struct.unpack_from("<H", data, ip+2)[0])); size = 4
        elif op == 0x1b:
            extra = "  " + repr(gets(struct.unpack_from("<I", data, ip+2)[0])); size = 6
        elif op == 0x1c:
            extra = "  " + gett(struct.unpack_from("<H", data, ip+2)[0]); size = 4
        elif op == 0x22:
            extra = "  " + gett(struct.unpack_from("<H", data, ip+2)[0]); size = 4
        elif op in (0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a,0x5b,0x5c):
            extra = "  " + getf(struct.unpack_from("<H", data, ip+2)[0]); size = 4
        elif op in range(0x60, 0x6e):
            extra = "  " + getf(struct.unpack_from("<H", data, ip+2)[0]); size = 4
        elif op in (0x6e,0x6f,0x70,0x71,0x72):
            extra = "  " + getm(struct.unpack_from("<H", data, ip+2)[0]); size = 6
        elif op in (0x38,0x39,0x3a,0x3b,0x3c,0x3d,0x13,0x15,0x2a): size = 4
        elif op == 0x14 or op == 0x18: size = 6
        print("  @%05x  %-22s%s" % (ip, nm, extra))
        n += 1; ip += size

# Lqe 类
for i in range(fds):
    off = fdo + i*32
    v = struct.unpack_from("<8I", data, off)
    cn, cdoff = gett(v[0]), v[6]
    if not cdoff: continue
    short = cn.split("/")[-1].rstrip(";")
    if short not in ("Lqe", "Lx4"): continue
    p = cdoff
    sf, p = uleb(p); inf, p = uleb(p); dm, p = uleb(p); vm, p = uleb(p)
    for _ in range(sf+inf):
        _, p = uleb(p); _, p = uleb(p)
    for lab, cnt in (("d", dm), ("v", vm)):
        for _ in range(cnt):
            mi, p = uleb(p); a, p = uleb(p); co, p = uleb(p)
            mname = getm(mi)
            if short == "Lqe" or "onClick" in mname or mname.endswith(".o"):
                disasm(co, "%s.%s" % (short, mname.split(".")[-1]))

# 找所有含 device id 相关字符串的方法
print()
print("=" * 78)
print("★ 找含 'Device ID' / '设备' 相关字符串的方法")
print("=" * 78)
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
                if not co: continue
                try:
                    regs, ins, outs, tries, dbg, insns = struct.unpack_from("<HHHHII", data, co)
                except Exception:
                    continue
                ip = co + 16; end = ip + insns*2
                found = []
                while ip < end:
                    op = data[ip]
                    if op == 0x1a:
                        s = gets(struct.unpack_from("<H", data, ip+2)[0])
                        low = s.lower()
                        if "device" in low or "读取" in s or "修改" in s or "清空" in s or "设备" in s:
                            found.append(s)
                        ip += 4
                    elif op == 0x1b:
                        s = gets(struct.unpack_from("<I", data, ip+2)[0])
                        low = s.lower()
                        if "device" in low or "读取" in s or "修改" in s or "清空" in s or "设备" in s:
                            found.append(s)
                        ip += 6
                    elif op in (0x6e,0x6f,0x70,0x71,0x72): ip += 6
                    elif op in (0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a,
                                0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,
                                0x69,0x6a,0x6b,0x6c,0x6d): ip += 4
                    else: ip += 2
                if found:
                    print()
                    print("  【%s.%s】@0x%x" % (cn.split("/")[-1].rstrip(";"),
                                                getm(mi).split(".")[-1], co))
                    for s in found: print("     %r" % s)
                    disasm(co, "%s.%s" % (cn.split("/")[-1].rstrip(";"),
                                           getm(mi).split(".")[-1]), 100)
    except Exception:
        continue
