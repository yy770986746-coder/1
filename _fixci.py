# -*- coding: utf-8 -*-
"""修正 CI：强制 control 架构 + 验证"""
import sys, io, os

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

p = r"C:\Users\yyds\Desktop\ios快手上号器\.github\workflows\tweak.yml"
s = open(p, encoding="utf-8").read()

# 在 make package 前强制改 control
old = """      - name: Build tweak
        working-directory: kstweak
        run: |
          set -e
          make clean 2>/dev/null || true
          make package FINALPACKAGE=1 2>&1 | tail -40
          echo "=== 产物 ==="
          ls -la packages/ || true"""

new = """      - name: Build tweak
        working-directory: kstweak
        run: |
          set -e
          # ★ 强制 control 的架构为 arm64e（Theos 会用 ARCHS 覆盖，需在 make 前改）
          sed -i '' 's/^Architecture:.*/Architecture: iphoneos-arm64e/' control || \\
            sed -i 's/^Architecture:.*/Architecture: iphoneos-arm64e/' control
          echo "=== control 内容 ==="
          cat control
          make clean 2>/dev/null || true
          make package FINALPACKAGE=1 ARCHS="arm64e" 2>&1 | tail -40
          echo "=== 产物 ==="
          ls -la packages/ || true
          echo "=== 产物架构 ==="
          DEB=$(ls packages/*.deb 2>/dev/null | head -1)
          dpkg-deb -f "$DEB" Architecture || true"""

if old in s:
    s = s.replace(old, new)
    open(p, "w", encoding="utf-8", newline="\n").write(s)
    print("✓ CI 已更新")
else:
    print("✗ 没找到目标片段")
    # 显示实际内容
    print(s[s.find("Build tweak"):s.find("Build tweak")+600])
