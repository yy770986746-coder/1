# -*- coding: utf-8 -*-
"""★ 完整反汇编 kstoken 的写入口方法 —— 逐条指令"""
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

# 找到写入口：含 'ksX' 的那个方法
TARGET = None
for cn, mn, co in allm:
    if not co: continue
    try:
        regs, ins, outs, tries, dbg, insns = struct.unpack_from("<HHHHII", data, co)
    except Exception:
        continue
    ip = co + 16
    end = ip + insns*2
    found = False
    while ip < end:
        op = data[ip]
        if op == 0x1a:
            if gets(struct.unpack_from("<H", data, ip+2)[0]) == "ksX":
                found = True
                break
            ip += 4
        elif op == 0x1b:
            ip += 6
        elif op in (0x6e,0x6f,0x70,0x71,0x72):
            ip += 6
        elif op in (0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a):
            ip += 4
        elif op in (0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,
                    0x69,0x6a,0x6b,0x6c,0x6d):
            ip += 4
        else:
            ip += 2
    if found:
        TARGET = (cn, mn, co)
        break

if not TARGET:
    print("未找到含 ksX 的方法")
    sys.exit()

cn, mn, co = TARGET
print("=" * 78)
print("★ 写入口方法: %s  %s  @0x%x" % (cn, mn, co))
print("=" * 78)
regs, ins, outs, tries, dbg, insns = struct.unpack_from("<HHHHII", data, co)
print("registers=%d ins=%d outs=%d tries=%d insns=%d" % (regs, ins, outs, tries, insns))
print()

# ★ 完整反汇编
ip = co + 16
end = ip + insns * 2
idx = 0
while ip < end:
    op = data[ip]
    name = None
    extra = ""
    size = 2
    if op == 0x00:   name = "nop"; size = 2
    elif op == 0x01: name = "move"; size = 2
    elif op == 0x0e: name = "return-void"; size = 2
    elif op == 0x0f: name = "return"; size = 2
    elif op == 0x10: name = "return-wide"; size = 2
    elif op == 0x11: name = "return-object"; size = 2
    elif op == 0x12: name = "const/4"; size = 2
    elif op == 0x13: name = "const/16"; size = 4
    elif op == 0x14: name = "const"; size = 6
    elif op == 0x15: name = "const/high16"; size = 4
    elif op == 0x1a:
        name = "const-string"; size = 4
        extra = repr(gets(struct.unpack_from("<H", data, ip+2)[0]))
    elif op == 0x1b:
        name = "const-string/jumbo"; size = 6
        extra = repr(gets(struct.unpack_from("<I", data, ip+2)[0]))
    elif op == 0x1c: name = "const-class"; size = 4
    elif op == 0x22: name = "new-instance"; size = 4
    elif op == 0x23: name = "new-array"; size = 4
    elif op in (0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a):
        name = {0x52:"iget",0x53:"iget-wide",0x54:"iget-object",0x55:"iget-boolean",
                0x56:"iget-byte",0x57:"iget-char",0x58:"iget-short",
                0x59:"iput",0x5a:"iput-object"}[op]; size = 4
        extra = getf(struct.unpack_from("<H", data, ip+2)[0])
    elif op in (0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,
                0x69,0x6a,0x6b,0x6c,0x6d):
        name = {0x60:"sget",0x61:"sget-wide",0x62:"sget-object",0x63:"sget-boolean",
                0x64:"sget-byte",0x65:"sget-char",0x66:"sget-short",
                0x67:"sput",0x68:"sput-wide",0x69:"sput-object",0x6a:"sput-boolean",
                0x6b:"sput-byte",0x6c:"sput-char",0x6d:"sput-short"}[op]; size = 4
        extra = getf(struct.unpack_from("<H", data, ip+2)[0])
    elif op in (0x6e,0x6f,0x70,0x71,0x72):
        name = {0x6e:"invoke-virtual",0x6f:"invoke-super",0x70:"invoke-direct",
                0x71:"invoke-static",0x72:"invoke-interface"}[op]; size = 6
        extra = getm(struct.unpack_from("<H", data, ip+2)[0])
    elif op == 0x71: name = "invoke-static"; size = 6
    elif op == 0x38: name = "if-eqz"; size = 4
    elif op == 0x39: name = "if-nez"; size = 4
    elif op == 0x3a: name = "if-ltz"; size = 4
    elif op == 0x3b: name = "if-gez"; size = 4
    elif op == 0x90: name = "add-int"; size = 4
    elif op == 0x99: name = "if-eq"; size = 4
    else: name = "op_0x%02x" % op; size = 2

    print("%4d  @%05x  %-22s %s" % (idx, ip, name, extra))
    idx += 1
    ip += size
