# -*- coding: utf-8 -*-
"""下载 keychain-2.db 并解析快手条目"""
import sys, io, os, sqlite3, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
TMP = r"C:\Users\yyds\Desktop\ios快手上号器\_kc"

os.makedirs(TMP, exist_ok=True)
c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sush(script, t=300):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo %s | sudo -S -p '' /var/mobile/_k.sh" % PWD, timeout=t)
    return o.read().decode("utf-8", "replace")

print("拷贝 keychain 数据库...")
so = sush("""
mkdir -p /var/mobile/_kcdump
cp /var/Keychains/keychain-2.db /var/mobile/_kcdump/
cp /var/Keychains/keychain-2.db-wal /var/mobile/_kcdump/ 2>/dev/null
cp /var/Keychains/keychain-2.db-shm /var/mobile/_kcdump/ 2>/dev/null
chmod -R 777 /var/mobile/_kcdump
ls -la /var/mobile/_kcdump/
""")
print(so)

sftp = c.open_sftp()
for f in ["keychain-2.db", "keychain-2.db-wal", "keychain-2.db-shm"]:
    try:
        sftp.get("/var/mobile/_kcdump/" + f, os.path.join(TMP, f))
        print("  ✓ %s" % f)
    except Exception as e:
        print("  ✗ %s: %s" % (f, e))
sftp.close()

print()
print("=" * 74)
print("★ 解析 keychain-2.db")
print("=" * 74)
db = os.path.join(TMP, "keychain-2.db")
try:
    con = sqlite3.connect(db)
    cur = con.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = [r[0] for r in cur.fetchall()]
    print("  表: %s" % ", ".join(tables))

    for tbl in ["genp", "inet", "cert"]:
        if tbl not in tables: continue
        print()
        print("  ── %s ──" % tbl)
        try:
            cur.execute("SELECT * FROM %s LIMIT 0" % tbl)
            cols = [d[0] for d in cur.description]
            print("    列: %s" % ", ".join(cols))
            # 找快手的
            ag = "agrp" if "agrp" in cols else cols[0]
            sv = "svce" if "svce" in cols else cols[1]
            ac = "acct" if "acct" in cols else cols[2]
            d  = "data" if "data" in cols else None
            q = ("SELECT %s,%s,%s%s FROM %s WHERE agrp LIKE '%%kwai%%' OR agrp LIKE '%%gif%%' "
                 "OR svce LIKE '%%kwai%%' OR svce LIKE '%%gif%%' OR svce LIKE '%%Ci%%' "
                 "OR acct LIKE '%%did%%' OR acct LIKE '%%Ci%%' OR acct LIKE '%%Device%%' LIMIT 60") % (
                     ag, sv, ac, ("," + d) if d else "", tbl)
            cur.execute(q)
            rows = cur.fetchall()
            print("    命中 %d 条:" % len(rows))
            for r in rows:
                grp = str(r[0])[:32]
                svc = str(r[1])[:44]
                acc = str(r[2])[:34]
                dat = r[3] if len(r) > 3 else None
                sz = len(dat) if dat else 0
                print("      agrp=%-32s svce=%-44s acct=%-34s data=%dB" % (grp, svc, acc, sz))
        except Exception as e:
            print("    错误: %s" % e)
    con.close()
except Exception as e:
    print("  打开失败: %s" % e)

c.close()
