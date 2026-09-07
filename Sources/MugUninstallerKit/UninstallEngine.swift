import Foundation
import AppKit

/// 卸载执行计划中的一个步骤（与 prototype/uninstaller_cli.py 的 build_plan 对应）。
public struct UninstallStep: Identifiable {
    public enum Kind: String { case quit, bootout, forgetReceipt, trash }
    public let id = UUID()
    public let kind: Kind
    public let detail: String
    /// root 文件 / system 域 bootout / pkgutil --forget 需要管理员
    public let needsAdmin: Bool
    public var path: String?
    public var scope: String?      // bootout: gui/<uid> | system
    public var label: String?      // bootout 目标 Label
    public var receiptID: String?  // pkgutil --forget 目标
    public var executable: String? // quit 目标

    public init(kind: Kind, detail: String, needsAdmin: Bool,
                path: String? = nil, scope: String? = nil, label: String? = nil,
                receiptID: String? = nil, executable: String? = nil) {
        self.kind = kind
        self.detail = detail
        self.needsAdmin = needsAdmin
        self.path = path
        self.scope = scope
        self.label = label
        self.receiptID = receiptID
        self.executable = executable
    }
}

/// Step2/4：卸载执行与安全删除。
/// 原则：先退进程 → 先 bootout 再删 plist → pkgutil --forget → 全部移入废纸篓（可恢复）；
/// root 文件按单次操作走管理员授权；删除目标限制在白名单目录内。
public enum UninstallEngine {
    /// 生成执行计划（不执行）。顺序：quit → bootout → forget → trash。
    public static func buildPlan(app: AppInfo, leftovers: [Leftover]) -> [UninstallStep] {
        var plan: [UninstallStep] = []

        // 1) 退出进程
        if app.isRunning, let exe = app.executableName {
            plan.append(UninstallStep(kind: .quit, detail: "退出进程 \(exe)",
                                      needsAdmin: false, executable: exe))
        }

        // 2) LaunchAgents/Daemons 先 bootout
        for x in leftovers
            where x.path.hasSuffix(".plist")
                && (x.path.contains("LaunchAgents") || x.path.contains("LaunchDaemons")) {
            guard let label = plistLabel(x.path) else { continue }
            let scope = x.path.contains("/LaunchDaemons/") ? "system" : "gui/\(getuid())"
            plan.append(UninstallStep(kind: .bootout,
                                      detail: "launchctl bootout \(scope) \(label)",
                                      needsAdmin: scope == "system",
                                      path: x.path, scope: scope, label: label))
        }

        // 3) pkg 回执
        var receiptIDs = Set<String>()
        for x in leftovers where x.path.hasPrefix("/var/db/receipts/") {
            var pid = (x.path as NSString).lastPathComponent
            if pid.hasSuffix(".bom") { pid = String(pid.dropLast(4)) }
            else if pid.hasSuffix(".plist") { pid = String(pid.dropLast(6)) }
            receiptIDs.insert(pid)
        }
        for pid in receiptIDs.sorted() {
            plan.append(UninstallStep(kind: .forgetReceipt, detail: "pkgutil --forget \(pid)",
                                      needsAdmin: true, receiptID: pid))
        }

        // 4) 移入废纸篓：主包 + 残留
        plan.append(UninstallStep(kind: .trash, detail: "移入废纸篓: \(app.path.path)",
                                  needsAdmin: false, path: app.path.path))
        for x in leftovers where !x.path.hasPrefix("/var/db/receipts/") {
            plan.append(UninstallStep(kind: .trash, detail: "移入废纸篓: \(x.path)",
                                      needsAdmin: isRootOwned(x.path), path: x.path))
        }
        return plan
    }

