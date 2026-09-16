# -*- coding: utf-8 -*-
"""谨慎测试：装插件 → 启动 → 监控崩溃 → 自动回滚"""
import sys, io, os, glob, tarfile, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
DID = "B28005FA-EE19-4A5F-B6D3-2D7024ECBD37"
DEBS = glob.glob(r"C:\Users\yyds\Desktop\ks-tweak-deb\*.deb")
DEB = DEBS[0] if DEBS else None
if not DEB:
    print("找不到 deb"); sys.exit(1)
print("deb: %s (%d 字节)" % (os.path.basename(DEB), os.path.getsize(DEB)))

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

# 1. 上传 + 安装
print(); print("=" * 60); print("1. 安装新插件"); print("=" * 60)
sftp = c.open_sftp(); sftp.put(DEB, "/var/mobile/ksdid3.deb"); sftp.close()
so, se = sush("""
B=/var/jb/Library/MobileSubstrate/DynamicLibraries
rm -f "$B"/KSDid.* 2>/dev/null
/usr/bin/dpkg -i /var/mobile/ksdid3.deb 2>&1 | tail -3
ls -la "$B" | grep -i ksdid
""")
print(so.strip()[:600])

# 2. 写配置
print(); print("=" * 60); print("2. 写入 did 配置"); print("=" * 60)
so, se = sush("""
cat > /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict><key>did</key><string>DIDPLACE</string></dict>
</plist>
EOF
chmod 644 /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist
grep -A1 did /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist | tail -1
""".replace("DIDPLACE", DID))
print("  " + so.strip())

# 3. 记录崩溃日志基线
print(); print("=" * 60); print("3. 记录崩溃基线"); print("=" * 60)
so, se = sh("ls -t /rootfs/private/var/mobile/Library/Logs/CrashReporter/com_kwai_gif*.ips 2>/dev/null | head -1")
baseline = so.strip()
print("  最新崩溃日志: %s" % (os.path.basename(baseline) if baseline else "(无)"))

# 4. 启动快手（SSH 方式）
print(); print("=" * 60); print("4. 启动快手"); print("=" * 60)
so, se = sush("/usr/bin/uiopen com.jiangjia.gif 2>/dev/null || open com.jiangjia.gif 2>/dev/null || echo 'uiopen失败'")
print("  " + so.strip())

# 5. 监控 20 秒
print(); print("=" * 60); print("5. 监控进程存活（20 秒）"); print("=" * 60)
alive_count = 0
for i in range(10):
    time.sleep(2)
    so, se = sh("launchctl list 2>/dev/null | grep -c jiangjia")
    n = so.strip()
    if n and n != "0":
        alive_count += 1
        print("  [%2ds] ✓ 运行中" % ((i+1)*2))
    else:
        print("  [%2ds] ✗ 不在" % ((i+1)*2))

# 6. 检查新崩溃
print(); print("=" * 60); print("6. 检查新崩溃日志"); print("=" * 60)
so, se = sh("ls -t /rootfs/private/var/mobile/Library/Logs/CrashReporter/com_kwai_gif*.ips 2>/dev/null | head -1")
newest = so.strip()
if newest and newest != baseline:
    print("  ★ 有新崩溃: %s" % os.path.basename(newest))
    so, se = sush("""
F='%s'
LC_ALL=C grep -a -oE '"type":"[^"]*"' "$F" 2>/dev/null | head -2
LC_ALL=C grep -a -oE '"symbol":"[^"]*KSDid[^"]*"' "$F" 2>/dev/null | head -3
""" % newest)
    print("  " + so.strip()[:500])
    print()
    print("  ⚠ 自动禁用插件...")
    so, se = sush("""
B=/var/jb/Library/MobileSubstrate/DynamicLibraries
mv "$B/KSDid.dylib" "$B/KSDid.dylib.disabled" 2>/dev/null
mv "$B/KSDid.plist" "$B/KSDid.plist.disabled" 2>/dev/null
launchctl list 2>/dev/null | awk '$3 ~ /jiangjia/ {print $1}' | while read p; do kill -9 "$p" 2>/dev/null; done
echo "  已禁用"
""")
    print("  " + so.strip())
else:
    print("  ✓ 无新崩溃（存活 %d/10 次检测）" % alive_count)

c.close()
print()
print("=" * 60)
if alive_count >= 8:
    print("✓ 插件工作正常！请打开快手看「帮助→设备信息」里的 did")
    print("  目标: %s" % DID)
else:
    print("⚠ 快手可能有问题，插件已处理")
print("=" * 60)
