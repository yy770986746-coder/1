# -*- coding: utf-8 -*-
"""部署 KSDid 插件 + 写入自定义 did 配置"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, USER, PWD = "192.168.1.4", "mobile", "qqqqaaaa"
DEB = r"C:\Users\yyds\Desktop\ks-tweak-deb\com.momo.ksdid_1.0.0_iphoneos-arm64.deb"
DID = "B28005FA-EE19-4A5F-B6D3-2D7024ECBD37"

if not os.path.exists(DEB):
    print("找不到 deb: %s" % DEB); sys.exit(1)
print("deb: %s (%d 字节)" % (os.path.basename(DEB), os.path.getsize(DEB)))
print("目标 did: %s\n" % DID)

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username=USER, password=PWD, timeout=25,
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

# 1. 上传
print("=" * 60); print("1. 上传插件"); print("=" * 60)
sftp = c.open_sftp(); sftp.put(DEB, "/var/mobile/ksdid.deb")
st = sftp.stat("/var/mobile/ksdid.deb"); sftp.close()
print("  已上传 %d 字节" % st.st_size)

# 2. 安装
print(); print("=" * 60); print("2. dpkg 安装"); print("=" * 60)
so, se = sush("/usr/bin/dpkg -i /var/mobile/ksdid.deb 2>&1")
for line in (so + se).splitlines():
    if line.strip() and "password for" not in line:
        print("  " + line)

# 3. 写配置
print(); print("=" * 60); print("3. 写入自定义 did"); print("=" * 60)
so, se = sush("""
echo '%s' > /var/mobile/Documents/ks_did.txt
chmod 644 /var/mobile/Documents/ks_did.txt
echo "  文件内容: $(cat /var/mobile/Documents/ks_did.txt)"

# 同时写 plist 形式（插件优先读这个）
cat > /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>did</key>
    <string>%s</string>
</dict>
</plist>
EOF
chmod 644 /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist
echo "  plist 内容: $(LC_ALL=C grep -A1 'did' /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist | tail -1)"
""" % (DID, DID))
print(so.strip()[:800])

# 4. 重启快手
print(); print("=" * 60); print("4. 重启快手"); print("=" * 60)
so, se = sush("""
PID=$(launchctl list 2>/dev/null | awk '$3 ~ /jiangjia/ {print $1}' | head -1)
[ -n "$PID" ] && kill -9 "$PID" 2>/dev/null && echo "  已杀 PID=$PID"
sleep 2
killall -9 cfprefsd 2>/dev/null
echo "  cfprefsd 已刷新"
""")
print(so.strip())

# 5. 验证插件安装
print(); print("=" * 60); print("5. 验证"); print("=" * 60)
so, se = sh("ls -la /var/jb/Library/MobileSubstrate/DynamicLibraries/ 2>/dev/null | grep -i ksdid || "
            "ls -la /var/jb/usr/lib/TweakInject/ 2>/dev/null | grep -i ksdid || "
            "find /var/jb -name 'KSDid*' 2>/dev/null | head -5")
print("  插件文件:")
print("  " + so.strip())

c.close()
print()
print("=" * 60)
print("安装完成。请打开快手，看「帮助→设备信息」里的 did")
print("=" * 60)
