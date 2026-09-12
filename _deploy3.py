# -*- coding: utf-8 -*-
"""部署 + 记录崩溃日志基线，供用户点击后对比"""
import sys, io, os, glob, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, USER, PWD = "192.168.1.2", "mobile", "qqqqaaaa"
DEB = glob.glob(r"C:\Users\yyds\Desktop\ks-ios-deb\*.deb")[0]
print("包: %s (%d bytes)\n" % (os.path.basename(DEB), os.path.getsize(DEB)))

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username=USER, password=PWD, timeout=20,
          allow_agent=False, look_for_keys=False)

D = "/rootfs/private/var/mobile/Library/Logs/CrashReporter"

def run(cmd, label=None, t=180):
    if label:
        print("=" * 62); print(label); print("=" * 62)
    _, o, e = c.exec_command("echo %s | sudo -S -p '' sh -c '%s'" % (PWD, cmd), timeout=t)
    so = o.read().decode("utf-8", "replace")
    se = e.read().decode("utf-8", "replace")
    if so.strip(): print(so.rstrip()[:1500])
    if se.strip():
        L = [l for l in se.splitlines() if "password for" not in l and l.strip()]
        if L: print("[err] " + "\n".join(L)[:400])
    print()
    return so

# 安装前记录崩溃日志基线
before = run("ls -t %s/KSExtract*.ips 2>/dev/null | head -1" % D, "0. 安装前最新崩溃日志")
base = before.strip().splitlines()[-1].strip() if before.strip() else "无"
print("基线: %s\n" % base)

sftp = c.open_sftp()
sftp.put(DEB, "/var/mobile/ks_new.deb")
sftp.close()

run("killall KSExtract 2>/dev/null; dpkg -r com.kuaishou.ioslogin 2>&1 | grep -v 'missing .Description' | tail -1",
    "1. 卸载旧版")
run("dpkg -i /var/mobile/ks_new.deb 2>&1 | grep -v 'missing .Description' | tail -3",
    "2. 安装新版")
run("uicache -a >/dev/null 2>&1; echo '刷新完成'", "3. 刷新图标")

# 启动测试
run("rm -f /tmp/ks_out.log; "
    "/var/jb/Applications/KSExtract.app/KSExtract > /tmp/ks_out.log 2>&1 & "
    "BP=$!; sleep 6; "
    "if kill -0 $BP 2>/dev/null; then echo '✓ 启动正常，进程存活'; else echo '✗ 启动后已退出'; fi; "
    "kill $BP 2>/dev/null; cat /tmp/ks_out.log | head -20",
    "4. 启动测试", t=120)

# 写入基线到文件，供后续对比
with open(r"C:\Users\yyds\Desktop\ios快手上号器\_baseline.txt", "w") as f:
    f.write(base)

c.close()
print("基线已记录到 _baseline.txt")
print("\n现在请到手机上点「一键上号」和「清空数据」，完成后告诉我，我来检查有没有新崩溃。")
