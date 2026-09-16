# -*- coding: utf-8 -*-
"""检查 RootHide 的真实插件目录"""
import sys, io, os, paramiko

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

print("=" * 60); print("1. pkgmirror 目录结构"); print("=" * 60)
so, se = sh("find /var/mobile/Library/pkgmirror -maxdepth 5 -type d 2>/dev/null | head -20")
print(so.strip())

print()
print("=" * 60); print("2. pkgmirror 里的插件"); print("=" * 60)
so, se = sh("ls -la /var/mobile/Library/pkgmirror/Library/MobileSubstrate/DynamicLibraries/ 2>/dev/null")
print(so.strip()[:1500])

print()
print("=" * 60); print("3. 所有可能的插件目录"); print("=" * 60)
for d in ["/var/jb/Library/MobileSubstrate/DynamicLibraries",
          "/var/mobile/Library/pkgmirror/Library/MobileSubstrate/DynamicLibraries",
          "/var/jb/usr/lib/TweakInject",
          "/var/jb/Library/TweakInject"]:
    so, se = sh("ls '%s' 2>/dev/null | wc -l" % d)
    n = so.strip()
    print("  %-70s %s 个文件" % (d, n if n else "不存在"))

print()
print("=" * 60); print("4. llekit 的配置（找插件扫描路径）"); print("=" * 60)
so, se = sush("""
LC_ALL=C strings /var/jb/usr/lib/libellekit.dylib 2>/dev/null | \
  grep -aE 'DynamicLibraries|TweakInject|pkgmirror|\\.jbroot' | head -10
""", 300)
print(so.strip())

print()
print("=" * 60); print("5. RootHide 的路径映射"); print("=" * 60)
so, se = sh("ls -la /var/jb/.jbroot 2>/dev/null; "
            "cat /var/jb/.jbroot 2>/dev/null | head -3; "
            "ls -la /var/mobile/Library/pkgmirror/ 2>/dev/null")
print(so.strip())

c.close()
