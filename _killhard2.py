# -*- coding: utf-8 -*-
"""强制杀快手 + 改 + 重启 cfprefsd"""
import sys, io, paramiko

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
print("步骤 1: 强杀快手")
print("=" * 78)
so, _ = sush("""
for p in $(launchctl list 2>/dev/null | grep -i jiangjia | awk '{print $1}'); do
  echo "  kill $p"; kill -9 "$p" 2>/dev/null
done
pkill -9 -f "com.jiangjia.gif" 2>/dev/null
ps aux 2>/dev/null | grep -i jiangjia | grep -v grep | awk '{print $2}' | while read p; do
  echo "  ps kill $p"; kill -9 "$p" 2>/dev/null
done
sleep 3
launchctl list 2>/dev/null | grep -i jiangjia || echo "  OK 已停止"
""")
print(so.strip())

print()
print("=" * 78)
print("步骤 2: 杀 cfprefsd")
print("=" * 78)
so, _ = sush("""
for p in $(launchctl list 2>/dev/null | awk '$3 ~ /cfprefsd/ {print $1}'); do
  kill -9 "$p" 2>/dev/null
done
sleep 2; echo "  OK"
""")
print(so.strip())

print()
print("=" * 78)
print("步骤 3: 改全部")
print("=" * 78)
so, _ = sush("""
D="%s"; G="%s"; NEW="%s"; n=0
for f in "$D/Documents/mmkv/"*; do
  [ -f "$f" ] || continue
  C=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | grep -av "$NEW" | head -1)
  if [ -n "$C" ]; then LC_ALL=C sed -i "s/$C/$NEW/g" "$f"; n=$((n+1)); echo "  OK MMKV $(basename $f)"; fi
done
for f in "$G/Library/Preferences/group.com.kwai.video.plist" "$G/UGExtension/ExtensionNetwork/params.plist"; do
  [ -f "$f" ] || continue
  C=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | grep -av "$NEW" | head -1)
  if [ -n "$C" ]; then LC_ALL=C sed -i "s/$C/$NEW/g" "$f"; n=$((n+1)); echo "  OK $(basename $f)"; fi
done
echo "  共 $n 个"
""" % (D, G, NEW))
print(so.strip())

print()
print("=" * 78)
print("步骤 4: 再杀 cfprefsd")
print("=" * 78)
so, _ = sush("""
for p in $(launchctl list 2>/dev/null | awk '$3 ~ /cfprefsd/ {print $1}'); do
  kill -9 "$p" 2>/dev/null
done
sleep 2; echo "  OK"
""")
print(so.strip())

print()
print("=" * 78)
print("步骤 5: 验证")
print("=" * 78)
so, _ = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  OK 快手未运行'")
print("  进程: " + so.strip())
so, _ = sush("""
echo "  AppGroup: $(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' '%s/Library/Preferences/group.com.kwai.video.plist' 2>/dev/null | head -1)"
echo "  MMKV残留A1B2C3D4: $(grep -la A1B2C3D4 %s/Documents/mmkv/* 2>/dev/null | wc -l) 个"
""" % (G, D))
print(so.strip())

c.close()
