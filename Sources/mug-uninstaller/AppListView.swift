import SwiftUI
import AppKit
import MugUninstallerKit

/// Step1 GUI：应用列表（dsh-ui-taste 重设计版）。
/// 原生 List 选中态 + 双击打开；行内图标 + 元信息两行 + 语义徽标；含加载/搜索空态。
struct AppListView: View {
    @State private var apps: [AppInfo] = []
    @State private var search = ""
    @State private var selectedID: AppInfo.ID?
    @State private var opened: AppInfo?
    @State private var loading = false
    /// 启动默认隐藏系统应用；用户手动开关后记住偏好
    @AppStorage("hideSystemApps") private var hideSystem = true

    init(initialApps: [AppInfo] = []) {
        _apps = State(initialValue: initialApps)
    }

    var filtered: [AppInfo] {
        apps.filter {
            (search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search))
                && (!hideSystem || !$0.isSystemApp)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            List(selection: $selectedID) {
                ForEach(filtered) { app in
                    row(app, selected: selectedID == app.id)
                        .tag(app.id)
                        .contextMenu {
                            Button("扫描残留并卸载…") { open(app) }
                        }
                        .onTapGesture(count: 2) { open(app) }
                }
            }
            .overlay {
                if loading && apps.isEmpty {
                    ProgressView("正在扫描应用…")
                } else if filtered.isEmpty && !loading {
                    emptyState
                }
            }
            statusBar
        }
        .sheet(item: $opened) { app in
            LeftoverView(app: app)
        }
        .onAppear {
            if apps.isEmpty { reload() }
        }
    }

    // MARK: - 区块

    private var header: some View {
        HStack(spacing: T.S.m) {
            VStack(alignment: .leading, spacing: T.S.xs) {
                Text("应用").font(.title2).bold()
                Text("\(apps.count) 个已安装应用")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: T.S.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, T.S.s)
            .padding(.vertical, T.S.s)
            .background(T.surface)
            .clipShape(RoundedRectangle(cornerRadius: T.badgeRadius))
            .frame(width: 220)
            Button {
                reload()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .help("重新扫描应用")
            .disabled(loading)
        }
        .padding(T.S.l)
    }

    private func row(_ app: AppInfo, selected: Bool) -> some View {
        HStack(spacing: T.S.m) {
            Image(nsImage: app.icon ?? NSWorkspace.shared.icon(forFile: app.path.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: T.S.xs) {
                Text(app.displayName)
                Text("\(app.version ?? "—") · \(sourceText(app.source))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            // 固定宽列：状态（SIP 与「运行中」同列）/ 大小 / 垃圾桶；缺内容留空白占位，保证纵向对齐
            Group {
                if app.isSystemApp {
                    Text("SIP")
                        .statusBadge(T.error, container: T.errorContainer, selected: selected)
                } else if app.isRunning {
                    Text("运行中")
                        .statusBadge(T.accent, container: T.accentContainer, selected: selected)
                }
            }
            .frame(width: 76, alignment: .trailing)
            Text(sizeText(app.sizeKB))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .trailing)
            Group {
                if app.isSystemApp {
                    // 系统应用受 SIP 保护：垃圾桶带斜杠（禁用态，不可点击）
                    Image(systemName: "trash.slash")
                        .foregroundColor(.secondary.opacity(0.55))
                        .help("系统应用受 SIP 保护，不可卸载")
                } else {
                    // 可卸载行：尾部垃圾桶，点击打开卸载页
                    Button {
                        open(app)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(T.error)
                    }
                    .buttonStyle(.plain)
                    .help("卸载 \(app.displayName)…")
                }
            }
            .frame(width: 30, alignment: .center)
        }
        .padding(.vertical, T.S.xs)
    }

    private var emptyState: some View {
        VStack(spacing: T.S.s) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("未找到匹配应用")
                .font(.headline)
            Text("换个关键词试试")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusBar: some View {
        HStack {
            Text("\(filtered.count) 个应用 · \(apps.filter(\.isRunning).count) 个运行中")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Toggle("隐藏系统应用", isOn: $hideSystem)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
        }
        .padding(.horizontal, T.S.l)
        .padding(.vertical, T.S.s)
    }

    // MARK: - 行为

    private func open(_ app: AppInfo) { opened = app }

    private func reload() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let list = AppScanner.scan()
            DispatchQueue.main.async {
                apps = list
                loading = false
            }
        }
    }

    // MARK: - 格式化

    private func sizeText(_ kb: Int64) -> String {
        kb > 0 ? String(format: "%.0f MB", Double(kb) / 1024) : "-"
    }

    private func sourceText(_ s: String) -> String {
        ["mas": "App Store", "brew-cask": "Homebrew", "pkg": "安装包", "?": "直接安装"][s] ?? s
    }
}
