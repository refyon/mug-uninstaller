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
    public var id: URL { path }
}

public enum AppScanner {
    /// 扫描 /Applications 与 ~/Applications。
    public static func scan() -> [AppInfo] {
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
                    executableName: exe))
            }
        }
        return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public static func find(byBundleID bid: String) -> AppInfo? {
        scan().first { $0.bundleID == bid }
    }
}
