# -*- coding: utf-8 -*-
"""快手已停：立即改 AppGroup"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
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
print("1. 列出所有 AppGroup 目录")
print("=" * 74)
so, se = sh("ls -d /var/mobile/Containers/Shared/AppGroup/*/ 2>/dev/null | head -60")
dirs = [x.strip() for x in so.split("\n") if x.strip()]
print("  共 %d 个" % len(dirs))

print()
print("=" * 74)
print("2. 找含快手数据的（用 group.com.kwai.video.plist 判断）")
print("=" * 74)
so, se = sh("for g in /var/mobile/Containers/Shared/AppGroup/*/; do "
            "[ -f \"${g}Library/Preferences/group.com.kwai.video.plist\" ] && echo \"$g\"; done")
kwai_groups = [x.strip() for x in so.split("\n") if x.strip()]
print("  找到 %d 个:" % len(kwai_groups))
for g in kwai_groups:
    so2, se2 = sh("LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "
                  "'%sLibrary/Preferences/group.com.kwai.video.plist' 2>/dev/null | head -1" % g)
    print("    %s" % g)
    print("      did = %s" % (so2.strip() or "(无)"))

print()
print("=" * 74)
print("3. 改所有快手的 AppGroup")
print("=" * 74)
so, se = sush("""
NEW="%s"
for g in /var/mobile/Containers/Shared/AppGroup/*/; do
  [ -f "${g}Library/Preferences/group.com.kwai.video.plist" ] || continue
  echo "  [$(basename "$g")]"
  for f in "${g}Library/Preferences/group.com.kwai.video.plist" \\
           "${g}UGExtension/ExtensionNetwork/params.plist"; do
    [ -f "$f" ] || continue
    CUR=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | grep -v "$NEW" | head -1)
    if [ -n "$CUR" ]; then
      LC_ALL=C sed -i "s/$CUR/$NEW/g" "$f"
      echo "    ✓ $(basename "$f"): $CUR → NEW"
    else
      echo "    · $(basename "$f"): 已是目标值"
    fi
  done
done
""" % NEW, 600)
print(so.strip()[:2000])

print()
print("=" * 74)
print("4. 验证 + 确认快手未运行")
print("=" * 74)
so, se = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  快手未运行 ✓'")
print("  " + so.strip())
so, se = sh("for g in /var/mobile/Containers/Shared/AppGroup/*/; do "
            "[ -f \"${g}Library/Preferences/group.com.kwai.video.plist\" ] || continue; "
            "V=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "
            "\"${g}Library/Preferences/group.com.kwai.video.plist\" 2>/dev/null | head -1); "
            "echo \"    $(basename $(dirname $g)): $V\"; done")
print("  AppGroup 值:")
print(so.strip())

c.close()
print()
print("=" * 74)
print("请立即打开快手（不要等）")
print("=" * 74)
