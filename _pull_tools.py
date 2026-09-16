# -*- coding: utf-8 -*-
"""拉取改机工具二进制分析"""
import sys, io, os, re, base64, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
OUT = r"C:\Users\yyds\Desktop\ksextract_ref\dev_tools"
os.makedirs(OUT, exist_ok=True)

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=20,
          allow_agent=False, look_for_keys=False)

def sush(script, t=900):
    sftp = c.open_sftp()
    with sftp.open("/var/mobile/_k.sh", "w") as f:
        f.write("#!/bin/sh\n" + script + "\n")
    sftp.chmod("/var/mobile/_k.sh", 0o755)
    sftp.close()
    _, o, e = c.exec_command("echo " + PWD + " | sudo -S -p '' /var/mobile/_k.sh", timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

sftp = c.open_sftp()
for name, path in [("YYApp", "/var/jb/Applications/YYApp.app/YYApp"),
                   ("AMG", "/var/jb/Applications/AMG.app/AMG")]:
    so, se = sush("base64 '%s' 2>/dev/null" % path, 900)
    b64 = "".join(so.split())
    if not b64:
        print("✗ %s 拉取失败" % name)
        continue
    data = base64.b64decode(b64)
    lp = os.path.join(OUT, name)
    open(lp, "wb").write(data)
    print("✓ %s: %d 字节" % (name, len(data)))
    # 直接在设备端之外做字符串提取
    strs = re.findall(rb"[\x20-\x7e]{5,}", data)
    hits = [s.decode() for s in strs
            if re.search(r"did|kKSUMMKV|kuaishou|jiangjia|kwai|mmkv|container",
                         s.decode(), re.I)]
    print("  相关字符串 %d 个:" % len(hits))
    for h in hits[:35]:
        print("     %s" % h[:110])
    print()

sftp.close(); c.close()
