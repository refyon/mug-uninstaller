#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mac-uninstaller 原型 CLI（Python3 stdlib 版）。

背景：本机 CLT 的 swiftc(6.0.3.1.10) 与全部 SDK swiftinterface(≤1.5) 版本不匹配，
Swift 编译不可用（见 docs/mac-uninstaller-design.md「环境约束」）。扫描规则与
Sources/UninstallerKit/*.swift 逐条对应，工具链修复后移植回 Swift。

用法:
  uninstaller_cli.py list                      列出已装应用
  uninstaller_cli.py scan <app路径|bundle id>  扫描残留
  uninstaller_cli.py uninstall <app|bundle id> 卸载（默认干跑；--confirm 实际执行；--skip-low 跳过低置信）
"""
import os
import plistlib
import subprocess
import sys

HIGH, MEDIUM, LOW = "high", "medium", "low"
CONF_TITLE = {HIGH: "高置信(可安全删)", MEDIUM: "中置信(建议确认)", LOW: "低置信(需人工确认)"}
RANK = {LOW: 0, MEDIUM: 1, HIGH: 2}


def read_plist(path):
    try:
        with open(path, "rb") as f:
            return plistlib.load(f)
    except Exception:
        return None


def du_kb(path):
    """返回占用 KB；无权限/失败返回 None。"""
    p = subprocess.run(["/usr/bin/du", "-sk", path], capture_output=True, text=True)
    if p.returncode != 0:
        return None
    try:
        return int(p.stdout.split("\t")[0])
    except Exception:
        return None


def run(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return p.stdout or ""
    except Exception:
        return ""


def name_variants(base):
    b = base.strip()
    if not b:
        return []
    return sorted({
        b, b.replace(" ", ""), b.replace(" ", "-"),
        b.replace(" ", "_"), b.lower(),
    })


# ---------- Step1: 应用扫描 ----------

def app_info(app_path):
    url = os.path.join(app_path, "Contents", "Info.plist")
    info = read_plist(url) or {}
    bid = info.get("CFBundleIdentifier")
    name = info.get("CFBundleDisplayName") or info.get("CFBundleName") \
        or os.path.basename(app_path)[:-4]
    version = info.get("CFBundleShortVersionString") or info.get("CFBundleVersion")
    real = os.path.realpath(app_path)

    source = "?"
    if os.path.exists(os.path.join(app_path, "Contents", "_MASReceipt")):
        source = "mas"
    elif "/Caskroom/" in real:
        source = "brew-cask"
    else:
        pkgs = run(["/usr/sbin/pkgutil", "--pkgs"])
        needle = (bid or name).lower()
        if any(needle in p.lower() for p in pkgs.splitlines()):
            source = "pkg"

    running = False
    exe = info.get("CFBundleExecutable")
    if exe:
        running = run(["/usr/bin/pgrep", "-x", exe]).strip() != ""
    return {
        "path": app_path, "bid": bid, "name": name, "version": version,
        "source": source,
        "system": ("/System/Applications" in real
                   or os.path.exists("/System/Applications/" + os.path.basename(app_path))),
        "running": running, "size_kb": du_kb(app_path),
    }


def list_apps():
    dirs = ["/Applications", os.path.expanduser("~/Applications")]
    apps = []
    for d in dirs:
        try:
            entries = os.listdir(d)
        except OSError:
            continue
        for e in entries:
            if e.endswith(".app"):
                apps.append(app_info(os.path.join(d, e)))
    return sorted(apps, key=lambda a: a["name"].lower())


# ---------- Step3: 残留扫描 ----------

def scan(bid, name):
    fm = os.path.exists
    # key=normcase(realpath) 去重：大小写不敏感文件系统上避免同一路径重复列出
    found = {}  # key -> [rank, set(reasons), display_path]

    def add(path, conf, reason):
        if not fm(path):
            return
        # 大小写不敏感文件系统：realpath 后统一小写作键去重
        # （注意：os.path.normcase 在 POSIX/macOS 上是恒等函数，不能用）
        key = os.path.realpath(path).lower()
        old = found.get(key)
        if old:
            old[0] = max(old[0], RANK[conf])
            old[1].add(reason)
        else:
            found[key] = [RANK[conf], {reason}, path]

    def add_dir(d, match):
        try:
            entries = os.listdir(d)
        except OSError:
            return
        for e in entries:
            hit = match(e)
            if hit:
                add(os.path.join(d, e), hit[0], hit[1])

    home = os.path.expanduser("~")
    lib = os.path.join(home, "Library")
    syslib = "/Library"
    variants = name_variants(name)
    bid_or_name = bid or name

    # 高置信：bundle id 精确
    if bid:
        for sub in ("Caches", "WebKit", "HTTPStorages", "Containers", "Application Scripts"):
            add(os.path.join(lib, sub, bid), HIGH, sub)
        add(os.path.join(lib, "Preferences", bid + ".plist"), HIGH, "Preferences")
        add(os.path.join(lib, "Saved Application State", bid + ".savedState"), HIGH, "Saved Application State")
        add(os.path.join(lib, "Cookies", bid + ".binarycookies"), HIGH, "Cookies")
        add(os.path.join(lib, "Application Support", bid), MEDIUM, "Application Support(bid)")
        add(os.path.join(lib, "Logs", bid), MEDIUM, "Logs(bid)")
        add(os.path.join(syslib, "Application Support", bid), MEDIUM, "Application Support(system,bid)")
        add_dir(os.path.join(lib, "Preferences", "ByHost"),
                lambda e: (HIGH, "Preferences/ByHost") if e.startswith(bid + ".") else None)
        add_dir(os.path.join(lib, "Group Containers"),
                lambda e: (HIGH, "Group Containers") if e == bid or e.startswith("group." + bid) else None)
        base = bid.rsplit(".", 1)[0]  # com.youqu.todesk.mac -> com.youqu.todesk
        for d, reason in ((os.path.join(lib, "LaunchAgents"), "LaunchAgents"),
                          (os.path.join(syslib, "LaunchAgents"), "LaunchAgents(system)"),
                          (os.path.join(syslib, "LaunchDaemons"), "LaunchDaemons")):
            add_dir(d, lambda e, base=base, reason=reason:
                    (HIGH, reason) if e.endswith(".plist") and e.startswith(base + ".") else None)
        # PrivilegedHelperTools：文件名含 vendor.product 前缀或应用名
        add_dir(os.path.join(syslib, "PrivilegedHelperTools"),
                lambda e: (HIGH, "PrivilegedHelperTools")
                if e.startswith(base + ".") or e.lower() == name.lower() else None)

    # 名称匹配
    exact = variants[0] if variants else None
    if exact:
        add(os.path.join(lib, "Application Support", exact), HIGH, "Application Support")
    for n in variants:
        add(os.path.join(lib, "Application Support", n), LOW, "Application Support(变体)")
        add(os.path.join(syslib, "Application Support", n), LOW, "Application Support(system,变体)")
        add(os.path.join(lib, "Caches", n), MEDIUM, "Caches(名称)")
        add(os.path.join(lib, "Logs", n), MEDIUM, "Logs(名称)")
        for d, reason in ((syslib, "PreferencePanes(system)"), (lib, "PreferencePanes")):
            add(os.path.join(d, "PreferencePanes", n + ".prefPane"), MEDIUM, reason)

    # 厂商目录（bid 第二段，如 org.mozilla.firefox -> mozilla）低置信，需人工确认
    if bid and bid.count(".") >= 2:
        vendor = bid.split(".")[1]
        if vendor and vendor.lower() not in {v.lower() for v in variants}:
            add(os.path.join(lib, "Application Support", vendor), LOW, "厂商目录")
            add(os.path.join(syslib, "Application Support", vendor), LOW, "厂商目录(system)")
            add(os.path.join(lib, "Caches", vendor), LOW, "厂商Caches")

    # LaunchAgents/Daemons 按 plist Label 匹配
    def match_label(d, label, conf, reason):
        def m(e):
            if not e.endswith(".plist"):
                return None
            info = read_plist(os.path.join(d, e)) or {}
            l = info.get("Label")
            if isinstance(l, str) and (l == label or l.startswith(label + ".")):
                return (conf, "%s:%s" % (reason, l))
            return None
        add_dir(d, m)

    if bid:
        match_label(os.path.join(lib, "LaunchAgents"), bid, HIGH, "Launch Label")
        match_label(os.path.join(syslib, "LaunchAgents"), bid, HIGH, "Launch Label(system)")
        match_label(os.path.join(syslib, "LaunchDaemons"), bid, HIGH, "Launch Label(daemon)")
        # label 仅含 vendor.product 前缀（bid 去掉末段）→ 中置信
        if "." in bid:
            vp = bid.rsplit(".", 1)[0]
            match_label(os.path.join(lib, "LaunchAgents"), vp, MEDIUM, "Launch Label(vendor)")
            match_label(os.path.join(syslib, "LaunchAgents"), vp, MEDIUM, "Launch Label(vendor,system)")
            match_label(os.path.join(syslib, "LaunchDaemons"), vp, MEDIUM, "Launch Label(vendor,daemon)")

    # pkg 回执
    needle = bid_or_name.lower()
    for pid in run(["/usr/sbin/pkgutil", "--pkgs"]).splitlines():
        if needle in pid.lower():
            for suffix in (".bom", ".plist"):
                add(os.path.join("/var/db/receipts", pid + suffix), MEDIUM, "pkg回执")

    leftovers = []
    for key, (rank, reasons, path) in found.items():
        leftovers.append({
            "path": path, "conf": {0: LOW, 1: MEDIUM, 2: HIGH}[rank],
            "reasons": sorted(reasons), "size_kb": du_kb(path),
        })
    leftovers.sort(key=lambda x: (-RANK[x["conf"]], x["path"].lower()))
    return {"target": name, "bid": bid, "leftovers": leftovers}


# ---------- Step2/4: 卸载执行与安全删除 ----------

TRASH = os.path.expanduser("~/.Trash")


def is_root_owned(path):
    try:
        return os.stat(path).st_uid == 0
    except OSError:
        return False


def trash_path(path):
    """移入废纸篓（同卷 mv，重名自动加序号）。返回 (ok, err, dest)。"""
    name = os.path.basename(path.rstrip("/"))
    dest = os.path.join(TRASH, name)
    i = 1
    while os.path.exists(dest):
        dest = os.path.join(TRASH, "%s %d" % (name, i))
        i += 1
    p = subprocess.run(["/bin/mv", path, dest], capture_output=True, text=True)
    return (p.returncode == 0, p.stderr.strip(), dest)


def admin_shell(cmd):
    """管理员提权执行（弹出系统授权框）。返回 (ok, err)。"""
    esc = cmd.replace("\\", "\\\\").replace('"', '\\"')  # AppleScript 字符串转义
    sc = 'do shell script "%s" with administrator privileges' % esc
    p = subprocess.run(["/usr/bin/osascript", "-e", sc], capture_output=True, text=True)
    return (p.returncode == 0, p.stderr.strip())


def plist_label(path):
    info = read_plist(path) or {}
    l = info.get("Label")
    return l if isinstance(l, str) else None


def build_plan(app, leftovers):
    """生成卸载操作计划，每项含执行所需字段。"""
    plan = []
    # 1) 退出进程
    info = read_plist(os.path.join(app["path"], "Contents", "Info.plist")) or {}
    exe = info.get("CFBundleExecutable")
    if app["running"] and exe:
        plan.append({"kind": "quit", "exe": exe,
                     "detail": "退出进程 %s（AppleScript quit，失败则 killall）" % exe,
                     "needs_admin": False})
    # 2) 卸载 LaunchAgents/Daemons（先 bootout 再删文件）
    for x in leftovers:
        p = x["path"]
        if p.endswith(".plist") and ("LaunchAgents" in p or "LaunchDaemons" in p):
            label = plist_label(p)
            if not label:
                continue
            scope = "system" if "/LaunchDaemons/" in p else "gui/%d" % os.getuid()
            plan.append({"kind": "bootout", "scope": scope, "label": label, "path": p,
                         "detail": "launchctl bootout %s %s" % (scope, label),
                         "needs_admin": scope == "system"})
    # 3) 删除 pkg 回执
    pkg_ids = []
    for x in leftovers:
        p = x["path"]
        if p.startswith("/var/db/receipts/"):
            pid = os.path.basename(p)
            pid = pid[:-4] if pid.endswith(".bom") else pid[:-6]
            if pid not in pkg_ids:
                pkg_ids.append(pid)
    for pid in pkg_ids:
        plan.append({"kind": "forget", "pid": pid,
                     "detail": "pkgutil --forget %s" % pid, "needs_admin": True})
    # 4) 移入废纸篓：主包 + 残留
    plan.append({"kind": "trash", "path": app["path"],
                 "detail": "移入废纸篓: %s" % app["path"], "needs_admin": False})
    for x in leftovers:
        if x["path"].startswith("/var/db/receipts/"):
            continue  # 回执由 pkgutil --forget 处理
        plan.append({"kind": "trash", "path": x["path"],
                     "detail": "移入废纸篓: %s" % x["path"],
                     "needs_admin": is_root_owned(x["path"])})
    return plan


def cmd_uninstall(arg, confirm, skip_low):
    app = None
    if arg.endswith(".app") and os.path.exists(arg):
        app = app_info(arg)
    else:
        for a in list_apps():
            if a["bid"] == arg:
                app = a
                break
    if app is None:
        print("未找到应用: %s（可先 list 查看）" % arg)
        return
    if app["system"]:
        print("SIP 保护的系统应用，无法卸载。")
        return
    leftovers = scan(app["bid"], app["name"])["leftovers"]
    if skip_low:
        leftovers = [x for x in leftovers if x["conf"] != LOW]

    print("卸载计划: %s  (bundle id: %s)\n" % (app["name"], app["bid"] or "-"))
    plan = build_plan(app, leftovers)
    for i, step in enumerate(plan, 1):
        admin = " [需管理员]" if step["needs_admin"] else ""
        print("  %2d. %s%s" % (i, step["detail"], admin))
    print("\n残留 %d 项，合计 %.1f MB" % (len(leftovers),
          sum(x["size_kb"] or 0 for x in leftovers) / 1024))

    if not confirm:
        print("[干跑模式] 未执行任何操作。确认后加 --confirm 实际执行。")
        return

    # ---- 实际执行（--confirm）----
    fails = []
    allowed = ("/Applications/", os.path.expanduser("~/Applications/"),
               os.path.expanduser("~/Library/"), "/Library/")
    for step in plan:
        try:
            if step["kind"] == "quit":
                p = subprocess.run(["/usr/bin/osascript", "-e",
                                    'tell application "%s" to quit' % step["exe"]],
                                   capture_output=True, text=True, timeout=15)
                if p.returncode != 0:
                    subprocess.run(["/usr/bin/killall", step["exe"]], capture_output=True)
            elif step["kind"] == "bootout":
                if step["needs_admin"]:
                    ok, err = admin_shell("launchctl bootout %s %s" % (step["scope"], step["label"]))
                    if not ok:
                        fails.append((step["detail"], err))
                else:
                    p = subprocess.run(["/bin/launchctl", "bootout", step["scope"], step["label"]],
                                       capture_output=True, text=True)
                    # 未加载/未运行的服务会报 "Could not find service" 或 "Boot-out failed"，属预期
                    if p.returncode != 0 and "Could not find service" not in p.stderr \
                            and "Boot-out failed" not in p.stderr:
                        fails.append((step["detail"], p.stderr.strip()))
            elif step["kind"] == "forget":
                ok, err = admin_shell("pkgutil --forget %s" % step["pid"])
                if not ok:
                    fails.append((step["detail"], err))
            elif step["kind"] == "trash":
                path = step["path"]
                if not path.startswith(allowed):
                    fails.append((step["detail"], "路径不在白名单，已跳过"))
                    continue
                if step["needs_admin"]:
                    ok, err = admin_shell('rm -rf -- "%s"' % path.replace('"', '\\"'))
                    if not ok:
                        fails.append((step["detail"], err))
                else:
                    ok, err, _ = trash_path(path)
                    if not ok:
                        fails.append((step["detail"], err))
        except Exception as e:
            fails.append((step["detail"], str(e)))
    print("\n执行完成。失败 %d 项:" % len(fails))
    for detail, err in fails:
        print("  - %s | %s" % (detail, err))


# ---------- CLI ----------

def pad(s, w):
    return s if len(s) >= w else s + " " * (w - len(s))


def cmd_list():
    print("名称                        版本         来源        大小      状态     路径")
    for a in list_apps():
        flags = []
        if a["running"]:
            flags.append("运行中")
        if a["system"]:
            flags.append("SIP")
        size = "-" if a["size_kb"] is None else ("0 MB" if a["size_kb"] == 0 else "%.0f MB" % (a["size_kb"] / 1024))
        print("%s %s %s %s %s %s" % (
            pad(a["name"], 24), pad(a["version"] or "-", 12), pad(a["source"], 11),
            pad(size, 8), pad(",".join(flags), 6), a["path"]))


def cmd_scan(arg):
    bid, name = None, arg
    if arg.endswith(".app") and os.path.exists(arg):
        info = read_plist(os.path.join(arg, "Contents", "Info.plist")) or {}
        bid = info.get("CFBundleIdentifier")
        name = info.get("CFBundleDisplayName") or info.get("CFBundleName") \
            or os.path.basename(arg)[:-4]
    elif "." in arg:
        bid = arg
        # 已安装则解析出显示名，否则用 bid 本身
        for a in list_apps():
            if a["bid"] == arg:
                name = a["name"]
                break
    result = scan(bid, name)
    print("目标: %s   bundle id: %s\n" % (name, bid or "-"))
    if not result["leftovers"]:
        print("未发现残留。")
        return
    for conf in (HIGH, MEDIUM, LOW):
        items = [x for x in result["leftovers"] if x["conf"] == conf]
        if not items:
            continue
        print("== %s ==" % CONF_TITLE[conf])
        for x in items:
            if x["size_kb"] is None:
                size = "- (需管理员)"
            elif x["size_kb"] == 0:
                size = "0.0 MB"
            else:
                size = "%.1f MB" % (x["size_kb"] / 1024)
            print("  [%s] %s  (%s)" % (",".join(x["reasons"]), x["path"], size))
        print("")
    total = sum(x["size_kb"] or 0 for x in result["leftovers"])
    print("共 %d 项，合计 %.1f MB" % (len(result["leftovers"]), total / 1024))


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 1
    if args[0] == "list":
        cmd_list()
    elif args[0] == "scan" and len(args) > 1:
        cmd_scan(args[1])
    elif args[0] == "uninstall" and len(args) > 1:
        cmd_uninstall(args[1], "--confirm" in args, "--skip-low" in args)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
