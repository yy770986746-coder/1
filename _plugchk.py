# -*- coding: utf-8 -*-
"""验证插件是否被加载"""
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

print("=" * 60); print("1. ElleKit 配置"); print("=" * 60)
so, se = sh("ls -la /var/jb/usr/lib/ellekit/ 2>/dev/null | head -10")
print("  " + so.strip())

print()
print("=" * 60); print("2. 对比其他插件（能工作的）"); print("=" * 60)
so, se = sh("ls -la /var/jb/Library/MobileSubstrate/DynamicLibraries/")
print(so.strip()[:1500])

print()
print("=" * 60); print("3. 检查 KSDid.dylib 的架构和签名"); print("=" * 60)
so, se = sh("file /var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.dylib 2>/dev/null || echo '无 file 命令'")
print("  " + so.strip())
so, se = sush("ldid -e /var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.dylib 2>&1 | head -10")
print("  签名:")
print("  " + so.strip()[:600])

print()
print("=" * 60); print("4. 对比 amg.dylib（能工作的插件的签名）"); print("=" * 60)
so, se = sush("ldid -e /var/jb/Library/MobileSubstrate/DynamicLibraries/amg.dylib 2>&1 | head -10")
print(so.strip()[:600])

print()
print("=" * 60); print("5. ElleKit 的排除列表（RootHide 可能屏蔽插件）"); print("=" * 60)
so, se = sh("ls -la /var/mobile/Library/RootHide/ 2>/dev/null")
print(so.strip())
so, se = sush("cat /var/mobile/Library/RootHide/RootHideConfig.plist 2>/dev/null")
print("  RootHideConfig:")
print("  " + so.strip()[:600])

c.close()
