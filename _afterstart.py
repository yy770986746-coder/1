# -*- coding: utf-8 -*-
"""快手已启动：看它把哪个文件写回去了"""
import sys, io, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
G = "/var/mobile/Containers/Shared/AppGroup/2B64FAB8-2826-4831-A314-5C6DCBEC275F"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=600):
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
print("1. ★ 启动后被写回 A1B2C3D4 的文件")
print("=" * 78)
so = sush("""
D="%s"; G="%s"
echo "  [MMKV]"
grep -la A1B2C3D4 "$D/Documents/mmkv/"* 2>/dev/null | while read f; do echo "    $(basename $f)"; done
echo "  [容器 plist]"
grep -la A1B2C3D4 "$D/Library/Preferences/"*.plist 2>/dev/null | while read f; do echo "    $(basename $f)"; done
echo "  [AppGroup]"
grep -rla A1B2C3D4 /var/mobile/Containers/Shared/AppGroup/ 2>/dev/null | head -8
""" % (D, G))
print(so.strip() or "  (无)")

print()
print("=" * 78)
print("2. ★ 关键文件的当前值")
print("=" * 78)
so = sush("""
D="%s"
for f in kKSUMMKVStoreKey kKSUHeartBeatReportKey com.kuaishou.ConfigCenter.KSStartupService com.kuaishou.KSNewDiskCache.startup; do
  V=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$D/Documents/mmkv/$f" 2>/dev/null | sort -u | tr '\\n' ' ')
  echo "    MMKV/$f: $V"
done
for f in com.gif.kscommon.idfa.plist com.jiangjia.gif.plist; do
  V=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$D/Library/Preferences/$f" 2>/dev/null | tr '\\n' ' ')
  echo "    Pref/$f: $V"
done
""" % (D))
print(so.strip())

print()
print("=" * 78)
print("3. ★ 插件日志（v17 网络追踪）")
print("=" * 78)
so = sh("cat '%s/Documents/ksdid_log.txt' 2>/dev/null | tail -30" % D)
print(so.strip()[:2500])

print()
print("=" * 78)
print("4. ★ 网络缓存最新 did")
print("=" * 78)
so = sush("""
CK="%s/Library/Caches/com.jiangjia.gif/KSURLCache/Cache.db-wal"
LC_ALL=C grep -aoE 'did=[0-9A-Fa-f-]{36}' "$CK" 2>/dev/null | tail -12
echo "  ---"
LC_ALL=C grep -aoE 'did=[0-9A-Fa-f-]{36}' "$CK" 2>/dev/null | sort | uniq -c | sort -rn | head -3
""" % D)
print(so.strip())

c.close()
