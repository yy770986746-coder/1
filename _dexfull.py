# -*- coding: utf-8 -*-
"""解析 kstoken dex —— 提取方法和字段"""
import sys, io, os, struct, re

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
DEX = r"C:\Users\yyds\Desktop\ios快手上号器\_kstoken_dex\classes.dex"
data = open(DEX, "rb").read()

hdr = struct.unpack_from("<8sI20s20I", data, 0)
string_ids_size, string_ids_off = hdr[9], hdr[10]
type_ids_size, type_ids_off = hdr[11], hdr[12]
proto_ids_size, proto_ids_off = hdr[13], hdr[14]
field_ids_size, field_ids_off = hdr[15], hdr[16]
method_ids_size, method_ids_off = hdr[17], hdr[18]
class_defs_size, class_defs_off = hdr[19], hdr[20]

def uleb(p):
    n = 0; shift = 0
    while True:
        b = data[p]; p += 1
        n |= (b & 0x7f) << shift
        if not (b & 0x80): break
        shift += 7
        if shift > 28: break
    return n, p

def get_str(idx):
    if idx >= string_ids_size: return ""
    off = struct.unpack_from("<I", data, string_ids_off + idx*4)[0]
    n, p = uleb(off)
    return data[p:p+n].decode("utf-8", "replace").rstrip("\x00")

def get_type(idx):
    if idx >= type_ids_size: return ""
    sid = struct.unpack_from("<I", data, type_ids_off + idx*4)[0]
    return get_str(sid)

def get_method(midx):
    if midx >= method_ids_size: return ("", "", "")
    moff = method_ids_off + midx * 8
    cls_idx, proto_idx, name_idx = struct.unpack_from("<HHI", data, moff)
    return (get_type(cls_idx), get_str(name_idx), get_type(proto_idx) if False else "")

def get_field(fidx):
    if fidx >= field_ids_size: return ("", "")
    foff = field_ids_off + fidx * 8
    cls_idx, type_idx, name_idx = struct.unpack_from("<HHI", data, foff)
    return (get_type(cls_idx), get_str(name_idx))

print("=" * 74)
print("★ kstoken 的类和方法")
print("=" * 74)
for i in range(class_defs_size):
    off = class_defs_off + i * 32
    vals = struct.unpack_from("<8I", data, off)
    class_idx, access_flags, superclass_idx = vals[0], vals[1], vals[2]
    class_data_off = vals[6]
    cn = get_type(class_idx)
    if "kstoken" not in cn: continue

    print()
    print("  【%s】 extends %s" % (cn, get_type(superclass_idx)))
    if not class_data_off:
        print("    (无方法体)")
        continue
    p = class_data_off
    sf, p = uleb(p); inf, p = uleb(p); dm, p = uleb(p); vm, p = uleb(p)

    print("    字段: static=%d instance=%d | 方法: direct=%d virtual=%d" % (sf, inf, dm, vm))

    for _ in range(sf + inf):
        fidx, p = uleb(p); acc, p = uleb(p)

    for label, cnt in (("direct", dm), ("virtual", vm)):
        for _ in range(cnt):
            midx, p = uleb(p)
            acc, p = uleb(p)
            code_off, p = uleb(p)
            cls, name, _ = get_method(midx)
            print("      [%s] %s.%s (code=0x%x)" % (label, cls.split("/")[-1], name, code_off))

print()
print("=" * 74)
print("★ 所有 MMKV/快手 相关字符串")
print("=" * 74)
for i in range(string_ids_size):
    s = get_str(i)
    low = s.lower()
    if any(k in low for k in ["gifshow", "account_", "egid", "kwtk", "salt",
                               "cache_did", "cloud_did", "device_id"]) and 3 < len(s) < 70:
        print("  [%4d] %s" % (i, s))

print()
print("=" * 74)
print("★ 所有文件路径字符串")
print("=" * 74)
for i in range(string_ids_size):
    s = get_str(i)
    if "/" in s and ("data" in s or "mmkv" in s or "gifshow" in s or "smile" in s):
        print("  [%4d] %s" % (i, s))

print()
print("=" * 74)
print("★ 所有 shell 命令相关")
print("=" * 74)
for i in range(string_ids_size):
    s = get_str(i)
    if any(k in s for k in ["force-stop", "chmod", "su ", "sh ", "/system/bin",
                             "Runtime", "exec", "Process"]):
        print("  [%4d] %s" % (i, s))