    /// 执行计划，返回失败项 (步骤描述, 错误)。root 文件删除会弹出系统授权框。
    public static func execute(_ steps: [UninstallStep]) -> [(String, String)] {
        var failures: [(String, String)] = []
        let allowedPrefixes = ["/Applications/",
                               NSHomeDirectory() + "/Applications/",
                               NSHomeDirectory() + "/Library/",
                               "/Library/"]

        for step in steps {
            do {
                switch step.kind {
                case .quit:
                    guard let exe = step.executable else { continue }
                    let apple = Process()
                    apple.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    apple.arguments = ["-e", "tell application \"\(exe)\" to quit"]
                    try? apple.run()
                    apple.waitUntilExit()
                    if apple.terminationStatus != 0 {
                        let k = Process()
                        k.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                        k.arguments = [exe]
                        try? k.run()
                        k.waitUntilExit()
                    }

                case .bootout:
                    guard let scope = step.scope, let label = step.label else { continue }
                    if step.needsAdmin {
                        let (ok, err) = adminShell("launchctl bootout \(scope) \(label)")
                        if !ok { failures.append((step.detail, err)) }
                    } else {
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                        p.arguments = ["bootout", scope, label]
                        let errPipe = Pipe()
                        p.standardError = errPipe
                        try p.run()
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        p.waitUntilExit()
                        if p.terminationStatus != 0 {
                            let err = String(data: errData, encoding: .utf8) ?? ""
                            // 未加载/未运行的服务 bootout 会报这些错，属预期（目标就是不运行）
                            if !err.contains("Could not find service")
                                && !err.contains("Boot-out failed") {
                                failures.append((step.detail,
                                                 err.trimmingCharacters(in: .whitespacesAndNewlines)))
                            }
                        }
                    }

                case .forgetReceipt:
                    guard let pid = step.receiptID else { continue }
                    let (ok, err) = adminShell("pkgutil --forget \(pid)")
                    if !ok { failures.append((step.detail, err)) }

                case .trash:
                    guard let path = step.path else { continue }
                    guard allowedPrefixes.contains(where: { path.hasPrefix($0) }) else {
                        failures.append((step.detail, "路径不在白名单，已跳过"))
                        continue
                    }
                    if step.needsAdmin {
                        let q = path.replacingOccurrences(of: "\"", with: "\\\"")
                        let (ok, err) = adminShell("rm -rf -- \"\(q)\"")
                        if !ok { failures.append((step.detail, err)) }
                    } else if FileManager.default.fileExists(atPath: path) {
                        // CLI/裸进程环境 recycle 可能空转（实测返回 Void 且不移动），
                        // 因此 recycle 后校验，仍在则退化为 mv 进废纸篓。
                        NSWorkspace.shared.recycle([URL(fileURLWithPath: path)])
                        if FileManager.default.fileExists(atPath: path) {
                            if !moveToTrash(path) {
                                failures.append((step.detail, "移入废纸篓失败"))
                            }
                        }
                    }
                    // 目标已不存在 → 幂等跳过（重试场景）
                }
            } catch {
                failures.append((step.detail, String(describing: error)))
            }
        }
        return failures
    }

    // MARK: - helpers

    /// 移入废纸篓（同卷 mv，重名自动加序号）。跨卷或失败返回 false。
    static func moveToTrash(_ path: String) -> Bool {
        let fm = FileManager.default
        let trash = NSHomeDirectory() + "/.Trash"
        let name = (path as NSString).lastPathComponent
        var dest = trash + "/" + name
        var i = 1
        while fm.fileExists(atPath: dest) {
            dest = "\(trash)/\(name) \(i)"
            i += 1
        }
        do {
            try fm.moveItem(atPath: path, toPath: dest)
            return true
        } catch {
            return false
        }
    }

    static func isRootOwned(_ path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        return (attrs[.ownerAccountID] as? NSNumber)?.intValue == 0
    }

    static func plistLabel(_ path: String) -> String? {
        guard let dict = Support.readPlist(at: URL(fileURLWithPath: path)),
              let label = dict["Label"] as? String else { return nil }
        return label
    }

    /// 管理员提权执行（osascript，弹出系统授权框）。返回 (成功, 错误)。
    static func adminShell(_ cmd: String) -> (Bool, String) {
        let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(esc)\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let errPipe = Pipe()
        p.standardError = errPipe
        do {
            try p.run()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let err = String(data: errData, encoding: .utf8) ?? ""
            return (p.terminationStatus == 0, err.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, String(describing: error))
        }
    }
}
