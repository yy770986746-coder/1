# -*- coding: utf-8 -*-
"""反汇编 kstoken 的 MainActivity.onCreate —— 看它真正做了什么"""
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
    sid = struct.unpack_from("<I", data, tio + i*4)[0]
    return gets(sid)

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

# 找 MainActivity.onCreate 的 code offset
cdoff = None
for i in range(hdr[19]):
    off = hdr[20] + i*32
    v = struct.unpack_from("<8I", data, off)
    cn = gett(v[0])
    if "MainActivity" in cn and "kstoken" in cn:
        cdoff = v[6]
        break

print("MainActivity class_data @0x%x" % (cdoff or 0))
p = cdoff
sf, p = uleb(p); inf, p = uleb(p); dm, p = uleb(p); vm, p = uleb(p)
for _ in range(sf + inf):
    _, p = uleb(p); _, p = uleb(p)

targets = {}
for label, cnt in (("direct", dm), ("virtual", vm)):
    for _ in range(cnt):
        mi, p = uleb(p); acc, p = uleb(p); co, p = uleb(p)
        if "onCreate" in getm(mi) or "onClick" in getm(mi):
            targets[getm(mi)] = co

print("目标方法:")
for k, v in targets.items():
    print("  %s @0x%x" % (k, v))

# 手动解析一个方法的字节码，提取 const-string / invoke
def disasm(codeoff, name):
    print()
    print("=" * 78)
    print("★ %s" % name)
    print("=" * 78)
    # 找 code_item：DEX 无直接指针，需要从 map 或线性扫描
    # 简便法：code_item 结构 registers_size(2) ins_size(2) outs_size(2) tries_size(2) debug_info_off(4) insns_size(4)
    p = codeoff
    regs, ins, outs, tries, dbg, insns_sz = struct.unpack_from("<HHHHII", data, p)
    print("  registers=%d ins=%d outs=%d tries=%d insns=%d" % (regs, ins, outs, tries, insns_sz))
    ip = p + 16
    end = ip + insns_sz * 2
    strings = []
    invokes = []
    fields = []
    while ip < end:
        op = data[ip]
        if op == 0x1a:      # const-string
            idx = struct.unpack_from("<H", data, ip + 2)[0]
            strings.append(gets(idx))
            ip += 4
        elif op == 0x1b:    # const-string/jumbo
            idx = struct.unpack_from("<I", data, ip + 2)[0]
            strings.append(gets(idx))
            ip += 6
        elif op in (0x6e, 0x6f, 0x70, 0x71, 0x72):  # invoke-*
            mi = struct.unpack_from("<H", data, ip + 2)[0]
            invokes.append(getm(mi))
            ip += 6
        elif op in (0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a):
            fi = struct.unpack_from("<H", data, ip + 2)[0]
            fields.append(getf(fi))
            ip += 4
        elif op in (0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
                    0x69, 0x6a, 0x6b, 0x6c, 0x6d):
            ip += 4
        elif op == 0x00:
            ip += 2
        else:
            ip += 2
    print("  --- 字符串常量 ---")
    for s in strings:
        if len(s) < 100:
            print("    %r" % s)
    print("  --- 方法调用 ---")
    for m in invokes:
        print("    %s" % m)
    print("  --- 字段访问 ---")
    for f in fields:
        print("    %s" % f)

for k, v in targets.items():
    if v:
        disasm(v, k)
