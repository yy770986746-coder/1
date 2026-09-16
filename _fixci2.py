# -*- coding: utf-8 -*-
"""改 CI：make 后直接改写 deb 里的 control（最可靠）"""
import sys, io, os, re

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
p = r"C:\Users\yyds\Desktop\ios快手上号器\.github\workflows\tweak.yml"
s = open(p, encoding="utf-8").read()

# 替换整个 build + verify 段
start = s.find("      - name: Build tweak")
end = s.find("      - name: Upload .deb")
if start < 0 or end < 0:
    print("✗ 找不到目标段"); sys.exit(1)

new_block = '''      - name: Build tweak
        working-directory: kstweak
        run: |
          set -e
          export ARCHS="arm64e"
          make clean 2>/dev/null || true
          make package FINALPACKAGE=1 ARCHS="arm64e" THEOS_PACKAGE_ARCH=iphoneos-arm64e 2>&1 | tail -40
          echo "=== 产物 ==="
          ls -la packages/ || true

      - name: Force arm64e architecture in deb
        working-directory: kstweak
        run: |
          set -e
          DEB=$(ls packages/*.deb 2>/dev/null | head -1)
          if [ -z "$DEB" ]; then echo "没有产出 deb"; exit 1; fi
          echo "原始 deb: $DEB"
          echo "原始架构: $(dpkg-deb -f "$DEB" Architecture)"

          # ★ Theos 会用 ARCHS 覆盖 control 里的 Architecture，
          #   这里解包→改 control→重打包，强制成 iphoneos-arm64e
          WORK=$(mktemp -d)
          dpkg-deb -R "$DEB" "$WORK"
          sed -i '' 's/^Architecture:.*/Architecture: iphoneos-arm64e/' "$WORK/DEBIAN/control" || \\
            sed -i 's/^Architecture:.*/Architecture: iphoneos-arm64e/' "$WORK/DEBIAN/control"
          cat "$WORK/DEBIAN/control"
          dpkg-deb -b "$WORK" "$DEB"
          rm -rf "$WORK"

          echo "=== 最终架构 ==="
          dpkg-deb -f "$DEB" Architecture
          dpkg-deb -c "$DEB"

      - name: Verify deb
        working-directory: kstweak
        run: |
          set -e
          DEB=$(ls packages/*.deb 2>/dev/null | head -1)
          ARCH=$(dpkg-deb -f "$DEB" Architecture)
          echo "最终架构: $ARCH"
          if [ "$ARCH" != "iphoneos-arm64e" ]; then
            echo "架构不对，应为 iphoneos-arm64e"; exit 1
          fi
          dpkg-deb -x "$DEB" /tmp/x
          find /tmp/x -name '*.dylib' -exec file {} \\;

'''

s = s[:start] + new_block + s[end:]
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("✓ CI 已重写")
print()
print("=== 新 CI 内容 ===")
print(s[s.find("- name: Build tweak"):s.find("- name: Upload")][:2000])
