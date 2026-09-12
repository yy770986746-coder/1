# -*- coding: utf-8 -*-
"""分析第5段 base64 protobuf 的真实结构"""
import sys, io, base64
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

S5 = ("Cg9rdWFpc2hvdS5hcGkuc3QSsAFAsu6dJRV1l1916eargBgUc7Oh30i"
      "Wcv6EBqfGigsFZfbMTrpjdQtoz8T0nyKLJh1-EytOu3D-Cw9nlwI7jy2pOS"
      "YcE6HpWsOnevHtPB0E9LQzBDVOb0cE0Vley8Ygy96TCPHyeUQmPO2cmp3_"
      "hAKRBBYQQxCxV7lSrRyWlY21FMv5W2Yp5n-sIaRKGsnO3xoSgZthIiB4goTLa6Dpo_QM8jpvrX_BgsF_IvjfkPSgkN3RIat7DSgFMAE")
S4 = "DFP95CF590C6390FA2595CCFCDA5811D7142147A42B04254B2375A4500687927"

def b64d(s):
    s = s.replace("-", "+").replace("_", "/")
    return base64.b64decode(s + "=" * ((4 - len(s) % 4) % 4))

raw = b64d(S5)
print("=" * 70)
print("第5段 base64 → %d 字节" % len(raw))
print("=" * 70)
print("hex: %s" % raw.hex()[:120])
print()

# 手工解析 protobuf
def parse(b, indent=0, depth=0):
    i = 0
    out = []
    while i < len(b):
        # varint tag
        tag = 0; shift = 0
        while i < len(b):
            byte = b[i]; i += 1
            tag |= (byte & 0x7F) << shift
            if not (byte & 0x80): break
            shift += 7
        if tag == 0: break
        fno = tag >> 3; wt = tag & 7
        pre = "  " * indent
        if wt == 0:  # varint
            v = 0; shift = 0
            while i < len(b):
                byte = b[i]; i += 1
                v |= (byte & 0x7F) << shift
                if not (byte & 0x80): break
                shift += 7
            out.append("%s字段%d = varint %d" % (pre, fno, v))
        elif wt == 2:  # length-delimited
            ln = 0; shift = 0
            while i < len(b):
                byte = b[i]; i += 1
                ln |= (byte & 0x7F) << shift
                if not (byte & 0x80): break
                shift += 7
            chunk = b[i:i+ln]; i += ln
            try:
                txt = chunk.decode("utf-8")
                printable = all(32 <= ord(ch) < 127 for ch in txt)
            except Exception:
                printable = False
            if printable and txt:
                out.append("%s字段%d = \"%s\"  (%d字节)" % (pre, fno, txt, ln))
            else:
                out.append("%s字段%d = 二进制 %d字节" % (pre, fno, ln))
                if depth < 3 and ln > 4:
                    out.extend(parse(chunk, indent + 1, depth + 1))
        elif wt == 5:
            out.append("%s字段%d = fixed32" % (pre, fno)); i += 4
        elif wt == 1:
            out.append("%s字段%d = fixed64" % (pre, fno)); i += 8
        else:
            out.append("%s字段%d = 未知wiretype %d" % (pre, fno, wt)); break
    return out

print("=" * 70)
print("protobuf 结构")
print("=" * 70)
for line in parse(raw):
    print("  " + line)

print()
print("=" * 70)
print("第4段（64位hex）")
print("=" * 70)
print("  %s  (%d 字符)" % (S4, len(S4)))
print("  以 DFP 开头 → 快手设备指纹 Device FingerPrint")
