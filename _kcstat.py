# -*- coding: utf-8 -*-
"""分析 keychain 里快手条目的写入模式"""
import sys, io, os, sqlite3, collections, datetime

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
TMP = r"C:\Users\yyds\Desktop\ios快手上号器\_kc"
db = os.path.join(TMP, "keychain-2.db")

con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
cur = con.cursor()

print("=" * 74)
print("1. ★ 按 svce 分组统计（出现次数 = 写入频率）")
print("=" * 74)
cur.execute("""SELECT svce, COUNT(*) n, MIN(cdat) c0, MAX(mdat) m1,
                      AVG(LENGTH(data)) avglen, MIN(LENGTH(data)) minl, MAX(LENGTH(data)) maxl
               FROM genp WHERE agrp LIKE '%jiangjia%'
               GROUP BY svce ORDER BY n DESC LIMIT 20""")
rows = cur.fetchall()
print("  %-30s %5s  %-19s %-19s %6s" % ("svce(hex前16)", "次数", "创建", "最后修改", "平均data"))
for r in rows:
    sv = bytes(r["svce"])
    hx = sv[:16].hex()
    def ts(x):
        if not x: return "-"
        try: return datetime.datetime.fromtimestamp(x + 978307200).strftime("%m-%d %H:%M:%S")
        except: return str(x)
    print("  %-30s %5d  %-19s %-19s %6d" % (hx, r["n"], ts(r["c0"]), ts(r["m1"]), r["avglen"] or 0))

print()
print("=" * 74)
print("2. ★ 总条目数")
print("=" * 74)
cur.execute("SELECT COUNT(*) FROM genp WHERE agrp LIKE '%jiangjia%'")
print("  快手 genp 条目: %d" % cur.fetchone()[0])

print()
print("=" * 74)
print("3. ★ 所有不同的 agrp")
print("=" * 74)
cur.execute("SELECT agrp, COUNT(*) n FROM genp WHERE agrp LIKE '%jiangjia%' OR agrp LIKE '%kwai%' OR agrp LIKE '%gif%' GROUP BY agrp ORDER BY n DESC")
for r in cur.fetchall():
    print("  %-50s %d" % (r["agrp"], r["n"]))

print()
print("=" * 74)
print("4. ★ 带 TeamID 前缀的条目（插件可能写不进去）")
print("=" * 74)
cur.execute("SELECT COUNT(*) FROM genp WHERE agrp='NR2KD6K4TL.com.jiangjia.gif'")
print("  NR2KD6K4TL.com.jiangjia.gif : %d 条  ← 插件的 entitlements 是 com.jiangjia.gif，不匹配！" % cur.fetchone()[0])
cur.execute("SELECT COUNT(*) FROM genp WHERE agrp='com.jiangjia.gif'")
print("  com.jiangjia.gif            : %d 条" % cur.fetchone()[0])

print()
print("=" * 74)
print("5. ★ data 里的 did 值分布（找 B28005FA / A1B2C3D4）")
print("=" * 74)
cur.execute("SELECT rowid, svce, data, agrp, mdat FROM genp WHERE agrp LIKE '%jiangjia%'")
new_cnt = old_cnt = 0
new_rows, old_rows = [], []
for r in cur.fetchall():
    d = bytes(r["data"]) if r["data"] else b""
    if b"B28005FA" in d:
        new_cnt += 1; new_rows.append(r)
    if b"A1B2C3D4" in d:
        old_cnt += 1; old_rows.append(r)
print("  含 B28005FA 的条目: %d" % new_cnt)
print("  含 A1B2C3D4 的条目: %d" % old_cnt)

def ts(x):
    try: return datetime.datetime.fromtimestamp(x + 978307200).strftime("%m-%d %H:%M:%S")
    except: return "-"

print()
print("  ── 含 B28005FA 的 ──")
for r in new_rows[:10]:
    sv = bytes(r["svce"])[:12].hex()
    print("    rowid=%d svce=%s... %s agrp=%s" % (r["rowid"], sv, ts(r["mdat"]), r["agrp"]))
print()
print("  ── 含 A1B2C3D4 的 ──")
for r in old_rows[:10]:
    sv = bytes(r["svce"])[:12].hex()
    print("    rowid=%d svce=%s... %s agrp=%s" % (r["rowid"], sv, ts(r["mdat"]), r["agrp"]))

con.close()
