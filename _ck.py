# -*- coding: utf-8 -*-
"""验证 CloudKit 是否存储 did"""
import sys, io, os, re, base64, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
OLD = "7F00CDE1-343F-E599-DDB9-E81FE372EE9A"
CK = D + "/CloudKit/af22a2284caf56b0c1cf019abf7e37c820fe250b/Records/pcs.db"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=20,
          allow_agent=False, look_for_keys=False)
print("已连接\n")

def sh(cmd, t=600):
    _, o, e = c.exec_command(cmd, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

print("=== 1. CloudKit 目录结构 ===")
so, se = sh("find '%s/CloudKit' -type f 2>/dev/null | head -20" % D)
print(so.strip())

print()
print("=== 2. pcs.db 大小 ===")
so, se = sh("ls -la '%s' 2>/dev/null; ls -la '%s'* 2>/dev/null" % (CK, CK))
print(so.strip())

print()
print("=== 3. 拉取 pcs.db 看 did 上下文 ===")
so, se = sh("echo " + PWD + " | sudo -S -p '' sh -c \"base64 '%s'\"" % CK, 600)
b64 = "".join(so.split())
if b64:
    data = base64.b64decode(b64)
    print("  拉取 %d 字节" % len(data))
    # 找 did
    idx = data.find(OLD.encode())
    print("  旧 did 位置: %d" % idx)
    if idx >= 0:
        win = data[max(0, idx-200):idx+300]
        txt = "".join(chr(b) if 32 <= b < 127 else "." for b in win)
        print("  上下文:")
        for seg in re.findall(r"[\x20-\x7e]{15,}", txt):
            print("    %s" % seg[:150])
    # 所有 UUID
    uu = {}
    for m in re.finditer(rb"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", data):
        v = m.group(0).decode(); uu[v] = uu.get(v, 0) + 1
    print("  文件里的所有 UUID:")
    for v, n in sorted(uu.items(), key=lambda x: -x[1])[:10]:
        print("    %s (%d 次)" % (v, n))
else:
    print("  拉取失败")
c.close()
