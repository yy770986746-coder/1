# -*- coding: utf-8 -*-
"""紧急：禁用插件让快手恢复 + 分析崩溃"""
import sys, io, os, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"

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

print("=" * 60); print("1. 立即禁用插件"); print("=" * 60)
so, se = sush("""
B=/var/jb/Library/MobileSubstrate/DynamicLibraries
# 移除插件文件（改名保留，便于恢复）
mv "$B/KSDid.dylib" "$B/KSDid.dylib.disabled" 2>/dev/null && echo "  ✓ dylib 已禁用"
mv "$B/KSDid.plist" "$B/KSDid.plist.disabled" 2>/dev/null && echo "  ✓ plist 已禁用"
ls -la "$B" | grep -i ksdid
""")
print(so.strip())

print()
print("=" * 60); print("2. 查看崩溃日志"); print("=" * 60)
so, se = sush("""
D=/rootfs/private/var/mobile/Library/Logs/CrashReporter
ls -t "$D"/com_kwai_gif*.ips 2>/dev/null | head -3
""")
print("  最新崩溃日志:")
print("  " + so.strip())

so, se = sush("""
D=/rootfs/private/var/mobile/Library/Logs/CrashReporter
F=$(ls -t "$D"/com_kwai_gif*.ips 2>/dev/null | head -1)
[ -n "$F" ] && {
  echo "=== 文件: $(basename "$F") ==="
  LC_ALL=C grep -a -oE '"exception"[^}]*}' "$F" 2>/dev/null | head -2
  echo "--- 调用栈（找 KSDid）---"
  LC_ALL=C grep -a -oE '"symbol":"[^"]*KSDid[^"]*"' "$F" 2>/dev/null | head -5
  echo "--- 前 20 个符号 ---"
  LC_ALL=C grep -a -oE '"symbol":"[^"]{3,60}"' "$F" 2>/dev/null | head -20
}
""", 300)
print(so.strip()[:2000])

print()
print("=" * 60); print("3. 恢复快手可用"); print("=" * 60)
so, se = sush("""
launchctl list 2>/dev/null | awk '$3 ~ /jiangjia/ {print $1}' | while read pid; do
  kill -9 "$pid" 2>/dev/null
done
sleep 2
echo "  已杀快手（插件已禁用，下次启动应该正常）"
""")
print(so.strip())

c.close()
print()
print("=" * 60)
print("插件已禁用。请打开快手确认能正常进入。")
print("=" * 60)
