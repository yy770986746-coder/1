# -*- coding: utf-8 -*-
"""绕过架构检查安装插件"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
DEB = r"C:\Users\yyds\Desktop\ks-tweak-deb\com.momo.ksdid_1.0.0_iphoneos-arm64.deb"
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

sftp = c.open_sftp(); sftp.put(DEB, "/var/mobile/ksdid.deb"); sftp.close()
print("已上传 deb\n")

print("=" * 60)
print("方案 A: dpkg --force-architecture")
print("=" * 60)
so, se = sush("/usr/bin/dpkg --force-architecture -i /var/mobile/ksdid.deb 2>&1")
for line in (so + se).splitlines():
    if line.strip() and "password for" not in line:
        print("  " + line)

print()
print("=" * 60)
print("方案 B: 直接解包复制（绕过 dpkg）")
print("=" * 60)
so, se = sush("""
cd /tmp 2>/dev/null || cd /var/tmp
rm -rf /var/tmp/_kd 2>/dev/null
mkdir -p /var/tmp/_kd
# 用 ar + tar 手工解包
cd /var/tmp/_kd
ar x /var/mobile/ksdid.deb 2>/dev/null || {
  echo "  无 ar，尝试 python 解包"
}
ls -la
if [ -f data.tar.xz ]; then
  tar -xJf data.tar.xz 2>&1 | head -3
  echo "  解包完成"
  ls -laR var/jb/Library/MobileSubstrate/ 2>/dev/null | head -10
fi
""", 300)
print(so.strip()[:1500])

print()
print("=" * 60)
print("检查最终安装位置")
print("=" * 60)
so, se = sh("ls -la /var/jb/Library/MobileSubstrate/DynamicLibraries/ 2>/dev/null | grep -i ksdid; "
            "ls -la /var/jb/usr/lib/TweakInject/ 2>/dev/null | grep -i ksdid")
print("  " + (so.strip() or "(未找到)"))

c.close()
