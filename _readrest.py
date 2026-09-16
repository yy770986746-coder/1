# -*- coding: utf-8 -*-
"""读日志剩余部分"""
import sys, io, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=300):
    _, o, e = c.exec_command(cmd, timeout=t)
    return o.read().decode("utf-8", "replace")

s = sh("cat '%s/Documents/ksdid_log.txt' 2>/dev/null" % D)
lines = s.strip().split("\n") if s.strip() else []
print("总行数: %d" % len(lines))
print("=" * 78)
# 只显示 150 行以后
for i, l in enumerate(lines):
    if i >= 148:
        print("%4d| %s" % (i, l[:225]))

print()
print("=" * 78)
print("★ 搜索关键行")
print("=" * 78)
for i, l in enumerate(lines):
    if any(k in l for k in ["KC写", "✓成功", "✗失败", "EAccountSDK", "PATCH",
                             "kuaishou_holdout", "异常", "!!!" ]):
        print("%4d| %s" % (i, l[:225]))

c.close()
