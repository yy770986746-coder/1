# -*- coding: utf-8 -*-
"""精确检查：每个方法体内是否有同名局部变量重复声明"""
import sys, io, re
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

src = open("app/KSCore.m", encoding="utf-8").read()

# 精确切分：找到所有方法定义位置
meths = list(re.finditer(r'^([+-])\s*\([^)]*\)\s*([\w:]{1,60})', src, re.M))
print("找到 %d 个方法\n" % len(meths))

problems = []
for idx, m in enumerate(meths):
    name = m.group(2)
    start = m.end()
    # 方法体：从第一个 { 到配对的 }
    bi = src.find("{", start)
    if bi < 0:
        continue
    depth = 0; i = bi; began = False
    while i < len(src):
        if src[i] == "{": depth += 1; began = True
        elif src[i] == "}":
            depth -= 1
            if began and depth == 0: break
        i += 1
    body = src[bi:i]

    # 找顶层（depth==1）的变量声明
    top = []
    d = 0
    for line in body.split("\n"):
        stripped = line.strip()
        # 只统计方法体第一层的声明
        if d == 1:
            mm = re.match(r'(?:__block\s+)?(?:NS\w+\s*\*?\s*|NSString\s*\*\s*|BOOL\s+|int\s+|NSUInteger\s+|id\s+|void\s*\^?\s*)'
                          r'\(?\s*\*?\s*(\w+)\s*[=;)]', stripped)
            if mm:
                top.append(mm.group(1))
        d += line.count("{") - line.count("}")
    dup = {}
    for v in top:
        dup[v] = dup.get(v, 0) + 1
    bad = {k: v for k, v in dup.items() if v > 1}
    if bad:
        problems.append((name, bad))

if problems:
    for n, b in problems:
        print("  %-40s 重复: %s" % (n, b))
else:
    print("  未发现方法内的重复变量声明 ✓")
