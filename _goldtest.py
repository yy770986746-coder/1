# -*- coding: utf-8 -*-
"""关键实验：把真机登录态快照完整写回，验证是否可复现登录"""
import sys, io, os, time, paramiko, plistlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
P = ("/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
     "/Library/Preferences/com.jiangjia.gif.plist")
GOLD = r"C:\Users\yyds\Desktop\ios快手上号器\_gold_reference.plist"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.1.2", username="mobile", password="qqqqaaaa", timeout=20,
          allow_agent=False, look_for_keys=False)

def sudosh(script, t=400):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo qqqqaaaa | sudo -S -p '' /var/mobile/_k.sh", timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

APP = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"

# 1. 停快手
so, se = sudosh("/usr/bin/killall -9 com_kwai_gif 2>/dev/null; sleep 2; echo 已停")
print(so.strip())

# 2. 备份当前
so, se = sudosh("cp %s /var/mobile/ks_before_gold.plist && echo 已备份当前" % P)
print(so.strip())

# 3. 读当前 plist，把 gold 里多出来的键合并进去（保留快手自己的新键）
sftp = c.open_sftp()
LOCAL = r"C:\Users\yyds\Desktop\ios快手上号器\_merge.plist"
sftp.get(P, LOCAL); sftp.close()
now = plistlib.load(open(LOCAL, "rb"))
gold = plistlib.load(open(GOLD, "rb"))
print("\n当前 %d 键，快照 %d 键" % (len(now), len(gold)))

# 只补 Gif_* 登录相关键，不动快手自己的运行数据
ADDED = []
for k, v in gold.items():
    if k.startswith("Gif_"):
        if k not in now or type(now[k]) != type(v):
            now[k] = v
            ADDED.append(k)
print("补写/修正 %d 个 Gif_ 键: %s" % (len(ADDED), ADDED))

plistlib.dump(now, open(LOCAL, "wb"))
print("合并后 %d 键" % len(now))

# 4. 清缓存 + 写入
so, se = sudosh("/usr/bin/killall -9 cfprefsd 2>/dev/null; "
                "/usr/bin/killall -9 containermanagerd 2>/dev/null; sleep 1; echo 已清缓存")
print(so.strip())

sftp = c.open_sftp(); sftp.put(LOCAL, "/var/mobile/ks_gold.plist"); sftp.close()
so, se = sudosh("cp /var/mobile/ks_gold.plist %s && chown mobile:mobile %s && "
                "chmod 600 %s && echo 已写入" % (P, P, P))
print(so.strip())

so, se = sudosh("/usr/bin/killall -9 cfprefsd 2>/dev/null; sleep 1; "
                "ls -la %s" % P)
print(so.strip())

# 5. 回读校验
sftp = c.open_sftp(); sftp.get(P, LOCAL); sftp.close()
chk = plistlib.load(open(LOCAL, "rb"))
print()
print("=" * 70)
print("回读校验")
print("=" * 70)
for k in ["Gif_Token", "Gif_ID", "Gif_LastLoginType", "Gif_ServiceToken"]:
    v = chk.get(k)
    print("  %-22s [%-6s] = %s" % (k, type(v).__name__ if v is not None else "-",
                                   str(v)[:50] if v is not None else "✗"))
c.close()
