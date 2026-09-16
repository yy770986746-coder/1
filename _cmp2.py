# -*- coding: utf-8 -*-
"""对比插件 plist，找出为什么 KSDid 不加载"""
import sys, io, os, plistlib, base64, paramiko

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

B = "/var/jb/Library/MobileSubstrate/DynamicLibraries"

print("=" * 60); print("各插件的 plist 内容"); print("=" * 60)
for name in ["KSDid", "SysCore", "amg", "YYTweak"]:
    so, se = sush("base64 '%s/%s.plist' 2>/dev/null" % (B, name), 200)
    b64 = "".join(so.split())
    print("\n--- %s.plist ---" % name)
    if not b64:
        print("  (读取失败)")
        continue
    data = base64.b64decode(b64)
    try:
        d = plistlib.loads(data)
        print("  %s" % d)
    except Exception:
        print("  原始: %s" % data[:200])

print()
print("=" * 60); print("RootHide 的插件屏蔽配置"); print("=" * 60)
so, se = sh("find /var/jb /var/mobile -maxdepth 4 -name '*.plist' 2>/dev/null | "
            "xargs grep -l 'DynamicLibraries\\|Filter' 2>/dev/null | head -10")
print("  含 Filter 的配置:")
print("  " + (so.strip() or "(无)"))

so, se = sh("ls -la /var/jb/usr/lib/DynamicPatches/ 2>/dev/null")
print("  DynamicPatches:")
print("  " + (so.strip() or "(无)"))

print()
print("=" * 60); print("ElleKit 是否启用 rootless 模式"); print("=" * 60)
so, se = sh("ls -la /var/jb/usr/lib/ellekit/libinjector.dylib; "
            "cat /var/jb/usr/lib/ellekit/*.plist 2>/dev/null | head -20")
print("  " + so.strip()[:600])

so, se = sh("find /var/jb -maxdepth 3 -name '*ellekit*' -o -maxdepth 3 -name '*substrate*' 2>/dev/null | head -10")
print("  ellekit 相关文件:")
print("  " + so.strip())

c.close()
