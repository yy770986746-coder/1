# -*- coding: utf-8 -*-
"""装 v11（自动写入版）"""
import sys, io, os, glob, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
DEB = glob.glob(r"C:\Users\yyds\Desktop\ks-tweak-deb\*.deb")[0]
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
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

print("=" * 74)
print("1. 安装 v11")
print("=" * 74)
sftp = c.open_sftp()
sftp.put(DEB, "/var/mobile/ksdid_v11.deb")
sftp.close()

so, se = sush("""
cd /var/tmp
rm -rf _v11 2>/dev/null
mkdir -p _v11
cd _v11
/var/jb/usr/bin/dpkg-deb -x /var/mobile/ksdid_v11.deb ./x 2>&1 | head -2
SRC=./x/var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.dylib
if [ -f "$SRC" ]; then
  echo "  MD5: $(md5sum "$SRC" | cut -d' ' -f1)"
  for DST in /var/jb/usr/lib/TweakInject /var/jb/Library/MobileSubstrate/DynamicLibraries; do
    mkdir -p "$DST"
    cp -f "$SRC" "$DST/KSDid.dylib"
    chown root:wheel "$DST/KSDid.dylib"
    chmod 755 "$DST/KSDid.dylib"
  done
  echo "  ✓ 已安装到两个目录"
fi
""", 300)
print(so.strip()[:600])

print()
print("=" * 74)
print("2. 写配置")
print("=" * 74)
so, se = sush("""
D="%s"
echo "%s" > "$D/Documents/ks_did.txt"
chown mobile:mobile "$D/Documents/ks_did.txt"
chmod 644 "$D/Documents/ks_did.txt"
rm -f "$D/Documents/ksdid_log.txt" 2>/dev/null
echo "  配置: $(cat "$D/Documents/ks_did.txt")"
echo "  日志已清"
""" % (D, DID))
print(so.strip())

print()
print("=" * 74)
print("3. 当前快手的 did 值（基线）")
print("=" * 74)
so, se = sh("echo '  AppGroup:'; LC_ALL=C grep -aoE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' "
            "'/var/mobile/Containers/Shared/AppGroup/E64F4F22-D11C-4369-9DBB-B4876F8D9867/Library/Preferences/group.com.kwai.video.plist' 2>/dev/null | head -1")
print(so.strip())
so, se = sh("echo '  MMKV:'; LC_ALL=C grep -aoE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' "
            "'%s/Documents/mmkv/kKSUMMKVStoreKey' 2>/dev/null | sort | uniq -c | head -2" % D)
print(so.strip())

print()
print("=" * 74)
print("4. 快手进程状态")
print("=" * 74)
so, se = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  未运行 ✓'")
print("  " + so.strip())

c.close()
print()
print("=" * 74)
print("请打开快手（不用杀进程）→ 等 10 秒 → 看「设备信息」里的 did")
print("=" * 74)
