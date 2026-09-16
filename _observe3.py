# -*- coding: utf-8 -*-
"""继续查：界面 did 的真实来源"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
G = "/var/mobile/Containers/Shared/AppGroup/2B64FAB8-2826-4831-A314-5C6DCBEC275F"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=600):
    _, o, e = c.exec_command(cmd, timeout=t)
    return o.read().decode("utf-8", "replace")

print("=" * 74)
print("1. AppGroup 当前值")
print("=" * 74)
so = sh("LC_ALL=C grep -aoE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' '%s/Library/Preferences/group.com.kwai.video.plist' 2>/dev/null | head -2" % G)
print("  " + so.strip())

print()
print("=" * 74)
print("2. 插件日志")
print("=" * 74)
LOG = D + "/Documents/ksdid_log.txt"
so = sh("cat '%s' 2>/dev/null" % LOG)
if so.strip():
    for l in so.strip().split("\n")[:40]:
        print("    " + l[:220])
else:
    print("  (空)")

print()
print("=" * 74)
print("3. ★ 快手容器里含 A1B2C3D4 的文件")
print("=" * 74)
so = sh("find '%s' -type f -size -12M 2>/dev/null | head -1500 | while read f; do "
        "LC_ALL=C grep -qa 'A1B2C3D4' \"$f\" 2>/dev/null && echo \"  ${f#%s/}\"; done" % (D, D))
print(so.strip()[:2500] or "  (无)")

print()
print("=" * 74)
print("4. ★ 网络缓存最后几个 did=")
print("=" * 74)
CK = D + "/Library/Caches/com.jiangjia.gif/KSURLCache/Cache.db-wal"
so = sh("echo %s | sudo -S -p '' sh -c \"LC_ALL=C grep -aoE 'did=[0-9A-Fa-f-]{36}' '%s' 2>/dev/null | tail -15\"" % (PWD, CK))
print("  " + so.strip().replace("\n", "\n  "))

print()
print("=" * 74)
print("5. 所有 AppGroup 里含 A1B2C3D4 的")
print("=" * 74)
so = sh("find /var/mobile/Containers/Shared/AppGroup -type f -size -4M 2>/dev/null | head -400 | "
        "while read f; do LC_ALL=C grep -qa 'A1B2C3D4' \"$f\" 2>/dev/null && echo \"  $f\"; done")
print(so.strip() or "  (无)")

c.close()
