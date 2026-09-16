# -*- coding: utf-8 -*-
"""正确顺序安装 KSDid：先装后清理，并验证 pkgmirror"""
import sys, io, os, glob, tarfile, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
DID = "B28005FA-EE19-4A5F-B6D3-2D7024ECBD37"
DEBS = glob.glob(r"C:\Users\yyds\Desktop\ks-tweak-deb\*.deb")
if not DEBS:
    print("找不到 deb"); sys.exit(1)
DEB = DEBS[0]
print("deb: %s (%d 字节)" % (os.path.basename(DEB), os.path.getsize(DEB)))

# 先验证架构
data = open(DEB, "rb").read()
pos = 8
arch = "?"
while pos < len(data):
    hdr = data[pos:pos+60]
    if len(hdr) < 60: break
    nm = hdr[:16].decode("latin-1").strip().rstrip("/")
    sz = int(hdr[48:58].decode("latin-1").strip())
    body = data[pos+60:pos+60+sz]
    if "control" in nm:
        tf = tarfile.open(fileobj=io.BytesIO(body))
        for m in tf.getmembers():
            if m.name.endswith("control"):
                for line in tf.extractfile(m).read().decode("utf-8", "replace").splitlines():
                    if line.startswith("Architecture"):
                        arch = line.split(":", 1)[1].strip()
    pos = pos + 60 + sz + (sz % 2)
print("deb 架构: %s" % arch)
if arch != "iphoneos-arm64e":
    print("⚠ 架构不是 arm64e，安装可能被 RootHide 忽略")

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

# 1. 上传（先上传！）
print()
print("=" * 60); print("1. 上传"); print("=" * 60)
sftp = c.open_sftp(); sftp.put(DEB, "/var/mobile/ksdid_new.deb")
st = sftp.stat("/var/mobile/ksdid_new.deb"); sftp.close()
print("  已上传 %d 字节" % st.st_size)

# 2. 卸载旧版
print(); print("=" * 60); print("2. 卸载旧版"); print("=" * 60)
so, se = sush("/usr/bin/dpkg --purge --force-depends com.momo.ksdid 2>&1 | tail -2; "
              "rm -f /var/jb/Library/MobileSubstrate/DynamicLibraries/KSDid.* 2>/dev/null; "
              "rm -rf /var/mobile/Library/pkgmirror/DEBIAN.com.momo.ksdid 2>/dev/null; echo done")
print("  " + so.strip()[:300])

# 3. 正常安装
print(); print("=" * 60); print("3. dpkg -i 安装"); print("=" * 60)
so, se = sush("/usr/bin/dpkg -i /var/mobile/ksdid_new.deb 2>&1")
for line in (so + se).splitlines():
    if line.strip() and "password for" not in line and "警告" not in line:
        print("  " + line)

# 4. 验证安装位置
print(); print("=" * 60); print("4. 验证安装位置"); print("=" * 60)
so, se = sh("ls -la /var/jb/Library/MobileSubstrate/DynamicLibraries/ | grep -i ksdid || echo '  jb: 无'")
print("  [jb 目录]")
print("  " + so.strip())
so, se = sh("ls -la /var/mobile/Library/pkgmirror/Library/MobileSubstrate/DynamicLibraries/ 2>/dev/null")
print("  [pkgmirror 目录]")
print("  " + so.strip())

# 5. 写配置
print(); print("=" * 60); print("5. 写入自定义 did"); print("=" * 60)
so, se = sush("""
cat > /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>did</key>
    <string>DIDPLACE</string>
</dict>
</plist>
EOF
chmod 644 /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist
echo "  plist: $(LC_ALL=C grep -A1 'did' /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist | tail -1 | tr -d ' \\t')"
echo "DIDPLACE" > /var/mobile/Documents/ks_did.txt
chmod 644 /var/mobile/Documents/ks_did.txt
echo "  txt: $(cat /var/mobile/Documents/ks_did.txt)"
""".replace("DIDPLACE", DID))
print(so.strip())

# 6. 杀快手
print(); print("=" * 60); print("6. 杀快手"); print("=" * 60)
so, se = sush("""
launchctl list 2>/dev/null | awk '$3 ~ /jiangjia/ {print $1}' | while read pid; do
  kill -9 "$pid" 2>/dev/null; echo "  杀 $pid"
done
sleep 2
launchctl list 2>/dev/null | grep -qi jiangjia && echo "  ✗ 仍在" || echo "  ✓ 已停止"
""")
print(so.strip())

c.close()
print()
print("=" * 60)
print("完成。请手动打开快手，看「帮助→设备信息」里的 did")
print("目标: %s" % DID)
print("=" * 60)
