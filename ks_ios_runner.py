#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
iOS 快手上号器 —— PC 侧主控

配合越狱 iOS 设备上的 KSExtract Tweak 使用。

三条链路：
  1. extract  从爱思/iTunes 备份包提取五参（复用安卓版算法，适配 iOS 键名）
  2. push     把五参推到设备 /var/mobile/Documents/ks_inject.txt，重启快手触发自动上号
  3. pull     从设备回读当前生效五参 + 注入日志，做闭环验证

依赖：pip install paramiko   （越狱设备需装 OpenSSH）
用法：
  python ks_ios_runner.py extract 备份包.rar -o 五参.txt
  python ks_ios_runner.py push 五参.txt --host 192.168.1.50
  python ks_ios_runner.py pull --host 192.168.1.50
  python ks_ios_runner.py auto 备份包.rar --host 192.168.1.50    # 一条龙
"""
import argparse
import io
import json
import os
import plistlib
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

SEP = "----"
ARCHIVE_EXTS = (".rar", ".zip", ".7z")

# 快手 iOS BundleID（新/老/海外）
KS_BUNDLE_IDS = ["com.jiangjia.gif", "com.kuaishou.nebula", "com.kwai.video"]

# 设备端路径
P_INJECT = "/var/mobile/Documents/ks_inject.txt"
P_RESULT = "/var/mobile/Documents/ks_params.txt"
P_LOG = "/var/mobile/Documents/ks_extract.txt"
P_DONE = "/var/mobile/Documents/ks_injected.done"

# ------------------------------------------------------------------
# 五参模型
# ------------------------------------------------------------------


class Five(object):
    def __init__(self, token="", salt="", did="", egid="", api_st="", h5="", pass_=""):
        self.token = (token or "").strip()
        self.salt = (salt or "").strip()
        self.did = (did or "").strip()
        self.egid = (egid or "").strip()
        self.api_st = (api_st or "").strip()
        self.h5 = (h5 or "").strip()
        self.pass_token = (pass_ or "").strip()

    @property
    def uid(self):
        d = self.token.rfind("-")
        return self.token[d + 1:] if d >= 0 else ""

    def is_usable(self):
        """双参即可登录：token 格式合法 + salt 32 hex（与安卓版结论一致）"""
        if not re.match(r"^[0-9a-fA-F]{32}-\d+$", self.token):
            return False
        if not re.match(r"^[a-fA-F0-9]{32}$", self.salt):
            return False
        return True

    def to_line(self):
        return SEP.join([self.token, self.salt, self.did, self.egid, self.api_st])

    def to_json(self):
        return json.dumps({
            "token": self.token, "salt": self.salt, "did": self.did,
            "egid": self.egid, "api_st": self.api_st, "h5Token": self.h5,
            "passToken": self.pass_token, "five": self.to_line(),
        }, ensure_ascii=False, indent=2)

    @staticmethod
    def _normalize(text):
        """把各种分隔符写法统一成 ----，用一次性扫描避免链式替换互相污染

        坑点：不能写成 t.replace("----", SEP).replace("--", SEP)，
        因为 SEP 本身等于 "----"，第一轮结果会被第二轮再次切断，
        字段全部错位（实测 salt 丢失、did 吃掉了 salt）。
        这里用正则一次性匹配所有候选分隔符。
        """
        t = text.strip()
        # 候选：4 连字符 / 2 连字符 / 中文长破折号 / 英文长破折号
        t = re.sub(r"-{2,}|\u2014+|\u2013+", SEP, t)
        return t

    @staticmethod
    def parse(text):
        """从五参行 / JSON / 键值对解析"""
        if not text:
            return None
        t = text.strip()
        t = Five._normalize(t)

        # JSON
        if t.startswith("{"):
            try:
                j = json.loads(t)
                if "five" in j and j["five"]:
                    f = Five.parse(j["five"])
                    if f:
                        f.token = f.token or j.get("token", "")
                        f.salt = f.salt or j.get("salt", "")
                        f.did = f.did or j.get("did", "")
                        f.egid = f.egid or j.get("egid", "")
                        f.api_st = f.api_st or j.get("api_st", "")
                        return f
                return Five(j.get("token", ""), j.get("salt", ""), j.get("did", ""),
                            j.get("egid", ""), j.get("api_st", ""),
                            j.get("h5Token", ""), j.get("passToken", ""))
            except Exception:
                pass

        # 五参行
        for line in t.splitlines():
            line = line.strip()
            if SEP in line:
                parts = [x.strip() for x in line.split(SEP) if x.strip()]
                if len(parts) >= 2:
                    return Five(*parts[:5])

        # 键值对兜底：token=... salt=... 形式
        kv = re.findall(
            r"\b(token|salt|did|egid|api_st|client_salt)\b\s*[=:]\s*([^\s,;&\n]+)",
            text, re.IGNORECASE)
        if kv:
            d = {k.lower(): v.strip("\"'") for k, v in kv}
            f = Five(token=d.get("token", ""),
                     salt=d.get("salt", "") or d.get("client_salt", ""),
                     did=d.get("did", ""),
                     egid=d.get("egid", ""),
                     api_st=d.get("api_st", ""))
            if f.token:
                return f
        return None


# ------------------------------------------------------------------
# 备份包提取（iOS 键名）
# ------------------------------------------------------------------


def get_7za():
    for name in ("7za", "7z", "7zz"):
        p = shutil.which(name)
        if p:
            return p
    for base in (os.path.dirname(os.path.abspath(sys.argv[0])), os.getcwd()):
        for name in ("7za.exe", "7z.exe"):
            p = os.path.join(base, name)
            if os.path.exists(p):
                return p
    return None


def decompress(archive):
    seven = get_7za()
    if not seven:
        raise RuntimeError("缺少 7za.exe 解压器（放到脚本同目录即可）")
    out = tempfile.mkdtemp(prefix="ks_ios_backup_")
    subprocess.run([seven, "x", "-y", "-o" + out, archive],
                   capture_output=True)
    return out


def find_manifestdb(base):
    for root, _dirs, files in os.walk(base):
        if "Manifest.db" in files:
            return root
    return None


def extract_from_hashdir(hashdir):
    """从 iOS 备份的 Manifest.db 提取五参

    关键点（对比安卓版差异）：
      - plist 是二进制 bplist，键名带 Gif_ / KLink_ / KS_OUTERID 前缀
      - token 有两处来源：Preferences plist 的 Gif_Token，或 KWApp 库的 kwapp_host_path_db.db
      - egid 要从日志文件里正则捞 DFP 指纹
      - iOS 也有 gifshow 命名空间的键，与安卓同名，做双通道提取
    """
    db = os.path.join(hashdir, "Manifest.db")
    get_file = lambda fid: os.path.join(hashdir, fid[:2], fid)

    conn = sqlite3.connect(db)
    cur = conn.cursor()
    cur.execute("SELECT DISTINCT domain FROM Files WHERE domain LIKE 'AppDomain-com.%'")
    domains = [r[0] for r in cur.fetchall()]

    app_domain = None
    for cand in ("AppDomain-com.jiangjia.gif", "AppDomain-com.kuaishou.nebula",
                 "AppDomain-com.kwai.video"):
        if cand in domains:
            app_domain = cand
            break
    if not app_domain:
        for d in domains:
            dl = d.lower()
            if any(k in dl for k in ("kwai", "kuaishou", "gif", "nebula")) \
               and "group" not in dl and "plugin" not in dl and "extension" not in dl:
                app_domain = d
                break
    if not app_domain:
        raise RuntimeError("备份里没有快手 App（已扫 %d 个 domain）" % len(domains))

    cur.execute("SELECT fileID, relativePath FROM Files WHERE domain=?", (app_domain,))
    files = {r[1]: r[0] for r in cur.fetchall()}
    conn.close()

    # ---- 定位主 plist ----
    plist_fid = None
    for rp, fid in files.items():
        base = os.path.basename(rp)
        if rp.endswith(".plist") and any(k in base for k in
                                         ("jiangjia.gif", "kuaishou.nebula",
                                          "kuaishou.gif", "kwai.video")):
            plist_fid = fid
            break
    if not plist_fid:
        for rp, fid in files.items():
            if rp.startswith("Library/Preferences/") and rp.endswith(".plist"):
                plist_fid = fid
                break
    if not plist_fid:
        raise RuntimeError("找不到快手的 Preferences plist")

    with open(get_file(plist_fid), "rb") as f:
        d = plistlib.load(f)

    def pick(*keys):
        for k in keys:
            if k in d and d[k]:
                return str(d[k])
        return ""

    # ---- 五参 ----
    # token：iOS 原生 Gif_Token，也兼容安卓同名键
    token = pick("Gif_Token", "gifshow_token", "token")
    salt = pick("Gif_Token_Salt", "Gif_KwaiClientSalt", "ClientSalt",
                "token_client_salt", "client_salt")
    api_st = pick("Gif_ServiceToken", "api_st", "Gif_ServiceTokenKey")
    h5 = pick("Gif_H5Token", "H5Token")
    pass_token = pick("Gif_PassToken", "passToken")
    did = pick("KLink_Persistent_klink.device_id", "WeaponUUIDKey", "did",
               "KLink_DeviceId")

    # token 不走 plist 时，从 KWApp 库捞（老版路径）
    if not re.match(r"^[0-9a-fA-F]{32}-\d+", token):
        kwapp_fid = files.get("Library/KWApp/kwapp_host_path_db.db")
        if kwapp_fid:
            try:
                tmp = os.path.join(tempfile.gettempdir(), "kwapp_ios.db")
                with open(get_file(kwapp_fid), "rb") as src, open(tmp, "wb") as dst:
                    dst.write(src.read())
                c2 = sqlite3.connect(tmp)
                row = c2.execute(
                    "SELECT host_id, owner_id FROM host_path_table LIMIT 1"
                ).fetchone()
                c2.close()
                if row and row[0] and row[1]:
                    token = "%s-%s" % (row[0], row[1])
            except Exception:
                pass

    # ---- egid：DFP 设备指纹，从日志/DB 里捞 ----
    egid = ""
    dfp_re = re.compile(r"global_id=(DFP[0-9A-Fa-f]{40,64})")
    dfp_re2 = re.compile(r"\b(DFP[0-9A-Fa-f]{40,64})\b")
    scanned = 0
    for rp, fid in files.items():
        if rp.endswith((".db", ".sqlite", ".log", ".txt", ".dat")):
            path = get_file(fid)
            if not os.path.exists(path):
                continue
            try:
                if os.path.getsize(path) > 8_000_000:
                    continue
                raw = open(path, "rb").read()
            except Exception:
                continue
            scanned += 1
            s = raw.decode("latin-1", "replace")
            m = dfp_re.search(s) or dfp_re2.search(s)
            if m:
                egid = m.group(1)
                break
    if not egid:
        egid = pick("KS_OUTERID_KEY", "egid", "KS_OUTERID")

    return Five(token, salt, did, egid, api_st, h5, pass_token), app_domain


def extract(path):
    tmp = None
    try:
        if path.lower().endswith(ARCHIVE_EXTS):
            tmp = decompress(path)
            base = tmp
        else:
            base = path
        hashdir = find_manifestdb(base)
        if not hashdir:
            raise RuntimeError("未找到 Manifest.db（不是 iOS 备份目录？）")
        return extract_from_hashdir(hashdir)
    finally:
        if tmp and os.path.isdir(tmp):
            shutil.rmtree(tmp, ignore_errors=True)


# ------------------------------------------------------------------
# 设备侧（SSH）
# ------------------------------------------------------------------


def ssh_connect(host, port=22, user="root", password="alpine"):
    try:
        import paramiko
    except ImportError:
        raise RuntimeError("缺少 paramiko：pip install paramiko")
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(host, port=port, username=user, password=password, timeout=15)
    return c


def run(ssh, cmd, timeout=30):
    _in, out, err = ssh.exec_command(cmd, timeout=timeout)
    o = out.read().decode("utf-8", "replace")
    e = err.read().decode("utf-8", "replace")
    rc = out.channel.recv_exit_status()
    return rc, o, e


def detect_bundle(ssh):
    """设备上探测快手 BundleID"""
    rc, o, _ = run(ssh, "ls -d /var/containers/Bundle/Application/*/"
                        "{com.jiangjia.gif,com.kuaishou.nebula,com.kwai.video}.app 2>/dev/null")
    for bid in KS_BUNDLE_IDS:
        if bid in o:
            return bid
    rc, o, _ = run(ssh, "ls /var/containers/Bundle/Application/*/ 2>/dev/null | sort -u")
    for line in o.splitlines():
        if ".app" in line:
            return line.strip().replace(".app", "")
    return KS_BUNDLE_IDS[0]


def push_and_inject(ssh, five, wait=12):
    """推五参 → 重启快手 → 等标记文件"""
    bid = detect_bundle(ssh)
    print("[设备] 快手 BundleID = %s" % bid)

    # 清掉上次的标记
    run(ssh, "rm -f %s" % P_DONE)

    # 写控制文件
    line = five.to_line()
    safe = line.replace("'", "")
    rc, o, e = run(ssh, "mkdir -p /var/mobile/Documents && "
                        "printf '%%s' '%s' > %s && chmod 644 %s"
                        % (safe, P_INJECT, P_INJECT))
    if rc != 0:
        raise RuntimeError("写控制文件失败: %s %s" % (o, e))
    print("[设备] 已推送五参 -> %s" % P_INJECT)

    # 重启快手
    run(ssh, "killall -9 %s 2>/dev/null; killall -9 %s 2>/dev/null"
        % ("com_kwai_gif", bid))
    time.sleep(1)
    rc, o, _ = run(ssh, "uiopen --bundleid %s 2>/dev/null || "
                        "uiopen %s 2>/dev/null" % (bid, bid))
    print("[设备] 已拉起快手，等待注入生效...")

    # 轮询标记文件
    for i in range(wait):
        time.sleep(1)
        rc, o, _ = run(ssh, "cat %s 2>/dev/null" % P_DONE)
        if "OK" in o:
            print("[上号] ✓ 注入确认: %s" % o.strip())
            return True
    print("[上号] ⚠ 未等到标记文件，请查日志 %s" % P_LOG)
    return False


def pull_status(ssh):
    """回读设备上的五参与日志"""
    bid = detect_bundle(ssh)
    out = {"bundle": bid}

    rc, o, _ = run(ssh, "cat %s 2>/dev/null" % P_RESULT)
    out["result"] = o.strip()

    rc, o, _ = run(ssh, "tail -60 %s 2>/dev/null" % P_LOG)
    out["log"] = o.strip()

    rc, o, _ = run(ssh, "cat %s 2>/dev/null" % P_DONE)
    out["done"] = o.strip()

    return out


# ------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description="iOS 快手上号器 PC 侧主控")
    sub = ap.add_subparsers(dest="cmd")

    pe = sub.add_parser("extract", help="从 iOS 备份包提取五参")
    pe.add_argument("paths", nargs="+", help="备份目录或 .rar/.zip/.7z")
    pe.add_argument("-o", "--out", default="五参.txt")

    pp = sub.add_parser("push", help="推送五参并触发上号")
    pp.add_argument("five", help="五参文件或直接是五参行")
    pp.add_argument("--host", required=True)
    pp.add_argument("--port", type=int, default=22)
    pp.add_argument("--user", default="root")
    pp.add_argument("--password", default="alpine")

    pl = sub.add_parser("pull", help="回读设备当前五参与日志")
    pl.add_argument("--host", required=True)
    pl.add_argument("--port", type=int, default=22)
    pl.add_argument("--user", default="root")
    pl.add_argument("--password", default="alpine")

    pa = sub.add_parser("auto", help="一条龙：提取 → 推送 → 验证")
    pa.add_argument("paths", nargs="+")
    pa.add_argument("--host", required=True)
    pa.add_argument("--port", type=int, default=22)
    pa.add_argument("--user", default="root")
    pa.add_argument("--password", default="alpine")

    args = ap.parse_args()

    if args.cmd == "extract":
        lines, ok, fail = [], 0, 0
        for p in args.paths:
            try:
                five, domain = extract(p)
                line = five.to_line()
                print("%s\n  token=%s\n  salt=%s\n  did=%s\n  egid=%s\n  api_st=%s\n  usable=%s"
                      % (line, five.token, five.salt, five.did, five.egid,
                         five.api_st, five.is_usable()))
                lines.append(line)
                ok += 1
            except Exception as ex:
                print("[失败 %s] %s" % (os.path.basename(p), ex))
                lines.append("[失败 %s] %s" % (os.path.basename(p), ex))
                fail += 1
        with open(args.out, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        print("\n[完成] 成功 %d / 失败 %d -> %s" % (ok, fail, args.out))
        return 0

    if args.cmd == "push":
        src = args.five
        if os.path.exists(src):
            src = open(src, encoding="utf-8").read()
        five = Five.parse(src)
        if not five:
            print("[错误] 五参解析失败")
            return 1
        print("[解析] %s" % five.to_line())
        print("[校验] usable=%s uid=%s" % (five.is_usable(), five.uid))
        ssh = ssh_connect(args.host, args.port, args.user, args.password)
        try:
            ok = push_and_inject(ssh, five)
            print("\n".join(["", "---- 设备日志 ----", pull_status(ssh)["log"]]))
            return 0 if ok else 2
        finally:
            ssh.close()

    if args.cmd == "pull":
        ssh = ssh_connect(args.host, args.port, args.user, args.password)
        try:
            st = pull_status(ssh)
            print("BundleID : %s" % st["bundle"])
            print("当前五参 : %s" % st["result"])
            print("上号标记 : %s" % st["done"])
            print("---- 日志 ----")
            print(st["log"])
            return 0
        finally:
            ssh.close()

    if args.cmd == "auto":
        five, ok = None, False
        for p in args.paths:
            try:
                five, _dom = extract(p)
                ok = True
                break
            except Exception as ex:
                print("[提取失败 %s] %s" % (os.path.basename(p), ex))
        if not ok:
            return 1
        print("[提取] %s" % five.to_line())
        if not five.is_usable():
            print("[警告] 五参不完整（token/salt 不合法），仍尝试注入")

        ssh = ssh_connect(args.host, args.port, args.user, args.password)
        try:
            good = push_and_inject(ssh, five)
            st = pull_status(ssh)
            print("\n---- 设备日志 ----\n%s" % st["log"])
            return 0 if good else 2
        finally:
            ssh.close()

    ap.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
