# -*- coding: utf-8 -*-
"""★ iOS 上找 egid"""
import sys, io, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
G = "/var/mobile/Containers/Shared/AppGroup/2B64FAB8-2826-4831-A314-5C6DCBEC275F"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sush(script, t=900):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return o.read().decode("utf-8", "replace")

print("=" * 78)
print("1. ★ 容器 + AppGroup 里含 'egid' 的文件")
print("=" * 78)
so = sush("""
D="%s"; G="%s"
echo "  [容器]"
find "$D" -type f -size -20M 2>/dev/null | head -3000 | while read f; do
  LC_ALL=C grep -qa 'egid' "$f" 2>/dev/null && echo "    ${f#$D/}"
done
echo "  [AppGroup]"
find "$G" -type f -size -20M 2>/dev/null | while read f; do
  LC_ALL=C grep -qa 'egid' "$f" 2>/dev/null && echo "    ${f#$G/}"
done
""" % (D, G), 900)
print(so.strip()[:3000] or "  (无)")

print()
print("=" * 78)
print("2. ★ 含 'egid' 的 MMKV 内容上下文")
print("=" * 78)
so = sush("""
D="%s"
for f in "$D/Documents/mmkv/"*; do
  [ -f "$f" ] || continue
  if LC_ALL=C grep -qa 'egid' "$f" 2>/dev/null; then
    echo "  ── $(basename $f) ──"
    LC_ALL=C grep -ao '.\\{0,60\\}egid.\\{0,90\\}' "$f" 2>/dev/null | head -3
  fi
done
""" % D)
print(so.strip()[:3000] or "  (无)")

print()
print("=" * 78)
print("3. ★ 快手容器里含 'EGID' 的大写")
print("=" * 78)
so = sush("""
D="%s"
find "$D" -type f -size -20M 2>/dev/null | head -3000 | while read f; do
  LC_ALL=C grep -qa 'EGID' "$f" 2>/dev/null && echo "  ${f#$D/}"
done | head -20
""" % D, 900)
print(so.strip()[:2000] or "  (无)")

c.close()
