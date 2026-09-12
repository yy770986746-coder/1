# -*- coding: utf-8 -*-
"""部署 + 实际启动验证（关键：确认不再 SIGABRT）"""
import sys, io, os, glob, time, paramiko, plistlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, USER, PWD = "192.168.1.2", "mobile", "qqqqaaaa"
DEB = glob.glob(r"C:\Users\yyds\Desktop\ks-ios-deb\*.deb")[0]
print("包: %s (%d bytes)\n" % (os.path.basename(DEB), os.path.getsize(DEB)))

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username=USER, password=PWD, timeout=20,
          allow_agent=False, look_for_keys=False)
sftp = c.open_sftp()

def run(cmd, label=None, sudo=False, t=180):
    if label:
        print("=" * 62); print(label); print("=" * 62)
    if sudo:
        cmd = "echo %s | sudo -S -p '' sh -c %s" % (PWD, repr(cmd).replace("'", '"', 1)[::-1].replace("'", '"', 1)[::-1])
    _, o, e = c.exec_command(cmd, timeout=t)
    so = o.read().decode("utf-8", "replace")
    se = e.read().decode("utf-8", "replace")
    if so.strip(): print(so.rstrip()[:1800])
    if se.strip():
        L = [l for l in se.splitlines() if "password for" not in l and l.strip()]
        if L: print("[err] " + "\n".join(L)[:500])
    print()
    return so

# 上传 + 安装
sftp.put(DEB, "/var/mobile/ks_new.deb")
run("killall KSExtract 2>/dev/null; dpkg -r com.kuaishou.ioslogin 2>&1 | grep -v 'missing .Description' | tail -2",
    "1. 卸载旧版", sudo=True)
run("dpkg -i /var/mobile/ks_new.deb 2>&1 | grep -v 'missing .Description' | tail -4",
    "2. 安装新版", sudo=True)
run("uicache -a >/dev/null 2>&1; echo refreshed", "3. 刷新图标", sudo=True)

# ★ 关键：实际启动，看是否还崩溃
run("echo qqqqaaaa | sudo -S -p '' sh -c '"
    "C=$(ls -t /rootfs/private/var/mobile/Library/Logs/CrashReporter/KSExtract*.ips 2>/dev/null | head -1); "
    "echo \"启动前最新崩溃: ${C:-无}\"; "
    "rm -f /tmp/ks_out.log; "
    "uicache -a >/dev/null 2>&1; "
    "sleep 1; "
    "/var/jb/Applications/KSExtract.app/KSExtract > /tmp/ks_out.log 2>&1 & "
    "BGPID=$!; sleep 6; "
    "echo \"--- 6 秒后是否还活着 ---\"; "
    "if kill -0 $BGPID 2>/dev/null; then echo \"进程存活 (PID=$BGPID) ✓\"; else echo \"进程已退出\"; fi; "
    "echo \"--- 输出 ---\"; cat /tmp/ks_out.log | head -30'",
    "4. 实际启动测试", t=120)

# 检查有没有产生新崩溃日志
run("echo qqqqaaaa | sudo -S -p '' sh -c '"
    "ls -t /rootfs/private/var/mobile/Library/Logs/CrashReporter/KSExtract*.ips 2>/dev/null | head -3'",
    "5. 当前崩溃日志（时间戳应为旧的）", t=90)

sftp.close(); c.close()
print("完成")
