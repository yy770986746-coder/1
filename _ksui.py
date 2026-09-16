# -*- coding: utf-8 -*-
"""分析 kstoken 的 UI 界面（找功能按钮）"""
import sys, io, os, zipfile, re

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
APK = r"C:\Users\yyds\Desktop\ios快手上号器\_android_apps\com.hmt.ks.apk"
z = zipfile.ZipFile(APK)

print("=" * 74)
print("1. 所有 layout 文件")
print("=" * 74)
for n in z.namelist():
    if "layout" in n and n.endswith(".xml"):
        print("  %-60s %d" % (n, z.getinfo(n).file_size))

print()
print("=" * 74)
print("2. ★ 所有字符串资源（UI 文案）")
print("=" * 74)
for n in z.namelist():
    if n == "resources.arsc":
        data = z.read(n)
        # 简单提取 UTF-8 中文
        try:
            txt = data.decode("utf-8", "replace")
            cn = re.findall(r"[\u4e00-\u9fff][\u4e00-\u9fff\w，。：！？、（）\s]{1,30}", txt)
            seen = set()
            for c in cn:
                c = c.strip()
                if c and len(c) >= 2 and c not in seen:
                    seen.add(c)
                    print("  %s" % c)
                    if len(seen) >= 60: break
        except Exception as e:
            print("  解析失败: %s" % e)

print()
print("=" * 74)
print("3. ★ 所有英文 UI 文案")
print("=" * 74)
for n in z.namelist():
    if n == "resources.arsc":
        data = z.read(n)
        txt = data.decode("utf-8", "replace")
        en = re.findall(r"[A-Z][a-z]+(?:\s+[A-Za-z]{2,}){1,4}", txt)
        seen = set()
        for e in en:
            if e not in seen and 8 < len(e) < 50:
                seen.add(e)
                print("  %s" % e)
                if len(seen) >= 50: break

print()
print("=" * 74)
print("4. ★ dex 里所有 method 名（看有什么功能）")
print("=" * 74)
# 从 dex string 池直接找
data = z.read("classes.dex")
seen = set()
for m in re.finditer(rb"[\x20-\x7e]{4,60}", data):
    s = m.group(0).decode("ascii", "replace")
    low = s.lower()
    if any(k in low for k in ["set", "get", "write", "read", "modify", "change",
                               "update", "save", "export", "import", "inject",
                               "extract", "decode", "encode", "decrypt", "encrypt"]):
        if s not in seen and not s.startswith(("android", "java", "com/google",
                                                "Landroid", "Ljava", "Lcom/google")):
            seen.add(s)
            print("  %s" % s)
            if len(seen) >= 70: break
