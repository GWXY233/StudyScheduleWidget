# 备考桌面小组件 (StudyScheduleWidget)

一个原生 macOS 桌面日程小组件 + 顶部菜单栏提醒应用（基于 SwiftUI + AppKit 构建，无需完整 Xcode，仅需 Xcode Command Line Tools 即可编译）。

## 功能特点

- **桌面卡片 + 菜单栏双端提醒**：贴合桌面显示，不遮挡日常工作窗口；顶部菜单栏实时展示今日任务与考试倒计时。
- **阶段配色与重点高亮**：完整呈现 5 周备考计划，保留分阶段色块及模拟考/考试日红底高亮，自动识别并突出显示「今日」。
- **每日打卡与自定义编辑**：点击格子即可完成/取消打卡，右键任意一天可修改任务名称、添加备注或调整重点标记，数据本地持久化保存在 `~/Library/Application Support/StudyScheduleWidget/`。
- **多种外观与交互模式**：支持纯白卡片 / 浅色玻璃 / 深色玻璃切换、完整 5 周视图与精简本周卡片切换、贴合桌面与置顶悬浮切换、自由拖拽与位置锁定、开机自启。

## 编译与安装

需要 macOS（Apple Silicon）与 Xcode Command Line Tools：

```bash
chmod +x build.sh
./build.sh
open "/Applications/备考桌面小组件.app"
```

## 目录结构

- `Sources/Models.swift`：日程与偏好设置数据模型
- `Sources/ScheduleStore.swift`：日程初始化、倒计时计算、本地 JSON 持久化与开机自启管理
- `Sources/WidgetView.swift`：SwiftUI 卡片界面与日历格子交互
- `Sources/AppDelegate.swift`：无边框桌面窗口管理、拖拽支持、菜单栏状态项
- `Sources/main.swift`：应用入口
- `Resources/Info.plist`：应用 Bundle 配置
- `generate_icon.swift`：生成应用 `.icns` 图标
- `build.sh`：一键编译、签名并安装到 `/Applications`
