# -*- coding: utf-8 -*-
"""观察快手启动时 AppGroup 的变化"""
import sys, io, os, time, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"
G = "/var/mobile/Containers/Shared/AppGroup/2B64FAB8-2826-4831-A314-5C6DCBEC275F"
D = "/var/mobile/Containers/Data/Application/F046E865-7D1B-4E2B-9966-713C2B79C02D"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(HOST, username="mobile", password=PWD, timeout=25,
          allow_agent=False, look_for_keys=False)

def sh(cmd, t=300):
    _, o, e = c.exec_command(cmd, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

print("=" * 74)
print("1. 当前值")
print("=" * 74)
so, se = sh("LC_ALL=C grep -aoE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' '%s/Library/Preferences/group.com.kwai.video.plist' 2>/dev/null | head -2" % G)
print("  AppGroup: " + so.strip())
so, se = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  未运行'")
print("  快手: " + so.strip())

print()
print("=" * 74)
print("2. 插件日志（v12 是否执行）")
print("=" * 74)
LOG = D + "/Documents/ksdid_log.txt"
s = sh("cat '%s' 2>/dev/null" % LOG)
if s.strip():
    for l in s.strip().split("\n")[:40]:
        print("    " + l[:220])
else:
    print("  (空)")

print()
print("=" * 74)
print("3. ★ 检查 AppGroup 里 A1B2C3D4 的其他位置")
print("=" * 74)
so, se = sh("find '%s' -type f -size -4M 2>/dev/null | while read f; do "
            "LC_ALL=C grep -qa 'A1B2C3D4' \"$f\" 2>/dev/null && echo \"  ${f#%s/}\"; done" % (G, G))
print(so.strip() or "  (无残留)")

print()
print("=" * 74)
print("4. ★ 快手容器里所有含 A1B2C3D4 的文件（再查一次）")
print("=" * 74)
so, se = sh("find '%s' -type f -size -12M 2>/dev/null | head -1500 | while read f; do "
            "LC_ALL=C grep -qa 'A1B2C3D4' \"$f\" 2>/dev/null && echo \"  ${f#%s/}\"; done" % (D, D))
print(so.strip()[:2500] or "  (无)")

print()
print("=" * 74)
print("5. ★ 网络缓存：最新请求用的 did")
print("=" * 74)
CK = D + "/Library/Caches/com.jiangjia.gif/KSURLCache/Cache.db-wal"
so, se = sh("echo %s | sudo -S -p '' sh -c \"LC_ALL=C grep -aoE 'did=[0-9A-Fa-f-]{36}' '%s' 2>/dev/null | tail -20\"" % (PWD, CK), 600)
print("  最后 20 个 did=:")
print("  " + so.strip().replace("\n", "\n  "))

c.close()
