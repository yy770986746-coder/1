# -*- coding: utf-8 -*-
"""找出 A1B2C3D4 还在哪里（它还在被发送）"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
V = "A1B2C3D4"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=900):
    _, o, e = c.exec_command(cmd, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

def sush(script, t=900):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

print("=" * 74)
print("1. 快手容器里所有含 A1B2C3D4 的文件")
print("=" * 74)
so, se = sush("""
D="%s"
find "$D" -type f -size -12M 2>/dev/null | head -1000 | while read f; do
  LC_ALL=C grep -qa 'A1B2C3D4' "$f" 2>/dev/null && echo "  ${f#$D/}"
done
""" % D, 900)
print(so.strip()[:2500] or "  (无)")

print()
print("=" * 74)
print("2. AppGroup 和系统位置")
print("=" * 74)
so, se = sush("""
G=/var/mobile/Containers/Shared/AppGroup
find "$G" -type f -size -4M 2>/dev/null | head -200 | while read f; do
  LC_ALL=C grep -qa 'A1B2C3D4' "$f" 2>/dev/null && echo "  [AG] $f"
done
find /var/mobile/Library -type f -size -4M 2>/dev/null | head -600 | while read f; do
  LC_ALL=C grep -qa 'A1B2C3D4' "$f" 2>/dev/null && echo "  [Lib] $f"
done
""", 900)
print(so.strip()[:2000] or "  (无)")

print()
print("=" * 74)
print("3. 网络缓存里 A1B2C3D4 的位置（看是不是历史记录）")
print("=" * 74)
CK = D + "/Library/Caches/com.jiangjia.gif/KSURLCache/Cache.db-wal"
so, se = sh("echo %s | sudo -S -p '' sh -c \"LC_ALL=C grep -c 'A1B2C3D4' '%s' 2>/dev/null\"" % (PWD, CK))
print("  Cache.db-wal 里 A1B2C3D4: %s 处" % so.strip())
so, se = sh("echo %s | sudo -S -p '' sh -c \"LC_ALL=C grep -c 'B28005FA' '%s' 2>/dev/null\"" % (PWD, CK))
print("  Cache.db-wal 里 B28005FA: %s 处" % so.strip())

c.close()
