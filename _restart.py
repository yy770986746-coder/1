# -*- coding: utf-8 -*-
"""重启快手加载插件 + 验证"""
import sys, io, os, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
DID = "B28005FA-EE19-4A5F-B6D3-2D7024ECBD37"

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

print("=" * 60); print("1. 杀掉快手（释放旧进程）"); print("=" * 60)
so, se = sush("""
launchctl list 2>/dev/null | awk '$3 ~ /jiangjia/ {print $1}' | while read pid; do
  echo "  杀 PID=$pid"
  kill -9 "$pid" 2>/dev/null
done
sleep 3
launchctl list 2>/dev/null | grep -qi jiangjia && echo "  ✗ 仍在" || echo "  ✓ 已停止"
""")
print(so.strip())

print()
print("=" * 60); print("2. 验证插件配置"); print("=" * 60)
so, se = sh("ls -la /var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.dylib")
print("  " + so.strip())
so, se = sh("cat /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist | grep -A1 did | tail -1")
print("  配置 did: " + so.strip())

print()
print("=" * 60); print("3. 启动快手（触发插件注入）"); print("=" * 60)
so, se = sush("/usr/bin/uiopen com.jiangjia.gif 2>/dev/null || open com.jiangjia.gif 2>/dev/null || echo '需手动启动'")
print("  " + so.strip())
time.sleep(12)

print()
print("=" * 60); print("4. 快手进程 & 插件日志"); print("=" * 60)
so, se = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  未运行'")
print("  " + so.strip())
# 看插件是否被加载（日志里应该有 [KSDid]）
so, se = sush("""
echo "  搜系统日志里的 KSDid:"
log show --last 2m 2>/dev/null | grep -i ksdid | tail -5 || \
  grep -r "KSDid" /var/mobile/Library/Logs/ 2>/dev/null | tail -3 || \
  echo "  （无法读取系统日志）"
""", 300)
print(so.strip()[:800])

c.close()
print()
print("=" * 60)
print("请手动打开快手，看「帮助→设备信息」里的 did")
print("目标: %s" % DID)
print("=" * 60)
