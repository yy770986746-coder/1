# -*- coding: utf-8 -*-
"""列出快手的所有 Keychain 条目"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=300):
    _, o, e = c.exec_command(cmd, timeout=t)
    return o.read().decode("utf-8", "replace")

def sush(script, t=300):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return o.read().decode("utf-8", "replace")

print("=" * 74)
print("1. Keychain 数据库位置")
print("=" * 74)
so = sh("ls -la /var/Keychains/ 2>/dev/null | head -10")
print(so)

print("=" * 74)
print("2. ★ keychain-2.db 里快手的条目")
print("=" * 74)
so = sush("""
DB=/var/Keychains/keychain-2.db
[ -f "$DB" ] || { echo "  无 $DB"; exit; }
ls -la "$DB"
echo ""
command -v sqlite3 >/dev/null 2>&1 && echo "  有 sqlite3" || echo "  ⚠ 无 sqlite3"
echo ""
echo "  --- genp (通用密码) 表里含 kwai/gifshow 的 ---"
sqlite3 "$DB" "SELECT agrp, svce, acct FROM genp WHERE agrp LIKE '%kwai%' OR agrp LIKE '%gifshow%' OR svce LIKE '%Kwai%' OR svce LIKE '%gif%' OR svce LIKE '%CiInfo%' OR acct LIKE '%did%' LIMIT 40;" 2>&1
""", 300)
print(so)

print("=" * 74)
print("3. 所有 agrp（access group）")
print("=" * 74)
so = sush("""
DB=/var/Keychains/keychain-2.db
echo "  --- genp 的 agrp ---"
sqlite3 "$DB" "SELECT DISTINCT agrp FROM genp LIMIT 40;" 2>&1
echo ""
echo "  --- 含 kwai 的表 ---"
sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table';" 2>&1
""", 300)
print(so)

c.close()
