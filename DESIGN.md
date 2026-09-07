# DESIGN.md — mug-uninstaller GUI 设计规范

依据：dsh-ui-taste 插件准则（stylePreset=balanced：融合 Material 3 与 HIG，简洁、一致、克制）。
用户确认：主色调 = 中性灰 + 绿色点缀；明暗模式 = 跟随系统；平台 = macOS（SwiftUI 原生组件）。

## Overview

macOS 原生卸载工具的简洁克制界面：充足留白、单一主操作（卸载）、信息层级由浅到深渐进披露。
绿色 = 选中 / 成功 / 高置信；红色 = 危险操作 / 错误 / SIP；其余一律中性灰阶。
无渐变、无自绘阴影、无卡片堆叠；全部使用系统组件与语义色。

## Colors

| token | 用途 | 浅色 | 深色 |
|---|---|---|---|
| `accent` | 选中态、高置信、成功、运行中徽标 | `#1D7A3D` | `#4ADE80` |
| `accentContainer` | 徽标 / 强调容器底 | `#E7F4EC` | `#16331F` |
| `warning` | FDA 警告、低置信 | 系统 orange | 系统 orange |
| `warningContainer` | 警告容器底 | orange 12% | orange 12% |
| `error` | 卸载按钮、SIP、失败 | 系统 red | 系统 red |
| `errorContainer` | 危险徽标底 | red 12% | red 12% |
| `surface` | 搜索框 / 日志面板底 | 系统 controlBackground | 同 |
| 文字 | 主/次文字 | 系统 primary/secondary | 同 |

规则：主色只做点缀（≤10% 画面）；正文对比度 ≥4.5:1（`#1D7A3D` on `#E7F4EC` ≈ 4.8:1 ✓）；灰阶代替纯黑。

## Typography

- 仅系统字体 SF Pro（≤2 种：正文 + 等宽）。
- 阶梯：页面标题 `.title2 bold` / 区块头 `.headline` / 正文 `.body` / 元信息与徽标 `.caption`。
- 路径类技术文本：`.caption.monospaced()`，单行 `lineLimit(1)` + `truncationMode(.middle)`。
- 数字（大小/统计）：`.monospacedDigit()`，行高默认。

## Elevation

- 层级只用系统组件自带（List / sheet / alert / checkbox），不自绘阴影、不用渐变。
- 强调容器用「浅色填充 + 小圆角」表达：徽标 6pt、面板 8pt；全应用圆角语言一致。
- 动效仅日志面板出现时淡入，时长 0.25s、easeOut，且尊重 `accessibilityReduceMotion`。

## Components

| 组件 | 结构 |
|---|---|
| AppRow | 图标 32pt + 名称 / “版本 · 来源”两行 + 大小（右对齐）+ 徽标（运行中=accent、SIP=error）+ 垃圾桶（可删行=SIP 外的行，点击打开卸载，error 色） |
| AppListStatusBar | “N 个应用 · M 个运行中”计数 + 「隐藏系统应用」开关（switch 样式，默认关=全部显示） |
| ConfidenceDot | 8pt 圆点：high=accent、medium=gray、low=warning |
| LeftoverRow | 复选框（整行可点）+ 圆点 + 截断路径 + 命中原因 + 大小 |
| FooterBar | “已选 X/Y 项 · Z MB” + 全选 / 仅高置信 / 卸载…（error prominent，勾选为空或执行中禁用） |
| LogPanel | 等宽 caption，surface 底 8pt 圆角，最高 96pt |
| FDABanner | warning 容器 + 三角图标 + 一句人话（不含技术黑话） |
| 空态 | 大图标 + 标题 + 一句说明（扫描空 / 搜索空 / 无残留三种） |

## Do's & Don'ts

- ✅ 颜色/间距/圆角一律走 `T.*` tokens（`Theme.swift`），禁行内 hex 与魔法数字；间距只用 4/8/12/16/24。
- ✅ 危险=红、强调=绿、其余中性；图标与文案并置（SF Symbols）；单一主操作；触控目标 ≥44pt。
- ✅ 状态齐全：loading（ProgressView）/ empty（空态视图）/ disabled（执行中）/ error（日志面板列出失败项）；键盘可达（原生 List 选中 + Tab）。
- ✅ 跟随系统明暗（动态色）；文案简洁面向用户（“卸载”“未发现残留”），不出现 bundle id 黑话以外的技术术语。
- ❌ 渐变、卡片堆叠、自绘阴影、纯色铺满、描边堆叠。
- ❌ 在视图里直接写颜色值或尺寸字面量。
