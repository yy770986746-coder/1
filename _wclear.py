# -*- coding: utf-8 -*-
"""清掉 Weapon 风控缓存，让快手用新账号重新协商"""
import sys, io, os, paramiko, plistlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
P = ("/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
     "/Library/Preferences/com.jiangjia.gif.plist")
LOCAL = r"C:\Users\yyds\Desktop\ios快手上号器\_ks8.plist"

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

# 备份
so, se = sudosh("cp %s /var/mobile/ks_pre_weapon.plist && echo 已备份" % P)
print(so.strip())

sftp = c.open_sftp(); sftp.get(P, LOCAL); sftp.close()
d = plistlib.load(open(LOCAL, "rb"))
before = len(d)

# 只清 Weapon 的**会话类**键（保留安全证书，那些是固定的）
KILL = []
for k in list(d.keys()):
    kl = k.lower()
    if kl.startswith("weapon_splite-"):        # 分片校验缓存
        KILL.append(k)
    elif k in ("WeaponTokenKey", "WeaponTokenUserCountKey",
               "WeaponPublicTokenIncrementTimeKey"):
        KILL.append(k)

print("将清除 %d 个 Weapon 会话缓存键:" % len(KILL))
for k in KILL:
    print("   ", k)
for k in KILL:
    d.pop(k, None)

plistlib.dump(d, open(LOCAL, "wb"))
print("\n保留 %d 个键（原 %d）" % (len(d), before))

# 关键：先停快手，再写（避免它运行时数据不一致）
so, se = sudosh("/usr/bin/killall -9 com_kwai_gif 2>/dev/null; sleep 2; echo 已停快手")
print(so.strip())
so, se = sudosh("/usr/bin/killall -9 cfprefsd 2>/dev/null; "
                "/usr/bin/killall -9 containermanagerd 2>/dev/null; sleep 1; echo 已清缓存")
print(so.strip())

sftp = c.open_sftp(); sftp.put(LOCAL, "/var/mobile/ks_w.plist"); sftp.close()
so, se = sudosh("cp /var/mobile/ks_w.plist %s && chown mobile:mobile %s && "
                "chmod 600 %s && echo 已写入" % (P, P, P))
print(so.strip())
so, se = sudosh("/usr/bin/killall -9 cfprefsd 2>/dev/null; sleep 1; echo 已刷新")
print(so.strip())

# 回读校验
so, se = sudosh("ls -la %s" % P)
print("\n" + so.strip())
c.close()
print("\n完成。现在打开快手，点之前闪退的功能试试。")
