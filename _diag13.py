# -*- coding: utf-8 -*-
"""诊断 v13 插件为什么没加载"""
import sys, io, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
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
print("1. 插件文件")
print("=" * 78)
so, se = sh("ls -la %s/ 2>/dev/null | grep -iE 'ksdid|KSDid'" % LIB)
print("  " + (so.strip() or "(无!)"))

print()
print("=" * 78)
print("2. ★ entitlements 签名检查")
print("=" * 78)
so, se = sush("""
DYLIB="%s/KSDid.dylib"
[ -f "$DYLIB" ] || { echo "  无 dylib"; exit; }
echo "  --- ldid -e (提取 entitlements) ---"
ldid -e "$DYLIB" 2>&1 | head -30
echo ""
echo "  --- 文件类型 ---"
file "$DYLIB" 2>/dev/null
echo ""
echo "  --- 架构 ---"
otool -h "$DYLIB" 2>/dev/null | grep -A1 "Magic" | head -6
""")
print(so.strip())

print()
print("=" * 78)
print("3. 插件 plist")
print("=" * 78)
so, se = sh("cat %s/KSDid.plist 2>/dev/null" % LIB)
print(so)

print()
print("=" * 78)
print("4. ★ 快手进程有没有加载它")
print("=" * 78)
so, se = sh("launchctl list 2>/dev/null | grep -i jiangjia")
pid = so.strip().split()[0] if so.strip() and so.strip()[0].isdigit() else "0"
print("  PID: %s" % pid)
if pid != "0":
    so, se = sush("vmmap %s 2>/dev/null | grep -i ks | head -10 || echo '  (vmmap不可用)'" % pid)
    print(so.strip())
    so, se = sush("grep -a 'KSDid' /dev/null 2>/dev/null; "
                  "cat /var/mobile/Library/Logs/CrashReporter/*.log 2>/dev/null | grep -i ksdid | head -5 || echo '  (无崩溃日志)'")
    print(so.strip())

print()
print("=" * 78)
print("5. 插件配置 + did 文件")
print("=" * 78)
so, se = sh("ls -la '%s/Documents/ks_did.txt' 2>/dev/null; cat '%s/Documents/ks_did.txt' 2>/dev/null; echo" % (D, D))
print("  " + so.strip())

c.close()
