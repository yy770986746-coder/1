# -*- coding: utf-8 -*-
"""读完整日志 + 验证版本"""
import sys, io, os, hashlib, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
LIB = "/var/jb/usr/lib/TweakInject"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=300):
    _, o, e = c.exec_command(cmd, timeout=t)
    return o.read().decode("utf-8", "replace")

print("=" * 78)
print("1. 设备上的 dylib 版本标记")
print("=" * 78)
so = sh("LC_ALL=C strings %s/KSDid.dylib 2>/dev/null | grep -a 'KSDid v' | head -3" % LIB)
print("  " + so.strip())
so = sh("md5sum %s/KSDid.dylib 2>/dev/null; md5sum /var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.dylib 2>/dev/null" % LIB)
print("  MD5: " + so.strip())

print()
print("=" * 78)
print("2. dylib 里有没有 v15 的标记")
print("=" * 78)
for m in ["v15", "候选条目内容 dump", "dump 结束", "KC写"]:
    so = sh("LC_ALL=C strings %s/KSDid.dylib 2>/dev/null | grep -ac '%s' || echo 0" % (LIB, m))
    print("  %-22s %s" % (m, so.strip()))

print()
print("=" * 78)
print("3. ★ 完整日志（全部行）")
print("=" * 78)
LOG = D + "/Documents/ksdid_log.txt"
so = sh("wc -l '%s' 2>/dev/null" % LOG)
print("  行数: " + so.strip())
s = sh("cat '%s' 2>/dev/null" % LOG)
lines = s.strip().split("\n") if s.strip() else []
print("  实际 %d 行" % len(lines))
print()
for i, l in enumerate(lines):
    print("%4d| %s" % (i, l[:220]))

c.close()
