import Foundation
import MugUninstallerKit

func pad(_ s: String, _ w: Int) -> String {
    s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
}

func usage() -> Never {
    print("""
    mug-uninstaller-cli — macOS 卸载工具原型
    用法:
      mug-uninstaller-cli list                     列出已装应用
      mug-uninstaller-cli scan <app路径|bundle id>  扫描某应用的残留文件
      mug-uninstaller-cli uninstall <app|bundle id> [--confirm] 卸载（默认干跑）
    """)
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 1 else { usage() }

switch args[0] {
case "list":
    print("名称                      版本       来源        大小      状态    路径")
    for app in AppScanner.scan() {
        var flags: [String] = []
        if app.isRunning { flags.append("运行中") }
        if app.isSystemApp { flags.append("SIP") }
        let size = app.sizeKB > 0 ? String(format: "%.0f MB", Double(app.sizeKB) / 1024) : "?"
        print("\(pad(app.displayName, 25))\(pad(app.version ?? "-", 10))\(pad(app.source, 10))\(pad(size, 9))\(pad(flags.joined(separator: ","), 8))\(app.path.path)")
    }

case "scan":
    guard args.count >= 2 else { usage() }
    let arg = args[1]
    var bid: String?
    var name = arg

    if arg.hasSuffix(".app"), FileManager.default.fileExists(atPath: arg) {
        let url = URL(fileURLWithPath: arg)
        if let info = Support.readPlist(at: url.appendingPathComponent("Contents/Info.plist")) {
            bid = info["CFBundleIdentifier"] as? String
            name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? String(url.lastPathComponent.dropLast(4))
        }
    } else if let app = AppScanner.find(byBundleID: arg) {
        bid = app.bundleID
        name = app.displayName
    } else {
        bid = arg.contains(".") ? arg : nil
    }

    let result = LeftoverScanner.scan(bundleID: bid, appName: name)
    print("目标: \(name)   bundle id: \(bid ?? "-")\n")
    if result.leftovers.isEmpty {
        print("未发现残留。")
        exit(0)
    }
    let order: [(Confidence, String)] = [(.high, "高置信(可安全删)"), (.medium, "中置信(建议确认)"), (.low, "低置信(需人工确认)")]
    for (conf, title) in order {
        let items = result.leftovers.filter { $0.confidence == conf }
        guard !items.isEmpty else { continue }
        print("== \(title) ==")
        for it in items {
            let size: String
            if it.sizeKB < 0 { size = "- (需管理员)" }
            else if it.sizeKB == 0 { size = "0.0 MB" }
            else { size = String(format: "%.1f MB", Double(it.sizeKB) / 1024) }
            print("  [\(it.reasons.joined(separator: ","))] \(it.path)  (\(size))")
        }
        print("")
    }
    print("共 \(result.leftovers.count) 项，合计 \(String(format: "%.1f MB", Double(result.totalKB) / 1024))")

case "uninstall":
    guard args.count >= 2 else { usage() }
    let confirm = args.contains("--confirm")
    let arg = args[1]
    var app: AppInfo?
    if arg.hasSuffix(".app") {
        app = AppScanner.scan().first { $0.path.path == arg }
    } else {
        app = AppScanner.find(byBundleID: arg)
    }
    guard let app = app else { print("未找到应用: \(arg)（可先 list 查看）"); exit(1) }
    guard !app.isSystemApp else { print("SIP 保护的系统应用，无法卸载。"); exit(1) }

    let result = LeftoverScanner.scan(bundleID: app.bundleID, appName: app.displayName)
    print("卸载计划: \(app.displayName)  (bundle id: \(app.bundleID ?? "-"))\n")
    let plan = UninstallEngine.buildPlan(app: app, leftovers: result.leftovers)
    for (i, step) in plan.enumerated() {
        print(String(format: " %2d. %@%@", i + 1, step.detail as NSString,
                     step.needsAdmin ? " [需管理员]" : ""))
    }
    print(String(format: "\n残留 %d 项，合计 %.1f MB",
                 result.leftovers.count, Double(result.totalKB) / 1024))
    if !confirm {
        print("[干跑模式] 未执行任何操作。确认后加 --confirm 实际执行。")
        exit(0)
    }
    let failures = UninstallEngine.execute(plan)
    print("\n执行完成。失败 \(failures.count) 项:")
    for f in failures { print("  - \(f.0) | \(f.1)") }

default:
    usage()
}
