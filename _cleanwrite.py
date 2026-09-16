# -*- coding: utf-8 -*-
"""快手已死：清缓存 + 改所有位置 + 用插件dump Keychain"""
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
print("0. 确认快手已死")
print("=" * 78)
print("  " + sh("launchctl list 2>/dev/null | grep -i jiangjia || echo 'OK 已停止'").strip())

print()
print("=" * 78)
print("1. ★ 杀 cfprefsd（清偏好缓存）")
print("=" * 78)
so = sush("""
n=0
for p in $(launchctl list 2>/dev/null | awk '$3 ~ /cfprefsd/ {print $1}'); do
  kill -9 "$p" 2>/dev/null && n=$((n+1))
done
sleep 2
echo "  已杀 $n 个 cfprefsd"
""")
print(so.strip())

print()
print("=" * 78)
print("2. ★ 改所有位置（含明文 plist）")
print("=" * 78)
so = sush("""
D="%s"; G="%s"; NEW="%s"; n=0

echo "  [MMKV 全部文件]"
for f in "$D/Documents/mmkv/"*; do
  [ -f "$f" ] || continue
  C=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | grep -av "$NEW" | head -1)
  if [ -n "$C" ]; then LC_ALL=C sed -i "s/$C/$NEW/g" "$f"; n=$((n+1)); echo "    OK $(basename $f)"; fi
done

echo "  [AppGroup]"
for g in /var/mobile/Containers/Shared/AppGroup/*/; do
  [ -d "$g" ] || continue
  for f in "${g}Library/Preferences/group.com.kwai.video.plist" \\
           "${g}Library/Preferences/"*.plist \\
           "${g}UGExtension/ExtensionNetwork/params.plist"; do
    [ -f "$f" ] || continue
    C=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | grep -av "$NEW" | head -1)
    if [ -n "$C" ]; then LC_ALL=C sed -i "s/$C/$NEW/g" "$f"; n=$((n+1)); echo "    OK ${g##*/AppGroup/}::$(basename $f)"; fi
  done
done

echo "  [容器 Library/Preferences]"
for f in "$D/Library/Preferences/"*.plist; do
  [ -f "$f" ] || continue
  C=$(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$f" 2>/dev/null | grep -av "$NEW" | head -1)
  if [ -n "$C" ]; then LC_ALL=C sed -i "s/$C/$NEW/g" "$f"; n=$((n+1)); echo "    OK $(basename $f)"; fi
done

echo "  共改 $n 个文件"
""" % (D, G, NEW))
print(so.strip())

print()
print("=" * 78)
print("3. ★ 再杀 cfprefsd")
print("=" * 78)
print("  " + sush("""
for p in $(launchctl list 2>/dev/null | awk '$3 ~ /cfprefsd/ {print $1}'); do
  kill -9 "$p" 2>/dev/null
done
sleep 2
echo "OK"
""").strip())

print()
print("=" * 78)
print("4. ★ 最终验证")
print("=" * 78)
so = sush("""
echo "  [AppGroup] $(LC_ALL=C grep -aoE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' '%s/Library/Preferences/group.com.kwai.video.plist' 2>/dev/null | tr '\\n' ' ')"
echo "  [MMKV 残留 A1B2C3D4]"
grep -la A1B2C3D4 %s/Documents/mmkv/* 2>/dev/null | while read f; do echo "    $(basename $f)"; done
echo "  [容器 plist 残留]"
grep -la A1B2C3D4 %s/Library/Preferences/*.plist 2>/dev/null | while read f; do echo "    $(basename $f)"; done
""" % (G, D, D))
print(so.strip())
print()
print("  快手进程: " + sh("launchctl list 2>/dev/null | grep -i jiangjia || echo 'OK 未运行'").strip())

c.close()
print()
print("=" * 78)
print("★ 请现在打开快手")
print("=" * 78)
