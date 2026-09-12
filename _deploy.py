# -*- coding: utf-8 -*-
"""把新 deb 推到 iPhone 并安装，然后验证检测是否正常"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, USER, PWD = "192.168.1.2", "mobile", "qqqqaaaa"
DEB = r"C:\Users\yyds\Desktop\ks-ios-deb\ks_KSExtract_1.0.0_iphoneos-arm64_FULL.deb"

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username=USER, password=PWD, timeout=20,
          allow_agent=False, look_for_keys=False)
sftp = c.open_sftp()

def run(cmd, label=None, sudo=False, t=120):
    if label:
        print("=" * 62); print(label); print("=" * 62)
    if sudo:
        cmd = "echo %s | sudo -S -p '' %s" % (PWD, cmd)
    _, o, e = c.exec_command(cmd, timeout=t)
    so = o.read().decode("utf-8", "replace")
    se = e.read().decode("utf-8", "replace")
    if so.strip(): print(so.rstrip())
    if se.strip() and "password for" not in se: print("[err] " + se.rstrip()[:600])
    print()
    return so

# 1. 上传
remote = "/var/mobile/ks_new.deb"
print("上传 deb ...")
sftp.put(DEB, remote)
print("  完成: %s (%d bytes)" % (remote, os.path.getsize(DEB)))
print()

# 2. 先卸载旧版（确保干净）
run("killall KSExtract 2>/dev/null; dpkg -r com.kuaishou.ioslogin 2>&1 | tail -3",
    "1. 卸载旧版", sudo=True)

# 3. 安装新版
run("dpkg -i %s 2>&1 | tail -6" % remote, "2. 安装新版", sudo=True)

# 4. uicache 刷新图标
run("uicache -a 2>&1 | tail -3 || /var/jb/usr/bin/uicache -a 2>&1 | tail -3",
    "3. 刷新图标缓存", sudo=True)

# 5. 验证安装结果
run("ls -la /var/jb/Applications/KSExtract.app/", "4. 安装后的文件")
run("dpkg -l com.kuaishou.ioslogin 2>&1 | tail -3", "5. dpkg 状态")

sftp.close(); c.close()
print("完成")
