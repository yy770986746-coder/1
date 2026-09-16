# -*- coding: utf-8 -*-
"""读诊断版v2 日志"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"
LOG = D + "/Documents/ksdid_log.txt"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=300):
    _, o, e = c.exec_command(cmd, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

print("=" * 70)
print("快手进程")
print("=" * 70)
so, se = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  未运行'")
print("  " + so.strip())

print()
print("=" * 70)
print("★ 插件日志")
print("=" * 70)
so, se = sh("ls -la '%s' 2>/dev/null" % LOG)
print("  " + (so.strip() or "(不存在)"))
print()
so, se = sh("cat '%s' 2>/dev/null" % LOG)
log = so.strip()
if log:
    lines = log.split("\n")
    print("  共 %d 行：" % len(lines))
    for l in lines[:120]:
        print("    %s" % l[:180])
else:
    print("  (空)")

print()
print("=" * 70)
print("统计")
print("=" * 70)
print("  [C数字] Keychain 调用: %d 次" % log.count("[C"))
print("  [SET]   替换成功:      %d 次" % log.count("[SET]"))
print("  [SKIP]  无UUID:        %d 次" % log.count("[SKIP]"))
print("  [ERR]   异常:          %d 次" % log.count("[ERR]"))

c.close()
