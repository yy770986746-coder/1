# -*- coding: utf-8 -*-
"""构造模拟 iOS 备份，端到端验证五参提取链路"""
import os, sqlite3, plistlib, hashlib, tempfile, sys, json
sys.path.insert(0, r"C:\Users\yyds\Desktop\ios快手上号器")
import ks_ios_runner as R

base = tempfile.mkdtemp(prefix="ks_fake_backup_")
print("备份目录:", base)

# Manifest.db
db = os.path.join(base, "Manifest.db")
conn = sqlite3.connect(db)
conn.execute("CREATE TABLE Files (fileID TEXT, domain TEXT, relativePath TEXT)")
conn.execute("CREATE TABLE Properties (key TEXT, value BLOB)")

def add(domain, relpath, payload, fileid=None):
    fid = fileid or hashlib.sha1((domain + "-" + relpath).encode()).hexdigest()
    os.makedirs(os.path.join(base, fid[:2]), exist_ok=True)
    with open(os.path.join(base, fid[:2], fid), "wb") as f:
        f.write(payload)
    conn.execute("INSERT INTO Files VALUES (?,?,?)", (fid, domain, relpath))
    return fid

DOM = "AppDomain-com.jiangjia.gif"

# 主 Preferences plist —— 复原 iOS 快手真实键名
TOKEN = "9f3a1c7e5b2d8460af17c3e95d0b28a4-1234567890"
SALT  = "4b8e1f2a9c3d7056e8b2a4f61d3c9e07"
API_ST = "Ch8KAggBEhQIABAAGAMgASgBMAE4AUABSAFYAWAB"
DID   = "FA47F00F-8A86-4306-AAD3-0319FF6A0F8E"

plist_data = {
    "Gif_Token": TOKEN,
    "Gif_Token_Salt": SALT,
    "Gif_KwaiClientSalt": SALT,
    "Gif_ServiceToken": API_ST,
    "Gif_H5Token": "H5_" + SALT,
    "Gif_PassToken": "PT_" + SALT,
    "KLink_Persistent_klink.device_id": DID,
    "KS_OUTERID_KEY": "",
    "SomeOtherKey": "noise",
}
add(DOM, "Library/Preferences/com.jiangjia.gif.plist", plistlib.dumps(plist_data))

# 日志文件里埋 DFP 指纹
EGID = "DFPF72754B1A352A854BABBAA636AA6B3CC8621B8A026FD1C734D8285EAC48EA"
log = ("2026-08-29 22:01:50.123 Kwai[1234] global_id=" + EGID +
       " did=" + DID + " ver=14.7.40.9965\n" * 3).encode()
add(DOM, "Library/Caches/kwai_net.log", log)

# 干扰项：别的 App
add("AppDomain-com.tencent.xin", "Library/Preferences/com.tencent.xin.plist",
    plistlib.dumps({"noise": "1"}))

conn.commit()
conn.close()

print("\n" + "=" * 60)
print("测试 1: 目录形式提取")
print("=" * 60)
five, domain = R.extract(base)
print("命中 domain :", domain)
print("token      :", five.token)
print("salt       :", five.salt)
print("did        :", five.did)
print("egid       :", five.egid)
print("api_st     :", five.api_st)
print("uid        :", five.uid)
print("is_usable  :", five.is_usable())
print("五参行     :", five.to_line())

ok = []
ok.append(("domain 命中", domain == DOM))
ok.append(("token 正确", five.token == TOKEN))
ok.append(("salt 正确", five.salt == SALT))
ok.append(("did 正确", five.did == DID))
ok.append(("egid 正确", five.egid == EGID))
ok.append(("api_st 正确", five.api_st == API_ST))
ok.append(("uid 正确", five.uid == "1234567890"))
ok.append(("可用性判定", five.is_usable() is True))

print("\n" + "=" * 60)
print("测试 2: 多格式解析")
print("=" * 60)
line = five.to_line()
for label, text in [
    ("五参行", line),
    ("JSON", five.to_json()),
    ("键值对", "token=%s salt=%s did=%s" % (TOKEN, SALT, DID)),
    ("中文破折号", line.replace("----", "——")),
]:
    p = R.Five.parse(text)
    good = p and p.token == TOKEN and p.salt == SALT
    print("[%-10s] %s  -> %s" % (label, "OK" if good else "FAIL",
                                 (p.token[:16] + "...") if p else None))
    ok.append(("解析-" + label, bool(good)))

print("\n" + "=" * 60)
print("测试 3: 合法性校验")
print("=" * 60)
cases = [
    ("正常", R.Five(TOKEN, SALT), True),
    ("token 非32hex", R.Five("bad-" + "1" * 10, SALT), False),
    ("salt 太短", R.Five(TOKEN, "abc"), False),
    ("缺 salt", R.Five(TOKEN, ""), False),
    ("salt 非 hex", R.Five(TOKEN, "z" * 32), False),
]
for label, f, expect in cases:
    got = f.is_usable()
    print("[%-14s] usable=%-5s expect=%-5s %s" % (label, got, expect,
                                                  "OK" if got == expect else "FAIL"))
    ok.append(("校验-" + label, got == expect))

print("\n" + "=" * 60)
passed = sum(1 for _, v in ok if v)
print("结果: %d/%d 通过" % (passed, len(ok)))
for k, v in ok:
    if not v:
        print("  FAILED:", k)
print("=" * 60)

import shutil
shutil.rmtree(base, ignore_errors=True)
sys.exit(0 if passed == len(ok) else 1)
