# -*- coding: utf-8 -*-
"""拉取参考仓库源码"""
import sys, io, os, json, base64, urllib.request, urllib.error

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
TOKEN = os.environ.get("GH_TOKEN", "")
OWNER, REPO = "yy770986746-coder", "ksextract"
OUT = r"C:\Users\yyds\Desktop\ksextract_ref"

def api(path):
    req = urllib.request.Request("https://api.github.com" + path,
                                 headers={"Authorization": "token " + TOKEN,
                                          "User-Agent": "dsh",
                                          "Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        return {"_err": e.code, "_msg": e.read().decode("utf-8", "replace")[:300]}
    except Exception as e:
        return {"_err": -1, "_msg": str(e)}

info = api("/repos/%s/%s" % (OWNER, REPO))
if "_err" in info:
    print("✗ %s" % info); sys.exit(1)
br = info.get("default_branch", "main")
print("仓库: %s  分支: %s" % (info.get("full_name"), br))

tr = api("/repos/%s/%s/git/trees/%s?recursive=1" % (OWNER, REPO, br))
files = [e for e in tr.get("tree", []) if e["type"] == "blob"]
print("文件数: %d\n" % len(files))

os.makedirs(OUT, exist_ok=True)
for e in files:
    p = e["path"]
    if p.lower().endswith((".png", ".jpg", ".ico", ".zip", ".apk", ".deb")):
        continue
    bl = api("/repos/%s/%s/git/blobs/%s" % (OWNER, REPO, e["sha"]))
    if "_err" in bl:
        print("  ✗ %s" % p); continue
    data = base64.b64decode(bl["content"])
    full = os.path.join(OUT, p.replace("/", os.sep))
    os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, "wb").write(data)
    print("  ✓ %-42s %7d 字节" % (p, len(data)))

print("\n完成: %s" % OUT)
