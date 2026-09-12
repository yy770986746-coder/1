# -*- coding: utf-8 -*-
"""回滚测试：清掉我们写的键，看快手能否正常启动"""
import sys, io, os, time, paramiko, plistlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
P = ("/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
     "/Library/Preferences/com.jiangjia.gif.plist")
LOCAL = r"C:\Users\yyds\Desktop\ios快手上号器\_ks5.plist"

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

# 先看当前状态
so, se = sudosh("ls -la %s" % P)
print("当前 plist: %s" % so.strip())
sftp = c.open_sftp(); sftp.get(P, LOCAL); sftp.close()
d = plistlib.load(open(LOCAL, "rb"))
print("总键数: %d" % len(d))
mine = [k for k in d if k.startswith("Gif_") or k in
        ("token_client_salt","ClientSalt","uid","user_id","userId")]
print("我们写的键: %d 个" % len(mine))

# 备份整个 plist
so, se = sudosh("cp %s /var/mobile/ks_backup.plist && echo 已备份" % P)
print(so.strip())

# 删除我们写的键
OURS = ["Gif_Token","Gif_Token_Salt","Gif_KwaiClientSalt","Gif_ID","Gif_Kwai_ID",
        "Gif_LastLoginType","Gif_Kwai_New_User","Gif_Name","Gif_HeadUrl",
        "Gif_BigHeadUrls","Gif_defaultHead","Gif_Sex","Gif_Email","Gif_FansNumber",
        "Gif_ProfileUserType","Gif_Background","Gif_pendantType","Gif_pendantUrls",
        "Gif_Contacts_Uploaded","Gif_User_Text","Gif_H","Gif_ServiceToken",
        "Gif_PassToken","token_client_salt","ClientSalt","uid","user_id","userId"]
for k in OURS:
    d.pop(k, None)
plistlib.dump(d, open(LOCAL, "wb"))
print("清理后剩 %d 个键" % len(d))

# 上传回去
so, se = sudosh("/usr/bin/killall -9 cfprefsd 2>/dev/null; "
                "/usr/bin/killall -9 containermanagerd 2>/dev/null; sleep 1; echo ok")
print("已清缓存")
sftp = c.open_sftp()
sftp.put(LOCAL, "/var/mobile/ks_clean.plist")
sftp.close()
so, se = sudosh("cp /var/mobile/ks_clean.plist %s && chown mobile:mobile %s && "
                "chmod 600 %s && echo 已恢复" % (P, P, P))
print(so.strip())
so, se = sudosh("/usr/bin/killall -9 cfprefsd 2>/dev/null; echo 再次清缓存")
print(so.strip())
c.close()
print("\n完成。现在到手机上打开快手，看能否正常进入。")
