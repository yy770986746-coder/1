# -*- coding: utf-8 -*-
"""★ 找 A1B2C3D4 在服务端响应缓存里的位置"""
import sys, io, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sush(script, t=900):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return o.read().decode("utf-8", "replace")

print("=" * 78)
print("1. ★ 容器内所有含 A1B2C3D4 的文件（全部，不过滤）")
print("=" * 78)
so = sush("""
D="%s"
find "$D" -type f 2>/dev/null | while read f; do
  LC_ALL=C grep -qa 'A1B2C3D4' "$f" 2>/dev/null && echo "  ${f#$D/}  ($(stat -c %%s "$f" 2>/dev/null)B)"
done
""" % D, 900)
print(so.strip()[:3000] or "  (无)")

print()
print("=" * 78)
print("2. ★ AppGroup 全部（不过滤）")
print("=" * 78)
so = sush("""
for g in /var/mobile/Containers/Shared/AppGroup/*/; do
  [ -d "$g" ] || continue
  find "$g" -type f 2>/dev/null | while read f; do
    LC_ALL=C grep -qa 'A1B2C3D4' "$f" 2>/dev/null && echo "  $f"
  done
done
""", 900)
print(so.strip()[:2000] or "  (无)")

print()
print("=" * 78)
print("3. ★ 系统级（快手可能放在别处）")
print("=" * 78)
so = sush("""
find /var/mobile/Library -type f -size -5M 2>/dev/null | while read f; do
  LC_ALL=C grep -qa 'A1B2C3D4' "$f" 2>/dev/null && echo "  [Lib] $f"
done
find /var/mobile/Documents -type f -size -5M 2>/dev/null | while read f; do
  LC_ALL=C grep -qa 'A1B2C3D4' "$f" 2>/dev/null && echo "  [Doc] $f"
done
""" , 900)
print(so.strip()[:2000] or "  (无)")

print()
print("=" * 78)
print("4. ★ 网络缓存里 A1B2C3D4 的上下文（看是请求还是响应）")
print("=" * 78)
so = sush("""
CK="%s/Library/Caches/com.jiangjia.gif/KSURLCache/Cache.db-wal"
LC_ALL=C grep -ao '.\{0,120\}A1B2C3D4.\{0,80\}' "$CK" 2>/dev/null | head -6 | cat -A 2>/dev/null | head -20 || \
LC_ALL=C grep -ao '.\{0,120\}A1B2C3D4.\{0,80\}' "$CK" 2>/dev/null | head -8
""" % D)
print(so.strip()[:3000] or "  (无)")

c.close()
