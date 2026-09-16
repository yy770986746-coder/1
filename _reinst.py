# -*- coding: utf-8 -*-
"""清理旧插件 + 正常安装新版本"""
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

print("=" * 60); print("1. 检查新 deb 架构"); print("=" * 60)
import base64, tarfile
sftp = c.open_sftp(); sftp.put(DEB, "/var/mobile/ksdid.deb"); sftp.close()
data = open(DEB, "rb").read()
pos = 8
while pos < len(data):
    hdr = data[pos:pos+60]
    if len(hdr) < 60: break
    nm = hdr[:16].decode("latin-1").strip().rstrip("/")
    sz = int(hdr[48:58].decode("latin-1").strip())
    body = data[pos+60:pos+60+sz]
    if "control" in nm:
        tf = tarfile.open(fileobj=io.BytesIO(body))
        for m in tf.getmembers():
            if m.name.endswith("control"):
                for line in tf.extractfile(m).read().decode("utf-8", "replace").splitlines():
                    if line.startswith(("Architecture", "Package", "Version")):
                        print("  " + line)
    pos = pos + 60 + sz + (sz % 2)

print()
print("=" * 60); print("2. 卸载旧插件"); print("=" * 60)
so, se = sush("""
/usr/bin/dpkg --purge --force-depends com.momo.ksdid 2>&1 | tail -3
rm -f /var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.* 2>/dev/null
rm -rf /var/mobile/Library/pkgmirror/DEBIAN.com.momo.ksdid 2>/dev/null
rm -f /var/mobile/ksdid.deb
echo "  已清理"
""")
print(so.strip()[:600])

print()
print("=" * 60); print("3. 正常安装新版本"); print("=" * 60)
so, se = sush("/usr/bin/dpkg -i /var/mobile/ksdid.deb 2>&1")
for line in (so + se).splitlines():
    if line.strip() and "password for" not in line:
        print("  " + line)

print()
print("=" * 60); print("4. 验证安装位置"); print("=" * 60)
so, se = sh("ls -la /var/jb/Library/MobileSubstrate/DynamicLibraries/ | grep -i ksdid")
print("  jb 目录:")
print("  " + (so.strip() or "(无)"))
so, se = sh("ls -la /var/mobile/Library/pkgmirror/Library/MobileSubstrate/DynamicLibraries/ 2>/dev/null")
print("  pkgmirror 目录:")
print("  " + so.strip())

c.close()
