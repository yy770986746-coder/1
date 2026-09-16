# -*- coding: utf-8 -*-
"""深入分析 YYApp / AMG —— 找出改 did 的具体做法"""
import sys, io, paramiko
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
HOST, PWD = "192.168.1.4", "qqqqaaaa"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=20,
          allow_agent=False, look_for_keys=False)

def sush(script, t=600):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo " + PWD + " | sudo -S -p '' /var/mobile/_k.sh", timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

so, se = sush("""
echo '=== 1. YYApp 显示名 ==='
for d in /var/jb/Applications/YYApp.app /var/jb/Applications/AMG.app; do
  echo "--- $d"
  LC_ALL=C strings "$d/Info.plist" 2>/dev/null | grep -iE 'CFBundle|executable' | head -5
done

echo
echo '=== 2. YYApp 里的 did / 改机相关字符串 ==='
EXE=/var/jb/Applications/YYApp.app/YYApp
LC_ALL=C strings "$EXE" 2>/dev/null | grep -iE 'did|kKSUMMKV|kuaishou|jiangjia|kwai|container|mmkv|delete' | sort -u | head -40

echo
echo '=== 3. YYApp 调用了哪些系统工具 ==='
LC_ALL=C strings "$EXE" 2>/dev/null | grep -aE '^/(usr|bin|var)' | sort -u | head -20

echo
echo '=== 4. AMG 里的相关字符串 ==='
EXE2=/var/jb/Applications/AMG.app/AMG
LC_ALL=C strings "$EXE2" 2>/dev/null | grep -iE 'did|kKSUMMKV|kuaishou|jiangjia|mmkv' | sort -u | head -30

echo
echo '=== 5. Patcher 的 patch.sh ==='
cat /var/jb/Applications/Patcher.app/patch.sh 2>/dev/null | head -40
""", 600)
print(so.strip()[:5000])
c.close()
