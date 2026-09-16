# -*- coding: utf-8 -*-
"""★ 验证：快手实际发出的 did（网络缓存最新值）"""
import sys, io, os, re, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=600):
    _, o, e = c.exec_command(cmd, timeout=t)
    return (o.read().decode("utf-8", "replace"), e.read().decode("utf-8", "replace"))

def sush(script, t=600):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return (o.read().decode("utf-8", "replace"), e.read().decode("utf-8", "replace"))

print("=" * 78)
print("1. 缓存文件时间")
print("=" * 78)
so, _ = sh("ls -la '%s/Library/Caches/com.jiangjia.gif/KSURLCache/' 2>/dev/null" % D)
print(so.strip())

print()
print("=" * 78)
print("2. ★ Cache.db-wal 里最新的 30 个 did=（越靠后越新）")
print("=" * 78)
so, _ = sush("""
CK="%s/Library/Caches/com.jiangjia.gif/KSURLCache/Cache.db-wal"
[ -f "$CK" ] || { echo "  无缓存"; exit; }
LC_ALL=C grep -aoE 'did=[0-9A-Fa-f-]{36}' "$CK" 2>/dev/null | tail -30 | cat -n
echo "  --- 统计 ---"
LC_ALL=C grep -aoE 'did=[0-9A-Fa-f-]{36}' "$CK" 2>/dev/null | sort | uniq -c | sort -rn | head -5
""" % D)
print(so.strip())

print()
print("=" * 78)
print("3. ★ 最近 5 分钟修改的文件（快手写入了什么）")
print("=" * 78)
so, _ = sush("""
D="%s"
find "$D" -type f -newermt '-5 minutes' 2>/dev/null | head -40
""" % D)
print(so.strip()[:2500])

print()
print("=" * 78)
print("4. ★ 检查 fsCachedData（网络响应缓存）")
print("=" * 78)
so, _ = sush("""
FD="%s/Library/Caches/com.jiangjia.gif/KSURLCache/fsCachedData"
[ -d "$FD" ] || { echo "  无"; exit; }
ls -lat "$FD" 2>/dev/null | head -10
echo "  --- 最新文件里含 did 的 ---"
ls -t "$FD" 2>/dev/null | head -20 | while read f; do
  P="$FD/$f"
  [ -f "$P" ] || continue
  V=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$P" 2>/dev/null | head -1)
  [ -n "$V" ] && echo "  $f: $V"
done
""" % D)
print(so.strip()[:2500])

c.close()
