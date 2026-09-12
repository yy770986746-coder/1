# -*- coding: utf-8 -*-
"""把源设备 did 写入当前设备"""
import sys, io, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.1.2", username="mobile", password="qqqqaaaa", timeout=20,
          allow_agent=False, look_for_keys=False)

def sudosh(script, t=300):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo qqqqaaaa | sudo -S -p '' /var/mobile/_k.sh", timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

APP = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
SRC_DID = "4C96E59A-0F12-47E8-B56B-FFB036C694CB"

so, se = sudosh("""
APP=%s
SRC=%s

echo '=== 1. 停快手 ==='
/usr/bin/killall -9 com_kwai_gif 2>/dev/null
sleep 2
killall -0 com_kwai_gif 2>/dev/null && echo "仍存活" || echo "已停止"

echo
echo '=== 2. 备份原 did 文件 ==='
cp "$APP/Library/Application Support/com.kuaishou.did" "$APP/Library/Application Support/com.kuaishou.did.bak" 2>/dev/null && echo "已备份"
echo "原值: $(cat "$APP/Library/Application Support/com.kuaishou.did" 2>/dev/null)"

echo
echo '=== 3. 写入源设备 did ==='
printf '%%s' "$SRC" > "$APP/Library/Application Support/com.kuaishou.did"
chown mobile:mobile "$APP/Library/Application Support/com.kuaishou.did"
chmod 644 "$APP/Library/Application Support/com.kuaishou.did"
echo "新值: $(cat "$APP/Library/Application Support/com.kuaishou.did")"

echo
echo '=== 4. 检查其他 did 相关文件 ==='
ls -la "$APP/Library/Application Support/com.kuaishou.security.outerid" 2>/dev/null
echo "outerid 内容:"; cat "$APP/Library/Application Support/com.kuaishou.security.outerid" 2>/dev/null; echo
echo "thu 内容:"; cat "$APP/Library/Application Support/com.kuaishou.thu" 2>/dev/null; echo

echo
echo '=== 5. 清 cfprefsd ==='
/usr/bin/killall -9 cfprefsd 2>/dev/null
sleep 1
echo "已清"
""" % (APP, SRC_DID), 300)
print(so.strip()[:3000])
c.close()
