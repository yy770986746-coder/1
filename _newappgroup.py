# -*- coding: utf-8 -*-
"""改新的 AppGroup 的 did"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
G = "/var/mobile/Containers/Shared/AppGroup/2B64FAB8-2826-4831-A314-5C6DCBEC275F"
NEW = "B28005FA-EE19-4A5F-B6D3-2D7024ECBD37"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=300):
    _, o, e = c.exec_command(cmd, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

def sush(script, t=300):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

print("=" * 74)
print("1. 所有 AppGroup 及其内容")
print("=" * 74)
so, se = sush("""
for g in /var/mobile/Containers/Shared/AppGroup/*/; do
  M="${g}.com.apple.mobile_container_manager.metadata.plist"
  [ -f "$M" ] || continue
  ID=$(LC_ALL=C strings "$M" 2>/dev/null | grep -aE '^group\\.' | head -1)
  case "$ID" in
    *kwai*|*kuaishou*|*gif*)
      echo "  ★ $ID"
      echo "     路径: $g"
      # 看有没有 did
      find "$g" -type f -size -2M 2>/dev/null | while read f; do
        U=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | head -1)
        [ -n "$U" ] && echo "       $(basename "$f"): $U"
      done
      ;;
  esac
done
""", 600)
print(so.strip()[:2500])

print()
print("=" * 74)
print("2. 改新 AppGroup 的 did")
print("=" * 74)
so, se = sush("""
G="%s"
NEW="%s"

for f in "$G/Library/Preferences/group.com.kwai.video.plist" \\
         "$G/UGExtension/ExtensionNetwork/params.plist"; do
  [ -f "$f" ] || { echo "  跳过: $f"; continue; }
  CUR=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | grep -v "$NEW" | head -1)
  if [ -n "$CUR" ]; then
    LC_ALL=C sed -i "s/$CUR/$NEW/g" "$f"
    echo "  ✓ $(basename "$f"): $CUR → NEW"
  else
    echo "  · $(basename "$f"): 已OK 或 无值"
  fi
done
""" % (G, NEW))
print(so.strip())

print()
print("=" * 74)
print("3. 验证")
print("=" * 74)
so, se = sh("LC_ALL=C grep -ac 'B28005FA' '%s/Library/Preferences/group.com.kwai.video.plist' 2>/dev/null" % G)
print("  group.com.kwai.video.plist: %s 处 B28005FA" % so.strip())
so, se = sh("LC_ALL=C grep -ac 'A1B2C3D4' '%s/Library/Preferences/group.com.kwai.video.plist' 2>/dev/null" % G)
print("  残留 A1B2C3D4: %s 处" % so.strip())
so, se = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '未运行'")
print("  快手: " + so.strip())

c.close()
