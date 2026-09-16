# -*- coding: utf-8 -*-
"""下载 dylib 本地检查签名 + 架构"""
import sys, io, os, struct, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
LIB = "/var/jb/usr/lib/TweakInject"
TMP = r"C:\Users\yyds\Desktop\ios快手上号器\_dylib"

os.makedirs(TMP, exist_ok=True)
c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

sftp = c.open_sftp()
for f in ["KSDid.dylib", "KSDid.plist"]:
    p = LIB + "/" + f
    lp = os.path.join(TMP, f)
    sftp.get(p, lp)
    print("  ✓ %s  (%d bytes)" % (f, os.path.getsize(lp)))
sftp.close()
c.close()

# 分析 Mach-O
import io as _io
path = os.path.join(TMP, "KSDid.dylib")
data = open(path, "rb").read()
magic = struct.unpack_from("<I", data, 0)[0]
print()
print("=" * 78)
print("1. Mach-O 头")
print("=" * 78)
print("  magic = 0x%08x %s" % (magic,
      {0xfeedface: "MH_MAGIC (32位)", 0xfeedfacf: "MH_MAGIC_64 (64位)",
       0xcafebabe: "FAT (universal)", 0xbebafeca: "FAT_64"}.get(magic, "?")))

def parse_macho(off, label):
    m = struct.unpack_from("<I", data, off)[0]
    if m not in (0xfeedface, 0xfeedfacf): return
    is64 = (m == 0xfeedfacf)
    cputype, cpusubtype, ftype, ncmds, sizeofcmds, flags = \
        struct.unpack_from("<iiIIII", data, off + 4)
    print("  [%s] cputype=%d (0x%x) cpusubtype=0x%x ftype=%d ncmds=%d flags=0x%x" %
          (label, cputype, cputype, cpusubtype, ftype, ncmds, flags))
    arch = {16777228: "arm64", 16777222: "arm64_32", 12: "armv7"}.get(cputype, str(cputype))
    print("        架构 = %s" % arch)
    # 遍历 load commands 找 LC_CODE_SIGNATURE
    p = off + (32 if is64 else 28)
    has_cs = False
    cs_off = cs_size = 0
    for i in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, p)
        if cmd == 0x1d:  # LC_CODE_SIGNATURE
            has_cs = True
            cs_off, cs_size = struct.unpack_from("<II", data, p + 8)
        if cmd == 0xc:   # LC_LOAD_DYLIB
            nameoff = struct.unpack_from("<I", data, p + 8)[0]
            nm = data[p+nameoff:p+nameoff+80].split(b"\x00")[0].decode("utf-8","replace")
            print("        dylib: %s" % nm)
        p += cmdsize
    print("        LC_CODE_SIGNATURE: %s  (off=%d size=%d)" %
          ("✓" if has_cs else "✗ 无签名!", cs_off, cs_size))

if magic == 0xcafebabe:
    n = struct.unpack_from(">I", data, 4)[0]
    print("  FAT 含 %d 个架构" % n)
    for i in range(n):
        o = 8 + i * 20
        ct, cs, off, sz, al = struct.unpack_from(">iiIII", data, o)
        arch = {16777228: "arm64", 16777222: "arm64_32", 12: "armv7"}.get(ct, str(ct))
        print("    架构 %d: %s (offset=%d size=%d)" % (i, arch, off, sz))
        parse_macho(off, arch)
else:
    parse_macho(0, "single")

print()
print("=" * 78)
print("2. ★ 是否有 arm64e")
print("=" * 78)
if magic == 0xcafebabe:
    n = struct.unpack_from(">I", data, 4)[0]
    for i in range(n):
        o = 8 + i * 20
        ct, cs = struct.unpack_from(">ii", data, o)
        desc = {16777228: "arm64", 16777222: "arm64_32", 12: "armv7",
                16777228: "arm64"}.get(ct, str(ct))
        sub = cs & 0xff
        print("    0x%x subtype=%d" % (ct, sub))

print()
print("=" * 78)
print("3. dylib 里有没有 v13 的标记字符串")
print("=" * 78)
for marker in [b"KSDid v13", b"Keychain \xe6\x9e\x9a\xe4\xb8\xbe", b"##########",
               b"sha1(empty)", b"NR2KD6K4TL"]:
    cnt = data.count(marker)
    print("  %-40s %s" % (marker.decode("utf-8", "replace"), "✓ %d 处" % cnt if cnt else "✗ 无"))
