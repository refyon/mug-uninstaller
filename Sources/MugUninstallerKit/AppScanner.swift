import Foundation
import AppKit

public struct AppInfo: Identifiable {
    public let path: URL
    public let bundleID: String?
    public let displayName: String
    public let version: String?
    /// 安装来源：mas / brew-cask / pkg / ?
    public let source: String
    /// /System/Applications 下（SIP 保护，不可删）
    public let isSystemApp: Bool
    public let isRunning: Bool
    public let sizeKB: Int64
    /// CFBundleExecutable（用于退出进程）
    public let executableName: String?
    /// 自定义图标（mock 数据用首字母图标；真实应用为 nil，走 NSWorkspace）
    public let icon: NSImage?
    public var id: URL { path }
}

public enum AppScanner {
    /// 截图/mock 模式开关（仅工具进程置 true，正式应用不受影响）
    public static var isMocking = false

    /// 扫描 /Applications 与 ~/Applications。
    public static func scan() -> [AppInfo] {
        if isMocking { return mockApps() }
        let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        var pkgIDs: Set<String>? = nil
        var apps: [AppInfo] = []

        for dir in dirs {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir + "/" + entry)
                guard let info = Support.readPlist(at: url.appendingPathComponent("Contents/Info.plist")) else { continue }
                let bid = info["CFBundleIdentifier"] as? String
                let exe = info["CFBundleExecutable"] as? String
                let name = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? String(entry.dropLast(4))
                let version = (info["CFBundleShortVersionString"] as? String)
                    ?? (info["CFBundleVersion"] as? String)
                let resolved = url.resolvingSymlinksInPath().path

                var source = "?"
                if FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path) {
                    source = "mas"
                } else if resolved.contains("/Caskroom/") {
                    source = "brew-cask"
                } else {
                    if pkgIDs == nil {
                        pkgIDs = Set((Support.run("/usr/sbin/pkgutil", ["--pkgs"]) ?? "")
                            .split(separator: "\n").map(String.init))
                    }
                    let needle = (bid ?? name).lowercased()
                    if let ids = pkgIDs, ids.contains(where: { $0.lowercased().contains(needle) }) {
                        source = "pkg"
                    }
                }

                // firmlink：/Applications/Safari.app realpath 指向 Cryptex 内 /System/Applications
                let isSystem = resolved.contains("/System/Applications")
                let isRunning = (bid != nil) && NSWorkspace.shared.runningApplications
                    .contains { $0.bundleIdentifier == bid }
                apps.append(AppInfo(
                    path: url,
                    bundleID: bid,
                    displayName: name,
                    version: version,
                    source: source,
                    isSystemApp: isSystem,
                    isRunning: isRunning,
                    sizeKB: Support.sizeKB(of: url),
                    executableName: exe,
                    icon: nil))
            }
        }
        return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public static func find(byBundleID bid: String) -> AppInfo? {
        scan().first { $0.bundleID == bid }
    }

    // MARK: - Mock 数据（README 截图用：脱敏，虚构流行应用，首字母图标）

    static func letterIcon(_ letter: String, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let s = NSAttributedString(string: letter, attributes: attrs)
            let size = s.size()
            s.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
    }

    static func mockApp(_ name: String, _ bid: String, _ version: String, _ source: String,
                        _ sizeKB: Int64, running: Bool, letter: String, color: NSColor) -> AppInfo {
        AppInfo(path: URL(fileURLWithPath: "/Applications/\(name).app"),
                bundleID: bid,
                displayName: name,
                version: version,
                source: source,
                isSystemApp: false,
                isRunning: running,
                sizeKB: sizeKB,
                executableName: name.lowercased(),
                icon: letterIcon(letter, color: color))
    }

    static func mockApps() -> [AppInfo] {
        [
            mockApp("Chrome", "com.google.Chrome", "126.0.6478.127", "?", 430_080,
                    running: true, letter: "C", color: .systemRed),
            mockApp("Slack", "com.tinyspeck.slack", "4.39.95", "mas", 245_760,
                    running: false, letter: "S", color: NSColor(srgbRed: 0.38, green: 0.12, blue: 0.44, alpha: 1)),
            mockApp("Zoom", "us.zoom.xos", "6.1.1", "pkg", 310_272,
                    running: false, letter: "Z", color: .systemBlue),
            mockApp("Visual Studio Code", "com.microsoft.VSCode", "1.90.2", "brew-cask", 512_000,
                    running: false, letter: "V", color: NSColor(srgbRed: 0.0, green: 0.48, blue: 0.80, alpha: 1)),
            mockApp("Docker", "com.docker.docker", "4.31.1", "brew-cask", 1_884_160,
                    running: true, letter: "D", color: NSColor(srgbRed: 0.11, green: 0.39, blue: 0.93, alpha: 1)),
            mockApp("1Password", "com.1password.1password", "8.10.33", "mas", 221_184,
                    running: false, letter: "1", color: NSColor(srgbRed: 0.04, green: 0.18, blue: 0.36, alpha: 1)),
            mockApp("Notion", "notion.id", "3.9.2", "mas", 186_368,
                    running: false, letter: "N", color: NSColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1)),
        ]
    }
}
