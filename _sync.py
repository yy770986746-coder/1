# -*- coding: utf-8 -*-
"""同步源码到各工程目录 + 括号平衡检查"""
import sys, io, os, re, shutil, hashlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
D = r"C:\Users\yyds\Desktop\ios快手上号器"

for f in ("main.m", "KSCore.m", "KSCore.h"):
    for sub in ("xcode_project", os.path.join("theos_build", "ksextract")):
        shutil.copy2(os.path.join(D, "app", f), os.path.join(D, sub, f))

print("同步结果:")
for f in ("main.m", "KSCore.m", "KSCore.h"):
    hs = []
    for sub in ("app", "xcode_project", os.path.join("theos_build", "ksextract")):
        p = os.path.join(D, sub, f)
        hs.append(hashlib.sha256(open(p, "rb").read()).hexdigest())
    print("  %-12s %s" % (f, "一致" if len(set(hs)) == 1 else "不一致"))

print()
STR = re.compile(r'"(\\.|[^"\\])*"')
CHR = re.compile(r"'(\\.|[^'\\])*'")
print("括号平衡:")
for f in ("main.m", "KSCore.m"):
    src = open(os.path.join(D, "app", f), encoding="utf-8").read().split("\n")
    b = p = 0
    for line in src:
        s = STR.sub('""', line)
        s = CHR.sub("''", s)
        s = re.sub(r"//.*$", "", s)
        b += s.count("{") - s.count("}")
        p += s.count("(") - s.count(")")
    print("  %-12s brace=%d paren=%d  %s" % (f, b, p, "OK" if b == 0 and p == 0 else "不平衡!"))

print()
print("确认私有 API 已隔离:")
src = open(os.path.join(D, "app", "KSCore.m"), encoding="utf-8").read()
print("  lsWorkspaceBundlePath 已移除:", "lsWorkspaceBundlePath" not in src)
print("  lsWorkspaceDataContainer 已移除:", "lsWorkspaceDataContainer" not in src)
print("  launch 内有 @try 保护:", "@catch (NSException" in src)
