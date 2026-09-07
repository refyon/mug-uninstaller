import Foundation

public enum Confidence: Int, Comparable {
    case low = 0, medium = 1, high = 2
    public static func < (l: Confidence, r: Confidence) -> Bool { l.rawValue < r.rawValue }
}

public struct Leftover {
    public let path: String
    public let confidence: Confidence
    /// 命中原因（如 "Preferences"、"Launch Label:com.x.y"）
    public let reasons: [String]
    public let sizeKB: Int64
}

public struct ScanResult {
    public let target: String
    public let bundleID: String?
    public let leftovers: [Leftover]
    public var totalKB: Int64 { leftovers.reduce(0) { $0 + max(0, $1.sizeKB) } }
}

/// 残留扫描引擎。规则与 prototype/uninstaller_cli.py 逐条对应（含实测修正）：
/// - 大小写不敏感文件系统去重：键 = realpath.lowercased()（macOS 无 normcase）
/// - 守护进程 label 常为 bid 的 vendor.product 前缀（com.youqu.todesk.* ≠ bid com.youqu.todesk.mac）
/// - PrivilegedHelperTools 需目录枚举（helper 名 ≠ 应用名）
public enum LeftoverScanner {
    /// 扫描一个应用的全部残留。bid 可能为 nil（无 bundle id 的怪异 app）。
    public static func scan(bundleID bid: String?, appName name: String) -> ScanResult {
        let fm = FileManager.default
        // key -> (conf, reasons, displayPath)
        var found: [String: (Confidence, Set<String>, String)] = [:]

        func add(_ path: String, _ conf: Confidence, _ reason: String) {
            guard fm.fileExists(atPath: path) else { return }
            let key = URL(fileURLWithPath: path).resolvingSymlinksInPath().path.lowercased()
            if let old = found[key] {
                found[key] = (max(old.0, conf), old.1.union([reason]), old.2)
            } else {
                found[key] = (conf, [reason], path)
            }
        }
        /// 枚举目录，对每个条目做匹配。
        func addDir(_ dir: String, _ match: (String) -> (Confidence, String)?) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for entry in entries {
                if let hit = match(entry) { add(dir + "/" + entry, hit.0, hit.1) }
            }
        }

        let home = NSHomeDirectory()
        let lib = home + "/Library"
        let sysLib = "/Library"
        let variants = Support.nameVariants([name])
        let bidOrName = bid ?? name

        // ---- 高置信：bundle id 精确 ----
        if let b = bid {
            let base = b.split(separator: ".").dropLast().joined(separator: ".")
            for sub in ["Caches", "WebKit", "HTTPStorages", "Containers", "Application Scripts"] {
                add("\(lib)/\(sub)/\(b)", .high, sub)
            }
            add("\(lib)/Preferences/\(b).plist", .high, "Preferences")
            add("\(lib)/Saved Application State/\(b).savedState", .high, "Saved Application State")
            add("\(lib)/Cookies/\(b).binarycookies", .high, "Cookies")
            add("\(lib)/Application Support/\(b)", .medium, "Application Support(bid)")
            add("\(lib)/Logs/\(b)", .medium, "Logs(bid)")
            add("\(sysLib)/Application Support/\(b)", .medium, "Application Support(system,bid)")
            addDir("\(lib)/Preferences/ByHost") { entry in
                entry.hasPrefix(b + ".") ? (.high, "Preferences/ByHost") : nil
            }
            addDir("\(lib)/Group Containers") { entry in
                (entry == b || entry.hasPrefix("group." + b)) ? (.high, "Group Containers") : nil
            }
            for (d, reason) in [("\(lib)/LaunchAgents", "LaunchAgents"),
                                ("\(sysLib)/LaunchAgents", "LaunchAgents(system)"),
                                ("\(sysLib)/LaunchDaemons", "LaunchDaemons")] {
                addDir(d) { entry in
                    entry.hasSuffix(".plist") && entry.hasPrefix(base + ".") ? (.high, reason) : nil
                }
            }
            addDir("\(sysLib)/PrivilegedHelperTools") { entry in
                (entry.hasPrefix(base + ".") || entry.lowercased() == name.lowercased())
                    ? (.high, "PrivilegedHelperTools") : nil
            }
        }

