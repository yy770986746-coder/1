# -*- coding: utf-8 -*-
"""确认新越狱环境"""
import sys, io, os, paramiko

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
HOST, PWD = "192.168.1.4", "qqqqaaaa"

c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
try:
    c.connect(HOST, username="mobile", password=PWD, timeout=25,
              allow_agent=False, look_for_keys=False)
except Exception as e:
    print("✗ SSH 连接失败: %s" % e)
    print("  可能密码变了或 SSH 未启动")
    sys.exit(1)
print("✓ SSH 已连接\n")

def sh(cmd, t=300):
    _, o, e = c.exec_command(cmd, timeout=t)
    return (o.read().decode("utf-8", "replace"),
            e.read().decode("utf-8", "replace"))

print("=" * 70)
print("1. 越狱环境")
print("=" * 70)
so, se = sh("uname -a; echo '---'; ls -la /var/jb 2>/dev/null | head -5; echo '---'; "
            "ls -la / 2>/dev/null | head -20")
print(so.strip()[:1500])

print()
print("=" * 70)
print("2. 注入引擎")
print("=" * 70)
so, se = sh("dpkg -l 2>/dev/null | grep -iE 'ellekit|substrate|rootless|dopamine' | head -10")
print(so.strip() or "  (无)")

print()
print("=" * 70)
print("3. 插件目录")
print("=" * 70)
for d in ["/var/jb/Library/MobileSubstrate/DynamicLibraries",
          "/var/jb/usr/lib/TweakInject",
          "/Library/MobileSubstrate/DynamicLibraries"]:
    so, se = sh("ls %s 2>/dev/null | head -12" % d)
    print("  %s:" % d)
    print("    " + (so.strip().replace("\n", "\n    ") or "(不存在)"))

print()
print("=" * 70)
print("4. KSDid 是否还在")
print("=" * 70)
so, se = sh("find /var/jb /Library -name 'KSDid*' 2>/dev/null | head -10")
print("  " + (so.strip() or "(无)"))

print()
print("=" * 70)
print("5. 快手状态")
print("=" * 70)
so, se = sh("ls -d /var/containers/Bundle/Application/*/com_kwai_gif.app 2>/dev/null")
print("  App: " + (so.strip() or "(未安装)"))
so, se = sh("launchctl list 2>/dev/null | grep -i jiangjia || echo '  未运行'")
print("  进程: " + so.strip())

c.close()
