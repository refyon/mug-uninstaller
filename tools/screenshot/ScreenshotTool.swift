// README 截图生成器：mock 数据 + ImageRenderer 离屏渲染 → PNG。
// 无需屏幕录制权限；仅在工具进程内启用 mock 开关，不影响正式应用。
import AppKit
import SwiftUI
import MugUninstallerKit

@main
struct ScreenshotTool {
    @MainActor
    static func main() {
        AppScanner.isMocking = true
        LeftoverScanner.isMocking = true
        try? FileManager.default.createDirectory(atPath: "docs/screenshots",
                                                 withIntermediateDirectories: true)

        // 1) 主窗口（默认隐藏系统应用）
        let apps = AppScanner.scan()
        render(AppListView(initialApps: apps).frame(width: 800, height: 520),
               to: "docs/screenshots/main.png")

        // 2) 残留确认页（用列表中的 Chrome 演示高/中/低置信度）
        if let chrome = apps.first(where: { $0.bundleID == "com.google.Chrome" }) {
            let leftovers = LeftoverScanner.scan(bundleID: chrome.bundleID,
                                                 appName: chrome.displayName)
            render(LeftoverView(app: chrome, initialResult: leftovers)
                    .frame(width: 720, height: 520),
                   to: "docs/screenshots/uninstall.png")
        }
        print("OK: docs/screenshots/main.png + uninstall.png")
    }

    @MainActor
    static func render<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.render { _, _ in }
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fputs("渲染失败: \(path)\n", stderr)
            exit(1)
        }
        try! png.write(to: URL(fileURLWithPath: path))
        print("已生成 \(path)（\(img.size.width)x\(img.size.height)）")
    }
}
