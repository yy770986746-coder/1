# -*- coding: utf-8 -*-
"""装 v4（全量UUID扫描）并测试"""
import sys, io, os, glob, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
DEB = glob.glob(r"C:\Users\yyds\Desktop\ks-tweak-deb\*.deb")[0]
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
LOG = D + "/Documents/ksdid_log.txt"
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

print("=" * 70)
print("1. 装 v4")
print("=" * 70)
sftp = c.open_sftp(); sftp.put(DEB, "/var/mobile/ksdid.deb"); sftp.close()
so, se = sush("/var/jb/usr/bin/dpkg --force-depends -i /var/mobile/ksdid.deb 2>&1 | tail -2")
print("  " + so.strip()[:300])

so, se = sush("""
TI=/var/jb/usr/lib/TweakInject
cat > "$TI/KSDid.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Filter</key>
	<dict>
		<key>Bundles</key>
		<array><string>com.jiangjia.gif</string></array>
	</dict>
</dict>
</plist>
EOF
chown root:wheel "$TI/KSDid.dylib" "$TI/KSDid.plist"
chmod 755 "$TI/KSDid.dylib"; chmod 644 "$TI/KSDid.plist"
rm -f "%s" 2>/dev/null
echo "%s" > "%s/Documents/ks_did.txt"
echo "  就绪"
""" % (LOG, DID, D))
print("  " + so.strip()[:400])

print()
print("=" * 70)
print("2. 杀快手")
print("=" * 70)
so, se = sush("""
launchctl list 2>/dev/null | awk '$3 ~ /jiangjia/ {print $1}' | while read p; do
  kill -9 "$p" 2>/dev/null; echo "  杀 $p"
done
sleep 3
launchctl list 2>/dev/null | grep -qi jiangjia && echo "  仍有" || echo "  已停止"
""")
print(so.strip())

c.close()
print()
print("=" * 70)
print("请打开快手并刷新（v4 会全量扫描 Keychain 里的 UUID）")
print("=" * 70)
