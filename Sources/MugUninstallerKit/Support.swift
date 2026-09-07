import Foundation

public enum Support {
    /// 读取 plist（兼容 XML / 二进制格式）。
    public static func readPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var format: PropertyListSerialization.PropertyListFormat = .binary
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: &format)) as? [String: Any]
    }

    /// 目录/文件占用大小（KB），走 `du -sk`：快、不跟随符号链接。失败返回 -1。
    public static func sizeKB(of url: URL) -> Int64 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", url.resolvingSymlinksInPath().path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0,
                  let first = String(data: data, encoding: .utf8)?
                    .split(separator: "\t").first, let kb = Int64(first) else { return -1 }
            return kb
        } catch { return -1 }
    }

    /// 运行外部命令并返回 stdout（先读完再 wait，避免管道缓冲死锁）。
    public static func run(_ tool: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }

    /// 名称变体：去空格 / 空格换 - 或 _ / 全小写，用于模糊匹配兜底。
    public static func nameVariants(_ bases: [String]) -> [String] {
        var result = Set<String>()
        for base in bases {
            let b = base.trimmingCharacters(in: .whitespaces)
            guard !b.isEmpty else { continue }
            result.insert(b)
            result.insert(b.replacingOccurrences(of: " ", with: ""))
            result.insert(b.replacingOccurrences(of: " ", with: "-"))
            result.insert(b.replacingOccurrences(of: " ", with: "_"))
            result.insert(b.lowercased())
        }
        return result.sorted()  // 排序保证原始名称优先（大小写敏感序）
    }
}
