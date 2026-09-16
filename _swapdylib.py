# -*- coding: utf-8 -*-
"""彻底替换 dylib 为 v7"""
import sys, io, os, glob, hashlib, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
DEB = glob.glob(r"C:\Users\yyds\Desktop\ks-tweak-deb\*.deb")[0]

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

print("本地 deb MD5: %s" % hashlib.md5(open(DEB, "rb").read()).hexdigest())
print("  大小: %d" % os.path.getsize(DEB))

print()
print("=" * 70)
print("1. 找出所有 KSDid.dylib 位置")
print("=" * 70)
so, se = sh("find /var/jb -name 'KSDid*' 2>/dev/null")
print("  " + so.strip().replace("\n", "\n  "))

print()
print("=" * 70)
print("2. 上传 deb 并在设备上解包")
print("=" * 70)
sftp = c.open_sftp()
sftp.put(DEB, "/var/mobile/ksdid_final.deb")
sftp.close()

so, se = sush("""
cd /var/tmp
rm -rf _kf 2>/dev/null
mkdir -p _kf
cd _kf
/var/jb/usr/bin/dpkg-deb -x /var/mobile/ksdid_final.deb ./x 2>&1 | head -3
echo "  解包内容:"
find ./x -type f 2>/dev/null | head -10

if [ -f ./x/var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.dylib ]; then
  echo "  ✓ 找到 dylib"
  echo "  MD5: $(md5sum ./x/var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.dylib 2>/dev/null || LC_ALL=C md5 ./x/var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.dylib)"
else
  echo "  ✗ 未找到 dylib"
  ls -laR ./x 2>/dev/null | head -20
fi
""", 300)
print(so.strip()[:1200])

print()
print("=" * 70)
print("3. 复制到所有位置")
print("=" * 70)
so, se = sush("""
SRC=/var/tmp/_kf/x/var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.dylib
[ -f "$SRC" ] || { echo "  ✗ 源文件不存在"; exit 1; }

for DST in /var/jb/usr/lib/TweakInject /var/jb/Library/MobileSubstrate/DynamicLibraries; do
  mkdir -p "$DST" 2>/dev/null
  cp -f "$SRC" "$DST/KSDid.dylib"
  chown root:wheel "$DST/KSDid.dylib"
  chmod 755 "$DST/KSDid.dylib"
  echo "  ✓ $DST/KSDid.dylib"
  echo "     MD5: $(md5sum "$DST/KSDid.dylib" 2>/dev/null || LC_ALL=C md5 "$DST/KSDid.dylib")"
done

# plist
cat > /var/jb/usr/lib/TweakInject/KSDid.plist <<'EOF'
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
chown root:wheel /var/jb/usr/lib/TweakInject/KSDid.plist
chmod 644 /var/jb/usr/lib/TweakInject/KSDid.plist
echo "  ✓ plist"

echo
echo "  最终确认:"
find /var/jb -name 'KSDid.dylib' -exec sh -c 'echo "    $1: $(md5sum "$1" 2>/dev/null || LC_ALL=C md5 "$1")"' _ {} \\;
""", 300)
print(so.strip()[:1500])

print()
print("=" * 70)
print("4. 杀快手")
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
