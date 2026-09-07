import SwiftUI
import AppKit

/// dsh-ui-taste 设计 tokens（DESIGN.md）：
/// 中性灰阶 + 绿色点缀（用户确认）、跟随系统明暗、间距 4/8pt 网格。
enum T {
    // MARK: 颜色
    static let accent = Color(light: 0x1D7A3D, dark: 0x4ADE80)
    static let accentContainer = Color(light: 0xE7F4EC, dark: 0x16331F)
    static let warning = Color.orange
    static let warningContainer = Color.orange.opacity(0.12)
    static let error = Color.red
    static let errorContainer = Color.red.opacity(0.12)
    static let medium = Color.gray
    static let surface = Color(nsColor: .controlBackgroundColor)

    // MARK: 间距（4/8pt 网格）
    enum S {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: 圆角
    static let badgeRadius: CGFloat = 6
    static let panelRadius: CGFloat = 8
}

// MARK: - 明暗自适应色

extension Color {
    /// 跟随系统外观的自适应色。
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - 徽标（浅色容器 + 同色文字，代替阴影表达强调）

extension View {
    /// 状态徽标。列表行被选中时会叠上系统高亮底色，此时改用不透明系统表面色作底，
    /// 避免半透明容器与高亮混色看不清。
    func statusBadge(_ color: Color, container: Color, selected: Bool) -> some View {
        foregroundColor(color)
            .font(.caption)
            .padding(.horizontal, T.S.s)
            .padding(.vertical, T.S.xs)
            .background(selected ? T.surface : container)
            .clipShape(RoundedRectangle(cornerRadius: T.badgeRadius))
    }
}
