// 应用图标生成器 v2：accent 绿 squircle 底（微渐层）+ 米白马克杯（杯身+右侧把手）+ 两缕热气。
// 输出 Resources/AppIcon.icns + .build/icon-preview.png。可随时改色板/形状重生成。
import AppKit

let iconsetDir = ".build/icon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

// 色板（DESIGN.md 色系：accent 绿 + 中性米白；仅作图标品牌面，UI 仍用 T.* tokens）
let accentTop = NSColor(srgbRed: 0x35 / 255.0, green: 0xA8 / 255.0, blue: 0x60 / 255.0, alpha: 1)
let accentBottom = NSColor(srgbRed: 0x18 / 255.0, green: 0x6C / 255.0, blue: 0x34 / 255.0, alpha: 1)
let cream = NSColor(srgbRed: 0xFF / 255.0, green: 0xF8 / 255.0, blue: 0xE9 / 255.0, alpha: 1)
let shadow = NSColor.black.withAlphaComponent(0.10)
let steam = NSColor.white.withAlphaComponent(0.85)

func mugHandle(_ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    // 半圆把手：圆心在杯身右缘，经 0°（最右）扫过 → 两个端点恰好落在杯身右缘
    p.appendArc(withCenter: NSPoint(x: 0.62 * w, y: 0.50 * h),
                radius: 0.15 * w, startAngle: -90, endAngle: 90, clockwise: false)
    p.lineWidth = 0.06 * w
    p.lineCapStyle = .round
    return p
}

func steamPath(_ baseX: CGFloat, _ baseY: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.lineWidth = 0.026 * w
    p.lineCapStyle = .round
    p.move(to: NSPoint(x: baseX, y: baseY))
    p.curve(to: NSPoint(x: baseX + 0.012 * w, y: baseY + 0.05 * h),
            controlPoint1: NSPoint(x: baseX - 0.02 * w, y: baseY + 0.02 * h),
            controlPoint2: NSPoint(x: baseX + 0.04 * w, y: baseY + 0.035 * h))
    p.curve(to: NSPoint(x: baseX, y: baseY + 0.10 * h),
            controlPoint1: NSPoint(x: baseX - 0.016 * w, y: baseY + 0.068 * h),
            controlPoint2: NSPoint(x: baseX + 0.02 * w, y: baseY + 0.082 * h))
    return p
}

func makeIcon(size: Int) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let w = rect.width
        let h = rect.height
        // 1) 背景 squircle：四周留透明边距（不顶满画布），绿渐层
        let inset = 0.07 * w
        let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset,
                                                  width: w - 2 * inset, height: h - 2 * inset),
                              xRadius: 0.2237 * (w - 2 * inset),
                              yRadius: 0.2237 * (h - 2 * inset))
        bg.addClip()
        NSGradient(starting: accentTop, ending: accentBottom)?.draw(in: bg, angle: -90)
        // 2) 落影
        shadow.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0.26 * w, y: 0.195 * h, width: 0.40 * w, height: 0.075 * h)).fill()
        // 3) 杯身（放大）
        cream.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0.22 * w, y: 0.285 * h, width: 0.40 * w, height: 0.435 * h),
                     xRadius: 0.08 * w, yRadius: 0.08 * h).fill()
        // 4) 把手（盖过杯身右缘，与杯身粘连）
        cream.setStroke()
        mugHandle(w, h).stroke()
        // 5) 热气两缕
        steam.setStroke()
        steamPath(0.36 * w, 0.735 * h, w, h).stroke()
        steamPath(0.47 * w, 0.735 * h, w, h).stroke()
        return true
    }
}

func pngData(_ image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

for (size, name) in sizes {
    guard let png = pngData(makeIcon(size: size)) else {
        fputs("渲染失败: \(name)\n", stderr)
        exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
}

if let png = pngData(makeIcon(size: 512)) {
    try? png.write(to: URL(fileURLWithPath: ".build/icon-preview.png"))
}

try? fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconsetDir, "-o", "Resources/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
print("OK: Resources/AppIcon.icns（预览: .build/icon-preview.png）")
