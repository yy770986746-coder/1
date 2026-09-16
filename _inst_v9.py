# -*- coding: utf-8 -*-
"""装 v9 正式版 + 写入目标 did"""
import sys, io, os, glob, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
DEB = glob.glob(r"C:\Users\yyds\Desktop\ks-tweak-deb\*.deb")[0]
# 目标 did（用户指定）
DID = "B28005FA-EE19-4A5F-B6D3-2D7024ECBD37"

# 快手容器
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"

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

print("目标 did: %s\n" % DID)

print("=" * 70)
print("1. 装 v9")
print("=" * 70)
sftp = c.open_sftp()
sftp.put(DEB, "/var/mobile/ksdid_v9.deb")
sftp.close()

so, se = sush("""
cd /var/tmp
rm -rf _v9 2>/dev/null
mkdir -p _v9
cd _v9
/var/jb/usr/bin/dpkg-deb -x /var/mobile/ksdid_v9.deb ./x 2>&1 | head -2
SRC=./x/var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.dylib
if [ -f "$SRC" ]; then
  echo "  源 MD5: $(md5sum "$SRC" | cut -d' ' -f1)"
  for DST in /var/jb/usr/lib/TweakInject /var/jb/Library/MobileSubstrate/DynamicLibraries; do
    mkdir -p "$DST"
    cp -f "$SRC" "$DST/KSDid.dylib"
    chown root:wheel "$DST/KSDid.dylib"
    chmod 755 "$DST/KSDid.dylib"
  done
  echo "  已安装"
fi
""", 300)
print(so.strip()[:600])

print()
print("=" * 70)
print("2. 写 did 配置到沙盒")
print("=" * 70)
so, se = sush("""
D="%s"
echo "%s" > "$D/Documents/ks_did.txt"
chown mobile:mobile "$D/Documents/ks_did.txt"
chmod 644 "$D/Documents/ks_did.txt"
echo "  沙盒配置: $(cat "$D/Documents/ks_did.txt")"

# 全局也写一份
echo "%s" > /var/mobile/Documents/ks_did.txt
chmod 644 /var/mobile/Documents/ks_did.txt
echo "  全局配置: $(cat /var/mobile/Documents/ks_did.txt)"

# 清日志
rm -f "$D/Documents/ksdid_log.txt" 2>/dev/null
echo "  日志已清"
""" % (D, DID, DID))
print(so.strip())

print()
print("=" * 70)
print("3. 杀快手")
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
print("请划掉快手后台 → 重新打开 → 等 5 秒")
print("=" * 70)