        // ---- 名称匹配（精确=high，变体=low/medium）----
        if let exact = variants.first {
            add("\(lib)/Application Support/\(exact)", .high, "Application Support")
        }
        for n in variants {
            add("\(lib)/Application Support/\(n)", .low, "Application Support(变体)")
            add("\(sysLib)/Application Support/\(n)", .low, "Application Support(system,变体)")
            add("\(lib)/Caches/\(n)", .medium, "Caches(名称)")
            add("\(lib)/Logs/\(n)", .medium, "Logs(名称)")
            add("\(sysLib)/PreferencePanes/\(n).prefPane", .medium, "PreferencePanes")
            add("\(lib)/PreferencePanes/\(n).prefPane", .medium, "PreferencePanes")
        }

        // ---- 厂商目录（bid 第二段，如 org.mozilla.firefox -> mozilla）低置信 ----
        if let b = bid, b.split(separator: ".").count >= 3 {
            let vendor = String(b.split(separator: ".")[1])
            if !vendor.isEmpty && !variants.contains(where: { $0.lowercased() == vendor.lowercased() }) {
                add("\(lib)/Application Support/\(vendor)", .low, "厂商目录")
                add("\(sysLib)/Application Support/\(vendor)", .low, "厂商目录(system)")
                add("\(lib)/Caches/\(vendor)", .low, "厂商Caches")
            }
        }

        // ---- LaunchAgents/Daemons 按 plist Label 匹配（更可靠）----
        func matchLabel(_ dir: String, _ label: String, _ conf: Confidence, _ reason: String) {
            addDir(dir) { file in
                guard file.hasSuffix(".plist") else { return nil }
                guard let dict = Support.readPlist(at: URL(fileURLWithPath: dir + "/" + file)),
                      let l = dict["Label"] as? String else { return nil }
                if l == label || l.hasPrefix(label + ".") { return (conf, "\(reason):\(l)") }
                return nil
            }
        }
        if let b = bid {
            matchLabel("\(lib)/LaunchAgents", b, .high, "Launch Label")
            matchLabel("\(sysLib)/LaunchAgents", b, .high, "Launch Label(system)")
            matchLabel("\(sysLib)/LaunchDaemons", b, .high, "Launch Label(daemon)")
            if b.contains(".") {
                let vp = b.split(separator: ".").dropLast().joined(separator: ".")
                matchLabel("\(lib)/LaunchAgents", vp, .medium, "Launch Label(vendor)")
                matchLabel("\(sysLib)/LaunchAgents", vp, .medium, "Launch Label(vendor,system)")
                matchLabel("\(sysLib)/LaunchDaemons", vp, .medium, "Launch Label(vendor,daemon)")
            }
        }

        // ---- pkg 回执 ----
        if let ids = Support.run("/usr/sbin/pkgutil", ["--pkgs"]) {
            let needle = bidOrName.lowercased()
            for id in ids.split(separator: "\n").map(String.init)
                where id.lowercased().contains(needle) {
                add("/var/db/receipts/\(id).bom", .medium, "pkg回执")
                add("/var/db/receipts/\(id).plist", .medium, "pkg回执")
            }
        }

        let items = found.values.map { v in
            Leftover(path: v.2,
                     confidence: v.0,
                     reasons: v.1.sorted(),
                     sizeKB: Support.sizeKB(of: URL(fileURLWithPath: v.2)))
        }.sorted { lhs, rhs in
            lhs.confidence != rhs.confidence ? lhs.confidence > rhs.confidence : lhs.path < rhs.path
        }
        return ScanResult(target: name, bundleID: bid, leftovers: items)
    }
}
