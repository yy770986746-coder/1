# -*- coding: utf-8 -*-
"""★ 严格按顺序：杀快手 → 杀cfprefsd → 改全部 → 杀cfprefsd → 启动"""
import sys, io, os, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
G = "/var/mobile/Containers/Shared/AppGroup/2B64FAB8-2826-4831-A314-5C6DCBEC275F"
NEW = "B28005FA-EE19-4A5F-B6D3-2D7024ECBD37"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=300):
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
print("步骤 1: 杀掉快手")
print("=" * 78)
so, _ = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '未运行'")
print("  " + so.strip())
so, _ = sush("""
launchctl list 2>/dev/null | grep -i jiangjia | awk '{print $1}' | while read p; do
  kill -9 "$p" 2>/dev/null && echo "  已杀 PID $p"
done
sleep 2
launchctl list 2>/dev/null | grep -i jiangjia || echo "  ✓ 快手已停止"
""")
print(so.strip())

print()
print("=" * 78)
print("步骤 2: ★ 杀 cfprefsd（清偏好缓存）")
print("=" * 78)
so, _ = sush("""
n=0
launchctl list 2>/dev/null | awk '$3 ~ /cfprefsd/ {print $1}' | while read p; do
  kill -9 "$p" 2>/dev/null && n=$((n+1))
done
sleep 1
echo "  已杀 cfprefsd"
launchctl list 2>/dev/null | grep -c cfprefsd | xargs echo "  剩余:"
""")
print(so.strip())

print()
print("=" * 78)
print("步骤 3: ★ 改所有位置")
print("=" * 78)
so, _ = sush("""
D="%s"
G="%s"
NEW="%s"

echo "[MMKV]"
for f in kKSUMMKVStoreKey kKSUHeartBeatReportKey com.kuaishou.KSNewDiskCache.startup \\
         com.kuaishou.ConfigCenter.KSStartupService gifshow account_main_app_data; do
  P="$D/Documents/mmkv/$f"
  [ -f "$P" ] || continue
  P2=$(stat -c '%%a' "$P" 2>/dev/null)
  C=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$P" 2>/dev/null | grep -v "$NEW" | head -1)
  [ -n "$C" ] && { LC_ALL=C sed -i "s/$C/$NEW/g" "$P"; echo "  ✓ $f"; }
  chmod "$P2" "$P" 2>/dev/null
done

echo "[AppGroup]"
for f in "$G/Library/Preferences/group.com.kwai.video.plist" \\
         "$G/UGExtension/ExtensionNetwork/params.plist"; do
  [ -f "$f" ] || continue
  C=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | grep -v "$NEW" | head -1)
  [ -n "$C" ] && { LC_ALL=C sed -i "s/$C/$NEW/g" "$f"; echo "  ✓ $(basename $f)"; }
done

echo "[旧AppGroup]"
for g2 in /var/mobile/Containers/Shared/AppGroup/*/; do
  [ -f "${g2}Library/Preferences/group.com.kwai.video.plist" ] || continue
  [ "$g2" = "$G/" ] && continue
  C=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \\
      "${g2}Library/Preferences/group.com.kwai.video.plist" 2>/dev/null | grep -v "$NEW" | head -1)
  [ -n "$C" ] && { LC_ALL=C sed -i "s/$C/$NEW/g" "${g2}Library/Preferences/group.com.kwai.video.plist"; echo "  ✓ $(basename $g2)"; }
done
""" % (D, G, NEW))
print(so.strip())

print()
print("=" * 78)
print("步骤 4: ★ 再杀 cfprefsd + 删 plist 缓存")
print("=" * 78)
so, _ = sush("""
launchctl list 2>/dev/null | awk '$3 ~ /cfprefsd/ {print $1}' | while read p; do
  kill -9 "$p" 2>/dev/null
done
sleep 2
echo "  ✓ cfprefsd 已重启"
""")
print(so.strip())

print()
print("=" * 78)
print("步骤 5: ★ 验证（快手仍是停止状态）")
print("=" * 78)
so, _ = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  ✓ 未运行'")
print("  进程: " + so.strip())
so, _ = sush("""
D="%s"
G="%s"
echo "[AppGroup 文件]"
V=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \\
    "$G/Library/Preferences/group.com.kwai.video.plist" 2>/dev/null | head -2)
echo "  $V"
echo "[MMKV]"
for f in kKSUMMKVStoreKey kKSUHeartBeatReportKey com.kuaishou.ConfigCenter.KSStartupService; do
  V=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \\
      "$D/Documents/mmkv/$f" 2>/dev/null | sort -u | head -2)
  echo "  $f: $V"
done
""" % (D, G))
print(so.strip())

c.close()
print()
print("=" * 78)
print("★ 请现在打开快手")
print("=" * 78)
