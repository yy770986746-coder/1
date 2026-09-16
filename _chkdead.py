# -*- coding: utf-8 -*-
"""验证快手是否死了 + 当前 did 状态"""
import sys, io, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
G = "/var/mobile/Containers/Shared/AppGroup/2B64FAB8-2826-4831-A314-5C6DCBEC275F"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=300):
    _, o, e = c.exec_command(cmd, timeout=t)
    return o.read().decode("utf-8", "replace")

def sush(script, t=600):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return o.read().decode("utf-8", "replace")

print("=" * 78)
print("1. 快手是否真的死了")
print("=" * 78)
so = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  OK 未运行'")
print("  进程: " + so.strip())
so = sh("ps aux 2>/dev/null | grep jiangjia | grep -v grep | wc -l")
print("  ps 匹配数: " + so.strip())

print()
print("=" * 78)
print("2. 当前存储状态")
print("=" * 78)
so = sush("""
echo "  [AppGroup 新]"
LC_ALL=C grep -aoE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
  "%s/Library/Preferences/group.com.kwai.video.plist" 2>/dev/null | head -1

echo "  [AppGroup 旧]"
for g in /var/mobile/Containers/Shared/AppGroup/*/; do
  [ -f "${g}Library/Preferences/group.com.kwai.video.plist" ] || continue
  [ "$g" = "%s/" ] && continue
  echo "    $(basename $g): $(LC_ALL=C grep -aoE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' "${g}Library/Preferences/group.com.kwai.video.plist" 2>/dev/null | head -1)"
done

echo "  [MMKV 关键文件]"
for f in kKSUMMKVStoreKey kKSUHeartBeatReportKey com.kuaishou.ConfigCenter.KSStartupService com.kuaishou.KSNewDiskCache.startup; do
  V=$(LC_ALL=C grep -aoE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
      "%s/Documents/mmkv/$f" 2>/dev/null | sort -u | tr '\\n' ' ')
  echo "    $f: $V"
done

echo "  [明文 did]"
cat "%s/Library/Application Support/com.kuaishou.did" 2>/dev/null; echo
""" % (G, G, D, D))
print(so.strip())

print()
print("=" * 78)
print("3. ★ 残留 A1B2C3D4 的文件")
print("=" * 78)
so = sush("""
echo "  [MMKV]"
grep -la A1B2C3D4 %s/Documents/mmkv/* 2>/dev/null | while read f; do echo "    $(basename $f)"; done
echo "  [AppGroup]"
for g in /var/mobile/Containers/Shared/AppGroup/*/; do
  [ -d "$g" ] || continue
  grep -rla A1B2C3D4 "$g" 2>/dev/null | head -5
done
echo "  [容器其他]"
grep -rla A1B2C3D4 %s 2>/dev/null | grep -v mmkv | head -10
""" % (D, D))
print(so.strip() or "  (无残留)")

c.close()
