# -*- coding: utf-8 -*-
"""★ 全盘扫描 A1B2C3D4 —— 找出所有还残留的位置"""
import sys, io, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sush(script, t=1800):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return o.read().decode("utf-8", "replace")

print("=" * 78)
print("1. ★ 快手容器内（全部文件）")
print("=" * 78)
so = sush("""
D="%s"
find "$D" -type f -size -20M 2>/dev/null | head -4000 | while read f; do
  LC_ALL=C grep -qa 'A1B2C3D4' "$f" 2>/dev/null && echo "  ${f#$D/}"
done
""" % D, 1800)
print(so.strip()[:3000] or "  (无)")

print()
print("=" * 78)
print("2. ★ AppGroup（全部）")
print("=" * 78)
so = sush("""
find /var/mobile/Containers/Shared/AppGroup -type f -size -20M 2>/dev/null | head -2000 | while read f; do
  LC_ALL=C grep -qa 'A1B2C3D4' "$f" 2>/dev/null && echo "  $f"
done
""", 1200)
print(so.strip()[:2000] or "  (无)")

print()
print("=" * 78)
print("3. 快手组的 Bundle 容器")
print("=" * 78)
so = sush("""
find /var/containers/Bundle/Application -maxdepth 3 -type d -name "*.app" 2>/dev/null | head -20
""")
print(so.strip())

print()
print("=" * 78)
print("4. ★ 系统级偏好设置")
print("=" * 78)
so = sush("""
ls -la /var/mobile/Library/Preferences/ 2>/dev/null | grep -iE 'kwai|gifshow|jiangjia'
echo "---"
for f in /var/mobile/Library/Preferences/*kwai* /var/mobile/Library/Preferences/*gifshow* \
         /var/mobile/Library/Preferences/*jiangjia*; do
  [ -f "$f" ] || continue
  V=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | head -3)
  echo "  $(basename $f): $V"
done
""")
print(so.strip()[:2000])

print()
print("=" * 78)
print("5. ★ 快手相关的所有容器目录")
print("=" * 78)
so = sush("""
ls -la /var/mobile/Containers/Data/Application/ 2>/dev/null | head -3
echo "--- 找 com.jiangjia.gif 的容器 ---"
for d in /var/mobile/Containers/Data/Application/*/; do
  M="${d}.com.apple.mobile_container_manager.metadata.plist"
  [ -f "$M" ] || continue
  ID=$(plutil -p "$M" 2>/dev/null | grep MCMMetadataIdentifier | head -1)
  case "$ID" in *jiangjia*|*kwai*|*gifshow*) echo "  $d  →  $ID";; esac
done
""", 600)
print(so.strip()[:2000])

c.close()
