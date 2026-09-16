# -*- coding: utf-8 -*-
"""重启快手测试 + 检查插件加载"""
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

print("=" * 60); print("1. 杀快手"); print("=" * 60)
so, se = sush("""
launchctl list 2>/dev/null | awk '$3 ~ /jiangjia/ {print $1}' | while read pid; do
  kill -9 "$pid" 2>/dev/null; echo "  杀 $pid"
done
sleep 3
launchctl list 2>/dev/null | grep -qi jiangjia && echo "  ✗ 仍在" || echo "  ✓ 已停止"
""")
print(so.strip())

print()
print("=" * 60); print("2. 启动快手并检查插件"); print("=" * 60)
so, se = sush("/usr/bin/uiopen com.jiangjia.gif 2>/dev/null; sleep 8; "
              "launchctl list 2>/dev/null | grep -i jiangjia || echo '  未启动'")
print("  " + so.strip())

print()
print("=" * 60); print("3. 检查进程加载的 dylib（如果能看到）"); print("=" * 60)
so, se = sush("""
PID=$(launchctl list 2>/dev/null | awk '$3 ~ /jiangjia/ {print $1}' | head -1)
echo "  PID=$PID"
if [ -n "$PID" ]; then
  # 尝试从 vmmap/lsof 看（可能不存在）
  command -v vmmap >/dev/null 2>&1 && vmmap "$PID" 2>/dev/null | grep -i ksdid | head -3
  echo "  --"
  # 用 sysctl 看 dyld 镜像不可行，改用 /var/mobile 下的日志
fi
""", 300)
print(so.strip()[:800])

print()
print("=" * 60); print("4. 检查 RootHide 日志 / 系统日志"); print("=" * 60)
so, se = sush("""
# RootHide 的日志
ls -la /var/mobile/Library/RootHide/*.log 2>/dev/null
ls -la /var/mobile/Library/Logs/*.log 2>/dev/null | head -5
# 找 ellekit 日志
find /var/mobile/Library -maxdepth 3 -iname '*ellekit*' -o -maxdepth 3 -iname '*substrate*' 2>/dev/null | head -5
echo "--"
env | grep -i dyld
""", 300)
print(so.strip()[:800])

c.close()
print()
print("=" * 60)
print("请手动打开快手，看「帮助→设备信息」里的 did")
print("=" * 60)
