# -*- coding: utf-8 -*-
"""对生成的 iOS 工程做静态检查（括号配对、必需符号、entitlement 关键项）"""
import os
import re
import sys

ROOT = r"C:\Users\yyds\Desktop\ios快手上号器"
ok, fail = [], []


def check(name, cond, detail=""):
    (ok if cond else fail).append(name)
    print("[%s] %s%s" % ("OK  " if cond else "FAIL", name,
                         ("  -> " + detail) if detail and not cond else ""))


def strip_code(src):
    """逐字符状态机剥离注释与字符串

    不用正则：正则处理 @"..." 与 @{...} 字面量时容易误判，
    实测会把 @{} 里的花括号算漏，导致假告警。
    """
    out = []
    i, n, state = 0, len(src), "code"
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if state == "code":
            if c == "/" and nxt == "/":
                state = "lc"; i += 2; continue
            if c == "/" and nxt == "*":
                state = "bc"; i += 2; continue
            if c == '"':
                state = "s"; i += 1; continue
            if c == "'":
                state = "ch"; i += 1; continue
            out.append(c); i += 1; continue
        if state == "lc":
            if c == "\n":
                state = "code"; out.append(c)
            i += 1; continue
        if state == "bc":
            if c == "*" and nxt == "/":
                state = "code"; i += 2; continue
            i += 1; continue
        if state in ("s", "ch"):
            if c == "\\":
                i += 2; continue
            if (state == "s" and c == '"') or (state == "ch" and c == "'"):
                state = "code"
            i += 1; continue
    return "".join(out)


def brace_balance(path):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    code = strip_code(src)

    # 剔除 C 数组声明 ident[N] / ident[expr]=，它们不是 ObjC 消息方括号
    code = re.sub(r"\b\w+\s*\[\s*\d+\s*\]", "X", code)
    code = re.sub(r"\b\w+\s*\[\s*[A-Za-z_]\w*\s*\]\s*=", "X=", code)

    return (code.count("{") - code.count("}"),
            code.count("(") - code.count(")"),
            code.count("[") - code.count("]"))


print("=" * 66)
print("1. 源文件存在性")
print("=" * 66)
for f in ("app/KSCore.h", "app/KSCore.m", "app/main.m",
          "build_app.py", "ks_ios_runner.py"):
    p = os.path.join(ROOT, f)
    check("存在 %s" % f, os.path.exists(p))

print()
print("=" * 66)
print("2. 括号配对（已剥离字符串与注释）")
print("=" * 66)
for f in ("app/KSCore.m", "app/main.m"):
    p = os.path.join(ROOT, f)
    if not os.path.exists(p):
        continue
    b, pr, br = brace_balance(p)
    check("%s 花括号配对" % f, b == 0, "diff=%d" % b)
    check("%s 圆括号配对" % f, pr == 0, "diff=%d" % pr)
    check("%s 方括号配对" % f, br == 0, "diff=%d" % br)

print()
print("=" * 66)
print("3. KSCore 必需符号")
print("=" * 66)
core_m = open(os.path.join(ROOT, "app/KSCore.m"), encoding="utf-8").read()
core_h = open(os.path.join(ROOT, "app/KSCore.h"), encoding="utf-8").read()

for sym in ("@implementation KSFive", "@implementation KSTarget",
            "@implementation KSInjector", "@implementation KSLog"):
    check("实现 %s" % sym, sym in core_m)

for m in ("+ (instancetype)fromText:", "- (BOOL)usable", "- (NSString *)userId",
          "+ (instancetype)detect", "+ (BOOL)launch:",
          "+ (BOOL)loginWithFive:", "+ (BOOL)writeOnly:",
          "+ (KSFive *)readCurrent:", "+ (BOOL)clearLogin:",
          "+ (BOOL)wipeAllData:", "+ (void)killKuaishou"):
    check("方法 %s" % m, m in core_m or m in core_h)

print()
print("=" * 66)
print("4. 关键登录键（必须两套都写）")
print("=" * 66)
for k in ("Gif_Token", "Gif_Token_Salt", "Gif_KwaiClientSalt",
          "gifshow_token", "gifshow_userid", "token_client_salt",
          "Gif_ServiceToken"):
    check("写入键 %s" % k, ('@"%s"' % k) in core_m)

print()
print("=" * 66)
print("5. 无根越狱关键路径")
print("=" * 66)
build_py = open(os.path.join(ROOT, "build_app.py"), encoding="utf-8").read()
check("使用 /var/jb 前缀", "/var/jb" in build_py or "JB_ROOT" in build_py)
check("Makefile 安装到 /var/jb/Applications",
      "APPLICATIONS" in build_py or "INSTALL_PATH" in build_py or "Applications" in build_py)

print()
print("=" * 66)
print("6. entitlements 关键权限")
print("=" * 66)
ent = open(os.path.join(ROOT, "build_app.py"), encoding="utf-8").read()
for k in ("platform-application", "no-container", "no-sandbox",
          "task_for_pid-allow", "get-task-allow",
          "launchservices"):
    check("权限 %s" % k, k in ent)

print()
print("=" * 66)
print("7. 目标 BundleID 覆盖")
print("=" * 66)
for b in ("com.jiangjia.gif", "com.kuaishou.nebula", "com.kwai.video"):
    check("支持 %s" % b, b in core_m or b in core_h or b in build_py)

print()
print("=" * 66)
print("8. 分隔符解析回归（避免链式替换坑）")
print("=" * 66)
seg = core_m[core_m.find("分隔符归一化"):core_m.find("分隔符归一化") + 700]
check("使用正则一次扫描", "regularExpressionWithPattern" in seg)
check("没有链式 replace(\"----\") 陷阱",
      'replaceOccurrencesOfString:@"----"' not in seg)

print()
print("=" * 66)
print("结果: %d 通过 / %d 失败" % (len(ok), len(fail)))
if fail:
    print("失败项:")
    for f in fail:
        print("  -", f)
print("=" * 66)
sys.exit(0 if not fail else 1)
