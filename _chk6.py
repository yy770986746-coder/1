# -*- coding: utf-8 -*-
"""检查注入引擎 + 验证插件是否生效"""
import sys, io, os, paramiko

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

print("=" * 60); print("1. 注入引擎检查"); print("=" * 60)
so, se = sh("dpkg -l 2>/dev/null | grep -iE 'mobilesubstrate|ellekit|substrate' | head -5")
print("  已装注入引擎:")
print("  " + (so.strip() or "(无)"))

so, se = sh("ls -la /var/jb/usr/lib/libsubstrate* /var/jb/usr/lib/libellekit* 2>/dev/null | head -5")
print("  substrate/ellekit 库:")
print("  " + (so.strip() or "(无)"))

so, se = sh("ls /var/jb/Library/MobileSubstrate/DynamicLibraries/ 2>/dev/null | head -20")
print("  插件目录内容:")
print("  " + so.strip())

print()
print("=" * 60); print("2. 修复 dpkg 依赖状态"); print("=" * 60)
so, se = sush("""
# 看 ellekit 是否存在
if [ -d /var/jb/usr/lib/ellekit ] || [ -f /var/jb/usr/lib/libellekit.dylib ]; then
  echo "  ElleKit 存在，修依赖"
fi
# 用 dpkg --configure 或直接标记
/usr/bin/dpkg --force-architecture --force-depends --configure com.momo.ksdid:iphoneos-arm64 2>&1 | tail -5
""", 300)
print(so.strip()[:800])

print()
print("=" * 60); print("3. 确认配置文件"); print("=" * 60)
so, se = sh("cat /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist 2>/dev/null | head -10")
print("  plist:")
print("  " + so.strip())
so, se = sh("cat /var/mobile/Documents/ks_did.txt 2>/dev/null")
print("  txt: '%s'" % so.strip())

print()
print("=" * 60); print("4. 插件文件确认"); print("=" * 60)
so, se = sh("ls -la /var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.*")
print("  " + so.strip())
so, se = sh("cat /var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.plist")
print("  配置:")
print("  " + so.strip())

c.close()
