# -*- coding: utf-8 -*-
"""检查快手实际发出的 did（网络缓存）"""
import sys, io, os, re, base64, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=600):
    _, o, e = c.exec_command(cmd, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

print("=" * 74)
print("1. 找到 KSURLCache 网络缓存")
print("=" * 74)
so, se = sh("find '%s/Library/Caches' -name 'Cache.db*' -o -name '*-wal' 2>/dev/null | grep -i ksurl | head -5" % D)
print("  " + (so.strip() or "(未找到)"))

# 找缓存目录
so, se = sh("ls -la '%s/Library/Caches/com.jiangjia.gif/KSURLCache/' 2>/dev/null | head -10" % D)
print()
print("  KSURLCache 目录:")
print("  " + so.strip()[:800])

print()
print("=" * 74)
print("2. ★ 网络缓存里最新的 did= 值（快手实际发送的）")
print("=" * 74)
CK = D + "/Library/Caches/com.jiangjia.gif/KSURLCache/Cache.db-wal"
so, se = sh("echo %s | sudo -S -p '' sh -c \"base64 '%s' 2>/dev/null\"" % (PWD, CK), 600)
b64 = "".join(so.split())
if not b64:
    # 试试别的
    so, se = sh("find '%s/Library/Caches' -name 'Cache.db-wal' 2>/dev/null | head -3" % D)
    print("  尝试其他: " + so.strip())
else:
    data = base64.b64decode(b64)
    print("  缓存大小: %d 字节" % len(data))
    print()
    print("  did= 的所有值（按出现次数）:")
    seen = {}
    for m in re.finditer(rb"did=([0-9A-Fa-f\-]{36})", data):
        v = m.group(1).decode()
        seen[v] = seen.get(v, 0) + 1
    for v, n in sorted(seen.items(), key=lambda x: -x[1]):
        mark = ""
        if v.startswith("B28005FA"): mark = " ★ 我们的目标值"
        if v.startswith("A1B2C3D4"): mark = " ← 界面显示的"
        print("    %s  (%d 次)%s" % (v, n, mark))

    print()
    print("  ★ 最新的 5 个 did=（文件末尾，越后越新）:")
    tail = data[-300000:]
    ms = list(re.finditer(rb"did=([0-9A-Fa-f\-]{36})", tail))
    for m in ms[-5:]:
        print("    %s" % m.group(1).decode())

c.close()
