# -*- coding: utf-8 -*-
"""部署 deb 到 iPhone：192.168.1.2，mobile/qqqqaaaa"""
import sys, io, os, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

HOST, USER, PWD = "192.168.1.2", "mobile", "qqqqaaaa"
DEB = r"C:\Users\yyds\Desktop\ks-ios-deb\ks_KSExtract_1.0.0_iphoneos-arm64e_FULL.deb"
REMOTE = "/var/mobile/ks_new.deb"

if not os.path.exists(DEB):
    print("✗ 找不到 deb: %s" % DEB); sys.exit(1)
print("deb: %s (%d 字节)\n" % (os.path.basename(DEB), os.path.getsize(DEB)))

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username=USER, password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=300):
    _, o, e = c.exec_command(cmd, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

def sudosh(script, t=300):
    """把脚本文本传给 sudo sh 执行，密码走 stdin"""
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command(
        "echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

print("=" * 62); print("1. 上传 deb"); print("=" * 62)
sftp = c.open_sftp(); sftp.put(DEB, REMOTE)
st = sftp.stat(REMOTE); sftp.close()
print("  已上传 %d 字节" % st.st_size)

print(); print("=" * 62); print("2. dpkg 安装"); print("=" * 62)
so, se = sudosh("/usr/bin/dpkg -i %s 2>&1" % REMOTE)
for line in (so + se).splitlines():
    if line.strip() and "password for" not in line:
        print("  " + line)

print(); print("=" * 62); print("3. 刷新图标缓存"); print("=" * 62)
so, se = sudosh("killall -9 cfprefsd 2>/dev/null; "
                "uicache -a 2>/dev/null; "
                "echo 刷新完成")
print("  " + (so + se).strip()[:200])

print(); print("=" * 62); print("4. 校验安装"); print("=" * 62)
so, se = sh("ls -d /var/jb/Applications/KSExtract.app 2>/dev/null "
            "|| ls -d /Applications/KSExtract.app 2>/dev/null "
            "|| echo '✗ 未找到'")
print("  " + so.strip())

c.close()
print(); print("=" * 62)
print("安装完成。到手机上打开「快手上号器」点一键上号。")
print("=" * 62)
