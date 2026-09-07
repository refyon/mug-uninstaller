import SwiftUI
import AppKit
import MugUninstallerKit

/// Step3/5 GUI：残留确认与卸载执行（dsh-ui-taste 重设计版）。
/// 置信度圆点 + 整行可点勾选 + 已选统计 + 危险操作红；含 FDA 警告、无残留空态、日志面板。
struct LeftoverView: View {
    let app: AppInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var result: ScanResult?
    @State private var selectedPaths: Set<String> = []
    @State private var log: [String] = []
    @State private var busy = false
    @State private var confirmVisible = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if busy {
                Spacer()
                ProgressView("正在执行…")
                Spacer()
            } else if let r = result {
                if r.leftovers.isEmpty {
                    emptyState
                } else {
                    leftoverList(r)
                    footer(r)
                }
            } else {
                Spacer()
                ProgressView("正在扫描残留…")
                Spacer()
            }
        }
        .frame(minWidth: 620, minHeight: 460)
        .onAppear(perform: load)
        .alert("确认卸载 \(app.displayName)？", isPresented: $confirmVisible) {
            Button("取消", role: .cancel) {}
            Button("执行卸载", role: .destructive) { runUninstall() }
        } message: {
            Text("将移除主程序与勾选的 \(selectedPaths.count) 项残留（移入废纸篓，可恢复）。root 文件删除时会弹出管理员授权。")
        }
    }

    // MARK: - 区块

    private var header: some View {
        HStack(spacing: T.S.m) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: T.S.xs) {
                Text(app.displayName).font(.title3).bold()
                if let bid = app.bundleID {
                    Text(bid).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if !LeftoverView.hasFullDiskAccess() {
                fdaBanner
            }
            Button("完成") { dismiss() }
        }
        .padding(T.S.l)
    }

    private var fdaBanner: some View {
        HStack(spacing: T.S.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(T.warning)
            Text("未授予完全磁盘访问，部分目录可能漏扫")
                .font(.caption)
                .foregroundColor(T.warning)
        }
        .padding(.horizontal, T.S.s)
        .padding(.vertical, T.S.s)
        .background(T.warningContainer)
        .clipShape(RoundedRectangle(cornerRadius: T.badgeRadius))
    }

    private func leftoverList(_ r: ScanResult) -> some View {
        List {
            ForEach([Confidence.high, .medium, .low], id: \.rawValue) { conf in
                let items = r.leftovers.filter { $0.confidence == conf }
                if !items.isEmpty {
                    Section {
                        ForEach(items, id: \.path) { x in
                            Toggle(isOn: binding(for: x.path)) {
                                HStack(spacing: T.S.m) {
                                    Circle()
                                        .fill(confColor(conf))
                                        .frame(width: 8, height: 8)
                                    Text(x.path)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: T.S.m)
                                    Text(x.reasons.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Text(sizeText(x.sizeKB))
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                        .frame(minWidth: 64, alignment: .trailing)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.vertical, T.S.xs)
                        }
                    } header: {
                        HStack(spacing: T.S.s) {
                            Circle()
                                .fill(confColor(conf))
                                .frame(width: 8, height: 8)
                            Text(confTitle(conf)).textCase(nil)
                            Spacer()
                            Text("\(items.count) 项")
                                .foregroundColor(.secondary)
                                .textCase(nil)
                        }
                    }
                }
            }
        }
    }

    private func footer(_ r: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: T.S.s) {
            if !log.isEmpty {
                logPanel
            }
            HStack(spacing: T.S.m) {
                let selected = r.leftovers.filter { selectedPaths.contains($0.path) }
                let selectedKB = selected.reduce(0) { $0 + max(0, $1.sizeKB) }
                Text("已选 \(selected.count)/\(r.leftovers.count) 项 · \(String(format: "%.1f MB", Double(selectedKB) / 1024))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("全选") {
                    selectedPaths = Set(r.leftovers.map(\.path))
                }
                Button("仅高置信") {
                    selectedPaths = Set(r.leftovers.filter { $0.confidence == .high }.map(\.path))
                }
                Button("卸载…", role: .destructive) { confirmVisible = true }
                    .buttonStyle(.borderedProminent)
                    .tint(T.error)
                    .disabled(selectedPaths.isEmpty || busy)
            }
        }
        .padding(T.S.l)
    }

    private var logPanel: some View {
        ScrollView {
            Text(log.joined(separator: "\n"))
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 96)
        .padding(T.S.s)
        .background(T.surface)
        .clipShape(RoundedRectangle(cornerRadius: T.panelRadius))
    }

    private var emptyState: some View {
        VStack(spacing: T.S.s) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundColor(T.accent)
            Text("未发现残留")
                .font(.headline)
            Text("该应用没有留下可清理的文件。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 行为

    private func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = LeftoverScanner.scan(bundleID: app.bundleID, appName: app.displayName)
            DispatchQueue.main.async {
                result = r
                // 默认勾选高/中置信，低置信需人工确认
                selectedPaths = Set(r.leftovers.filter { $0.confidence != .low }.map(\.path))
            }
        }
    }

    private func runUninstall() {
        guard let r = result else { return }
        busy = true
        defer { busy = false }
        let selected = r.leftovers.filter { selectedPaths.contains($0.path) }
        let plan = UninstallEngine.buildPlan(app: app, leftovers: selected)
        let failures = UninstallEngine.execute(plan)
        // 执行后重扫磁盘：已删除项从列表移除；仍存在的项（如提权失败）保留供重试
        let rescan = LeftoverScanner.scan(bundleID: app.bundleID, appName: app.displayName)
        result = rescan
        selectedPaths = Set(rescan.leftovers.filter { $0.confidence != .low }.map(\.path))
        let newLog: [String]
        if failures.isEmpty {
            newLog = ["完成：\(plan.count) 步全部成功。残留已移入废纸篓（可恢复）。"]
        } else {
            newLog = failures.map { "\($0.0): \($0.1)" }
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            log = newLog
        }
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selectedPaths.contains(path) },
            set: { on in
                if on { selectedPaths.insert(path) } else { selectedPaths.remove(path) }
            })
    }

    // MARK: - 格式化与探测

    private func confColor(_ c: Confidence) -> Color {
        switch c {
        case .high: return T.accent
        case .medium: return T.medium
        case .low: return T.warning
        }
    }

    private func confTitle(_ c: Confidence) -> String {
        switch c {
        case .high: return "高置信（可安全删除）"
        case .medium: return "中置信（建议确认）"
        case .low: return "低置信（需人工确认）"
        }
    }

    private func sizeText(_ kb: Int64) -> String {
        if kb < 0 { return "- (需管理员)" }
        return String(format: "%.1f MB", Double(kb) / 1024)
    }

    /// FDA 探针：无公开 API，试读 TCC 保护文件（Safari 的 CloudTabs.db）。
    static func hasFullDiskAccess() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: NSHomeDirectory()
            + "/Library/Safari/CloudTabs.db")) else { return false }
        return data.count > 0
    }
}
