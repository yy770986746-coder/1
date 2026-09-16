# -*- coding: utf-8 -*-
"""分析改机工具：找出它是怎么改 did 的"""
import sys, io, paramiko
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=20,
          allow_agent=False, look_for_keys=False)
print("已连接\n")

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
echo '=== 1. 已安装的改机/工具类 app ==='
ls -d /var/jb/Applications/*.app 2>/dev/null
echo
for a in /var/jb/Applications/*.app; do
  [ -d "$a" ] || continue
  N=$(basename "$a")
  case "$N" in
    *AMG*|*Patcher*|*CTW*|*YYApp*) echo "  ★ $N"; ls "$a" | head -8 | sed 's/^/      /' ;;
  esac
done

echo
echo '=== 2. AMG / CTW 是什么工具 ==='
for a in AMG CTW* Patcher YYApp; do
  for d in /var/jb/Applications/$a.app; do
    [ -d "$d" ] || continue
    echo "--- $d"
    if [ -f "$d/Info.plist" ]; then
      LC_ALL=C grep -a -A1 'CFBundleDisplayName\\|CFBundleName' "$d/Info.plist" 2>/dev/null | grep -a string | head -2
    fi
    ls "$d" | head -10 | sed 's/^/    /'
  done
done

echo
echo '=== 3. 这些工具的可执行文件里的 did 相关字符串 ==='
for a in /var/jb/Applications/*.app; do
  [ -d "$a" ] || continue
  B=$(basename "$a" .app)
  EXE="$a/$B"
  [ -f "$EXE" ] || continue
  H=$(LC_ALL=C strings "$EXE" 2>/dev/null | grep -icE 'did|kKSUMMKVStoreKey|com.kuaishou.did|deleteContainer|mmkv' 2>/dev/null)
  echo "  $B: $H 个相关字符串"
done
""", 600)
print(so.strip()[:4000])
c.close()
