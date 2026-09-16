# -*- coding: utf-8 -*-
"""检查+修复 dylib 签名"""
import sys, io, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
LIB = "/var/jb/Library/MobileSubstrate/DynamicLibraries"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=300):
    _, o, e = c.exec_command(cmd, timeout=t)
    return (o.read().decode("utf-8", "replace"), e.read().decode("utf-8", "replace"))

def sush(script, t=300):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return (o.read().decode("utf-8", "replace"), e.read().decode("utf-8", "replace"))

print("=" * 78)
print("1. 找 ldid")
print("=" * 78)
so, se = sh("ls -la /var/jb/usr/bin/ldid /usr/bin/ldid 2>/dev/null; which ldid 2>/dev/null || echo '  PATH无ldid'")
print("  " + so.strip())

print()
print("=" * 78)
print("2. ★ dylib 当前 entitlements")
print("=" * 78)
so, se = sush("LDID=$(ls /var/jb/usr/bin/ldid 2>/dev/null || ls /usr/bin/ldid 2>/dev/null || echo ldid); "
              "echo \"  ldid=$LDID\"; "
              "$LDID -e %s/KSDid.dylib 2>&1 | head -40" % LIB)
print(so.strip())

print()
print("=" * 78)
print("3. ★ 检查 dylib 能否被 dlopen（依赖是否满足）")
print("=" * 78)
so, se = sush("otool -L %s/KSDid.dylib 2>/dev/null | head -20" % LIB)
print(so.strip())

print()
print("=" * 78)
print("4. ★ 两个目录的文件对比")
print("=" * 78)
so, se = sh("for p in /var/jb/Library/MobileSubstrate/DynamicLibraries "
            "/var/jb/usr/lib/TweakInject "
            "/var/mobile/Library/Application\\ Support/ ; do "
            "echo \"  [$p]\"; ls -la \"$p\" 2>/dev/null | grep -iE 'ksdid|KSDid'; done")
print(so.strip())

so, se = sh("ls -la /var/jb/usr/lib/TweakInject/ 2>/dev/null | head -5; "
            "readlink /var/jb/Library/MobileSubstrate/DynamicLibraries 2>/dev/null")
print("  TweakInject: " + so.strip())

print()
print("=" * 78)
print("5. 用 log 命令看 v13 是否被拒")
print("=" * 78)
so, se = sh("ls -la /var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D/Documents/ 2>/dev/null | head -20")
print("  Documents:")
print(so)

c.close()
