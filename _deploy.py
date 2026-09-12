# -*- coding: utf-8 -*-
"""部署新 deb 到 iPhone 并验证"""
import sys, io, os, glob, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, USER, PWD = "192.168.1.2", "mobile", "qqqqaaaa"

cands = glob.glob(r"C:\Users\yyds\Desktop\ks-ios-deb\*.deb")
DEB = cands[0]
print("本地包: %s (%d bytes)" % (os.path.basename(DEB), os.path.getsize(DEB)))

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username=USER, password=PWD, timeout=20,
          allow_agent=False, look_for_keys=False)
sftp = c.open_sftp()

def run(cmd, label=None, sudo=True, t=180):
    if label:
        print("=" * 62); print(label); print("=" * 62)
    if sudo:
        cmd = "echo %s | sudo -S -p '' sh -c \"%s\"" % (PWD, cmd.replace('"', '\\"'))
    _, o, e = c.exec_command(cmd, timeout=t)
    so = o.read().decode("utf-8", "replace")
    se = e.read().decode("utf-8", "replace")
    if so.strip(): print(so.rstrip()[:2000])
    if se.strip():
        lines = [l for l in se.splitlines() if "password for" not in l and l.strip()]
        if lines: print("[err] " + "\n".join(lines)[:600])
    print()
    return so

# 1. 上传
remote = "/var/mobile/ks_new.deb"
sftp.put(DEB, remote)
print("上传完成: %s\n" % remote)

# 2. 卸载旧的（清干净）
run("killall KSExtract 2>/dev/null; dpkg -r com.kuaishou.ioslogin 2>&1 | grep -v 'missing .Description' | tail -3",
    "1. 卸载旧版")

# 3. 装新版
run("dpkg -i %s 2>&1 | grep -v 'missing .Description' | tail -6" % remote,
    "2. 安装新版")

# 4. 刷新图标
run("uicache -a 2>&1 | tail -2 || /var/jb/usr/bin/uicache -a 2>&1 | tail -2",
    "3. uicache 刷新")

# 5. 验证
run("ls -la /var/jb/Applications/KSExtract.app/", "4. 安装后文件", sudo=False)
run("dpkg -l com.kuaishou.ioslogin 2>&1 | grep -v 'missing .Description' | tail -2",
    "5. dpkg 状态", sudo=False)
run("ldid -e /var/jb/Applications/KSExtract.app/KSExtract 2>/dev/null | grep -c platform-application",
    "6. entitlements 检查（1=有平台权限）", sudo=False)

sftp.close(); c.close()
print("完成")
