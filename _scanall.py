# -*- coding: utf-8 -*-
"""找 kstoken 里所有调用 ProcessBuilder / 写 MMKV 的方法"""
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
fds, fdo = hdr[19], hdr[20]   # class_defs

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
    return "%s->%s" % (gett(ci), gets(ni))

def getf(i):
    if i >= fis: return "?"
    o = fio + i*8
    ci, ti, ni = struct.unpack_from("<HHI", data, o)
    return "%s->%s" % (gett(ci), gets(ni))

def name_of(t):
    return t.split("/")[-1].rstrip(";")

# 遍历所有类
print("=" * 78)
print("★ 扫描所有类，找调用 ProcessBuilder / MMKV 的方法")
print("=" * 78)

allclasses = []
for i in range(fds):
    off = fdo + i*32
    v = struct.unpack_from("<8I", data, off)
    allclasses.append((gett(v[0]), v[1], v[6]))

KEYWORDS = ["ProcessBuilder", "Runtime", "exec", "MMKV", "encodeString",
            "decodeString", "force-stop", "chmod"]

for cn, acc, cdoff in allclasses:
    if not cdoff: continue
    p = cdoff
    try:
        sf, p = uleb(p); inf, p = uleb(p); dm, p = uleb(p); vm, p = uleb(p)
        for _ in range(sf + inf):
            _, p = uleb(p); _, p = uleb(p)
        methods = []
        for label, cnt in (("direct", dm), ("virtual", vm)):
            for _ in range(cnt):
                mi, p = uleb(p); a, p = uleb(p); co, p = uleb(p)
                methods.append((getm(mi), co))
    except Exception:
        continue

    for mname, codeoff in methods:
        if not codeoff: continue
        try:
            regs, ins, outs, tries, dbg, insns = struct.unpack_from("<HHHHII", data, codeoff)
        except Exception:
            continue
        ip = codeoff + 16
        end = ip + insns*2
        hits = []
        strings = []
        while ip < end:
            op = data[ip]
            if op == 0x1a:
                strings.append(gets(struct.unpack_from("<H", data, ip+2)[0])); ip += 4
            elif op == 0x1b:
                strings.append(gets(struct.unpack_from("<I", data, ip+2)[0])); ip += 6
            elif op in (0x6e,0x6f,0x70,0x71,0x72):
                mm = getm(struct.unpack_from("<H", data, ip+2)[0])
                if any(k in mm for k in KEYWORDS):
                    hits.append("CALL " + mm)
                ip += 6
            elif op in (0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5a):
                ff = getf(struct.unpack_from("<H", data, ip+2)[0])
                if any(k in ff for k in KEYWORDS):
                    hits.append("FIELD " + ff)
                ip += 4
            elif op in (0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,
                        0x69,0x6a,0x6b,0x6c,0x6d):
                ip += 4
            else:
                ip += 2

        interesting_str = [s for s in strings
                           if any(k in s for k in ["mmkv","gifshow","force-stop",
                                                    "chmod","device","did","json",
                                                    "MMKV","Generate","sms",".crc"])]
        if hits or interesting_str:
            print()
            print("  【%s】" % mname)
            if interesting_str:
                print("     字符串:")
                for s in interesting_str[:20]:
                    print("       %r" % s)
            if hits:
                print("     调用/字段:")
                for h in hits[:20]:
                    print("       %s" % h)
