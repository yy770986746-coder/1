# -*- coding: utf-8 -*-
"""给 KSDid 加 RootHide 补丁（模仿 SysCore）"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
B = "/var/jb/Library/MobileSubstrate/DynamicLibraries"

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

print("=" * 60); print("1. 检查 RootHide 补丁机制"); print("=" * 60)
so, se = sh("ls -la %s/*.roothidepatch 2>/dev/null" % B)
print("  已有的 roothidepatch:")
print("  " + (so.strip() or "(无)"))

so, se = sh("ls -la /usr/lib/DynamicPatches/ 2>/dev/null; "
            "ls -la /var/jb/usr/lib/DynamicPatches/ 2>/dev/null")
print("  DynamicPatches 目录:")
print("  " + (so.strip() or "(无)"))

print()
print("=" * 60); print("2. 给 KSDid 加 roothidepatch 符号链接"); print("=" * 60)
so, se = sush("""
B=%s
cd "$B"
ln -sf /usr/lib/DynamicPatches/AutoPatches.dylib KSDid.dylib.roothidepatch 2>&1
ls -la KSDid.dylib.roothidepatch 2>&1
echo "  ---"
ls -la "$B" | grep -i ksdid
""" % B)
print(so.strip())

print()
print("=" * 60); print("3. 检查 RootHide 的插件白名单机制"); print("=" * 60)
so, se = sh("find /var/jb -maxdepth 4 -iname '*roothide*' -type f 2>/dev/null | head -10")
print("  RootHide 文件:")
print("  " + (so.strip() or "(无)"))

so, se = sh("ls -la /var/jb/usr/lib/roothide* /var/jb/usr/lib/*roothide* 2>/dev/null | head -10")
print("  RootHide 库:")
print("  " + (so.strip() or "(无)"))

so, se = sh("ls -la /var/mobile/Library/RootHide/ 2>/dev/null")
print("  RootHide 配置目录:")
print("  " + so.strip())

c.close()
