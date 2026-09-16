# -*- coding: utf-8 -*-
"""快手已停：写入 did 到所有位置（含动态 AppGroup）"""
import sys, io, os, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
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
print("1. 确认快手已停止")
print("=" * 74)
so, se = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  未运行 ✓'")
print("  " + so.strip())
pid = so.strip().split()[0] if so.strip() and so.strip()[0].isdigit() else "0"
if pid != "0":
    print()
    print("  ⚠ 快手仍在运行 (PID %s)，尝试杀掉..." % pid)
    so, se = sush("kill -9 %s 2>/dev/null; sleep 2; launchctl list 2>/dev/null | grep -i jiangjia || echo '已停止'" % pid)
    print("  " + so.strip())

print()
print("=" * 74)
print("2. ★ 动态查找所有快手的 AppGroup 并改 did")
print("=" * 74)
so, se = sush("""
NEW="%s"

for g in /var/mobile/Containers/Shared/AppGroup/*/; do
  M="${g}.com.apple.mobile_container_manager.metadata.plist"
  [ -f "$M" ] || continue
  ID=$(LC_ALL=C strings "$M" 2>/dev/null | grep -aE '^group\\.' | head -1)
  case "$ID" in
    *kwai*|*kuaishou*|*gif*)
      echo "  [AppGroup] $(basename "$g")  ($ID)"
      for f in "$g/Library/Preferences/group.com.kwai.video.plist" \\
               "$g/UGExtension/ExtensionNetwork/params.plist"; do
        [ -f "$f" ] || continue
        CUR=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | grep -v "$NEW" | head -1)
        if [ -n "$CUR" ]; then
          LC_ALL=C sed -i "s/$CUR/$NEW/g" "$f"
          echo "      ✓ $(basename "$f"): $CUR → NEW"
        else
          echo "      · $(basename "$f"): 已OK"
        fi
      done
      ;;
  esac
done
""" % NEW, 600)
print(so.strip()[:2500])

print()
print("=" * 74)
print("3. MMKV + 明文 + 插件配置")
print("=" * 74)
so, se = sush("""
D="%s"
NEW="%s"

for f in kKSUMMKVStoreKey kKSUHeartBeatReportKey com.kuaishou.KSNewDiskCache.startup com.kuaishou.ConfigCenter.KSStartupService; do
  P="$D/Documents/mmkv/$f"
  [ -f "$P" ] || continue
  PERM=$(stat -c '%%a' "$P" 2>/dev/null)
  CUR=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$P" 2>/dev/null | grep -v "$NEW" | head -1)
  if [ -n "$CUR" ]; then
    LC_ALL=C sed -i "s/$CUR/$NEW/g" "$P"
    echo "  ✓ MMKV $f: $CUR → NEW"
  fi
  chmod "$PERM" "$P" 2>/dev/null
done

printf '%%s' "$NEW" > "$D/Library/Application Support/com.kuaishou.did"
echo "  ✓ 明文 did"
echo "$NEW" > "$D/Documents/ks_did.txt"
echo "  ✓ 插件配置"
""" % (D, NEW))
print(so.strip())

print()
print("=" * 74)
print("4. 刷新 cfprefsd")
print("=" * 74)
so, se = sush("""
launchctl list 2>/dev/null | awk '$3 ~ /cfprefsd/ {print $1}' | while read p; do
  kill -9 "$p" 2>/dev/null
done
sleep 1
echo "  完成"
""")
print(so.strip())

print()
print("=" * 74)
print("5. ★ 最终验证（快手必须仍未运行）")
print("=" * 74)
so, se = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  未运行 ✓'")
print("  进程: " + so.strip())
so, se = sush("""
for g in /var/mobile/Containers/Shared/AppGroup/*/; do
  M="${g}.com.apple.mobile_container_manager.metadata.plist"
  [ -f "$M" ] || continue
  ID=$(LC_ALL=C strings "$M" 2>/dev/null | grep -aE '^group\\.' | head -1)
  case "$ID" in
    *kwai*|*kuaishou*|*gif*)
      P="$g/Library/Preferences/group.com.kwai.video.plist"
      [ -f "$P" ] || continue
      V=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$P" 2>/dev/null | head -1)
      echo "  $(basename "$g"): $V"
      ;;
  esac
done
""", 300)
print(so.strip())

c.close()
print()
print("=" * 74)
print("请现在打开快手（先不要动别的）")
print("=" * 74)
