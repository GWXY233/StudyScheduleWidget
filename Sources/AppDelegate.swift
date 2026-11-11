import AppKit
import Combine
import SwiftUI

final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    var isPositionLocked: Bool = false

    override var mouseDownCanMoveWindow: Bool {
        !isPositionLocked
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: ScheduleStore!
    private var uiState = WidgetUIState()
    private var window: WidgetWindow!
    private var hostingView: DraggableHostingView<WidgetView>!
    private var statusItem: NSStatusItem!
    private var cancellables: Set<AnyCancellable> = []
    private var lastAppliedCompact: Bool?
    private var isProgrammaticMove = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent duplicate running instances
        if let bundleID = Bundle.main.bundleIdentifier {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if running.count > 1 {
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name("com.gwxy.studyschedulewidget.activate"),
                    object: nil,
                    userInfo: nil,
                    deliverImmediately: true
                )
                NSApp.terminate(nil)
                return
            }
        }

        NSApp.setActivationPolicy(.accessory)

        store = ScheduleStore()
        setupWindow()
        setupStatusBar()
        bindStoreUpdates()
        observeActivationNotification()
        observeScreenChanges()

        if !store.preferences.isHidden {
            window.orderFrontRegardless()
        }
    }

    private func setupWindow() {
        let initialSize = targetSize(isCompact: store.preferences.isCompactMode)
        lastAppliedCompact = store.preferences.isCompactMode

        let contentRect = NSRect(origin: .zero, size: initialSize)
        window = WidgetWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rootView = WidgetView(
            store: store,
            uiState: uiState,
            onResetPosition: { [weak self] in
                self?.resetToDefaultPosition()
            },
            onHideWidget: { [weak self] in
                self?.store.setHidden(true)
            },
            onQuitApp: {
                NSApp.terminate(nil)
            },
            onBeginTextEdit: { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.window.makeKeyAndOrderFront(nil)
            }
        )

        hostingView = DraggableHostingView(rootView: rootView)
        hostingView.isPositionLocked = store.preferences.isPositionLocked
        hostingView.frame = contentRect
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        applyWindowPreferences(store.preferences)
        restoreOrDefaultPosition()
    }

    private func targetSize(isCompact: Bool) -> NSSize {
        isCompact ? NSSize(width: 356, height: 220) : NSSize(width: 620, height: 392)
    }

    private func applyWindowPreferences(_ prefs: WidgetPreferences) {
        switch prefs.windowLevelMode {
        case .desktop:
            let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
            // Above wallpaper (-2147483624), Finder icons (-2147483603), and Notification Center widgets (-2147483601),
            // while remaining below all normal app windows (0).
            window.level = NSWindow.Level(rawValue: desktopIconLevel + 3)
        case .floating:
            window.level = .floating
        }

        window.isMovable = !prefs.isPositionLocked
        window.isMovableByWindowBackground = !prefs.isPositionLocked
        hostingView.isPositionLocked = prefs.isPositionLocked

        switch prefs.appearanceMode {
        case .pureWhite:
            window.appearance = NSAppearance(named: .aqua)
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        }

        if lastAppliedCompact != prefs.isCompactMode {
            lastAppliedCompact = prefs.isCompactMode
            resizeKeepingTopRight(to: targetSize(isCompact: prefs.isCompactMode))
        }

        if prefs.isHidden {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    private func resizeKeepingTopRight(to newSize: NSSize) {
        let oldFrame = window.frame
        let newOrigin = NSPoint(
            x: oldFrame.maxX - newSize.width,
            y: oldFrame.maxY - newSize.height
        )
        let clampedOrigin = clampOriginToVisibleScreens(origin: newOrigin, size: newSize)
        isProgrammaticMove = true
        window.setFrame(NSRect(origin: clampedOrigin, size: newSize), display: true, animate: false)
        isProgrammaticMove = false
        store.saveOrigin(clampedOrigin)
    }

    private func restoreOrDefaultPosition() {
        let size = window.frame.size
        if let x = store.preferences.originX, let y = store.preferences.originY {
            let clamped = clampOriginToVisibleScreens(origin: NSPoint(x: x, y: y), size: size)
            isProgrammaticMove = true
            window.setFrameOrigin(clamped)
            isProgrammaticMove = false
        } else {
            resetToDefaultPosition()
        }
    }

    private func resetToDefaultPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let size = window.frame.size
        let existingWidgetRects = nativeDesktopWidgetRects()

        let candidates: [NSPoint] = [
            // Top-right
            NSPoint(x: vf.maxX - size.width - 20, y: vf.maxY - size.height - 16),
            // Bottom-right (right below native widgets if top-right is occupied)
            NSPoint(x: vf.maxX - size.width - 20, y: vf.minY + 12),
            // Top-left
            NSPoint(x: vf.minX + 20, y: vf.maxY - size.height - 16),
            // Bottom-left
            NSPoint(x: vf.minX + 20, y: vf.minY + 12),
        ]

        var chosen = candidates[0]
        for pt in candidates {
            let candidateRect = NSRect(origin: pt, size: size)
            let overlaps = existingWidgetRects.contains { $0.insetBy(dx: -8, dy: -8).intersects(candidateRect) }
            if !overlaps {
                chosen = pt
                break
            }
        }

        let clamped = clampOriginToVisibleScreens(origin: chosen, size: size)
        isProgrammaticMove = true
        window.setFrameOrigin(clamped)
        isProgrammaticMove = false
        store.saveOrigin(clamped)
    }

    private func nativeDesktopWidgetRects() -> [NSRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        let desktopWidgetLayer = Int(CGWindowLevelForKey(.desktopIconWindow)) + 2
        let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        var rects: [NSRect] = []
        for info in infoList {
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == desktopWidgetLayer else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            let appKitRect = NSRect(
                x: cgRect.origin.x,
                y: primaryHeight - cgRect.maxY,
                width: cgRect.width,
                height: cgRect.height
            )
            rects.append(appKitRect)
        }
        return rects
    }

    private func clampOriginToVisibleScreens(origin: NSPoint, size: NSSize) -> NSPoint {
        let candidateRect = NSRect(origin: origin, size: size)
        let matchingScreen = NSScreen.screens.first { $0.visibleFrame.intersects(candidateRect) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let vf = matchingScreen?.visibleFrame else { return origin }
        let minX = vf.minX + 8
        let maxX = max(minX, vf.maxX - size.width - 8)
        let minY = vf.minY + 8
        let maxY = max(minY, vf.maxY - size.height - 8)
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove else { return }
        store.saveOrigin(window.frame.origin)
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarTitle()
        rebuildStatusMenu()
    }

    private func updateStatusBarTitle() {
        guard let button = statusItem.button else { return }
        let countdown = store.daysUntilExam
        let countdownSuffix = countdown > 0 ? "· \(countdown)天" : (countdown == 0 ? "· 考试日" : "")

        if let today = store.todayItem {
            let prefix = today.isCompleted ? "✅" : (today.isHighlightRed ? "🔥" : "📖")
            button.title = "\(prefix) \(today.task) \(countdownSuffix)"
        } else {
            button.title = "📅 备考安排 \(countdownSuffix)"
        }
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()

        // Summary items
        if let today = store.todayItem {
            let statusStr = today.isCompleted ? "已完成" : "待完成"
            let todayItem = NSMenuItem(
                title: "今日 (\(today.shortDate) \(today.weekdayLabel))：\(today.task) [\(statusStr)]",
                action: nil,
                keyEquivalent: ""
            )
            todayItem.isEnabled = false
            menu.addItem(todayItem)
        } else {
            let infoItem = NSMenuItem(title: "今日：\(store.todayDisplayString)", action: nil, keyEquivalent: "")
            infoItem.isEnabled = false
            menu.addItem(infoItem)
        }

        if let tomorrow = store.tomorrowItem {
            let nextItem = NSMenuItem(
                title: "明日 (\(tomorrow.shortDate))：\(tomorrow.task)",
                action: nil,
                keyEquivalent: ""
            )
            nextItem.isEnabled = false
            menu.addItem(nextItem)
        }

        let countdownText = store.daysUntilExam > 0
            ? "距离 12.12 考试还有 \(store.daysUntilExam) 天（已打卡 \(store.completedCount)/\(store.totalCount)）"
            : (store.daysUntilExam == 0 ? "今天就是 12.12 考试日，祝顺利！" : "备考日程已结束")
        let countdownItem = NSMenuItem(title: countdownText, action: nil, keyEquivalent: "")
        countdownItem.isEnabled = false
        menu.addItem(countdownItem)

        menu.addItem(.separator())

        if let today = store.todayItem {
            let checkTitle = today.isCompleted ? "取消今日打卡" : "完成今日打卡 ✓"
            let checkItem = NSMenuItem(title: checkTitle, action: #selector(toggleTodayAction), keyEquivalent: "d")
            checkItem.target = self
            menu.addItem(checkItem)
            menu.addItem(.separator())
        }

        let visibilityTitle = store.preferences.isHidden ? "显示桌面小组件" : "隐藏桌面小组件"
        let visibilityItem = NSMenuItem(title: visibilityTitle, action: #selector(toggleVisibilityAction), keyEquivalent: "h")
        visibilityItem.target = self
        menu.addItem(visibilityItem)

        let compactItem = NSMenuItem(title: "精简卡片模式", action: #selector(toggleCompactAction), keyEquivalent: "m")
        compactItem.target = self
        compactItem.state = store.preferences.isCompactMode ? .on : .off
        menu.addItem(compactItem)

        let floatingItem = NSMenuItem(title: "置顶悬浮（浮在窗口上方）", action: #selector(toggleFloatingAction), keyEquivalent: "t")
        floatingItem.target = self
        floatingItem.state = store.preferences.windowLevelMode == .floating ? .on : .off
        menu.addItem(floatingItem)

        let lockItem = NSMenuItem(title: "锁定小组件位置", action: #selector(toggleLockAction), keyEquivalent: "l")
        lockItem.target = self
        lockItem.state = store.preferences.isPositionLocked ? .on : .off
        menu.addItem(lockItem)

        let resetPosItem = NSMenuItem(title: "自动停靠空余桌面位置", action: #selector(resetPositionAction), keyEquivalent: "")
        resetPosItem.target = self
        menu.addItem(resetPosItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLoginAction), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = store.launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        let openDataItem = NSMenuItem(title: "打开数据文件夹...", action: #selector(openDataFolderAction), keyEquivalent: "")
        openDataItem.target = self
        menu.addItem(openDataItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出小组件", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func toggleTodayAction() {
        store.toggleTodayCompleted()
    }

    @objc private func toggleVisibilityAction() {
        store.setHidden(!store.preferences.isHidden)
    }

    @objc private func toggleCompactAction() {
        store.toggleCompactMode()
    }

    @objc private func toggleFloatingAction() {
        store.toggleWindowLevelMode()
    }

    @objc private func toggleLockAction() {
        store.togglePositionLocked()
    }

    @objc private func resetPositionAction() {
        store.setHidden(false)
        resetToDefaultPosition()
    }

    @objc private func toggleLaunchAtLoginAction() {
        store.setLaunchAtLogin(!store.launchAtLoginEnabled)
        rebuildStatusMenu()
    }

    @objc private func openDataFolderAction() {
        let dir = store.scheduleFileURL.deletingLastPathComponent()
        NSWorkspace.shared.open(dir)
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - Bindings & Observers

    private func bindStoreUpdates() {
        store.$preferences
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] prefs in
                self?.applyWindowPreferences(prefs)
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)

        store.$days
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)

        store.$currentDate
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)

        store.$launchAtLoginEnabled
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildStatusMenu()
            }
            .store(in: &cancellables)
    }

    private func observeActivationNotification() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.gwxy.studyschedulewidget.activate"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.store.setHidden(false)
                self.window.orderFrontRegardless()
            }
        }
    }

    private func observeScreenChanges() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let clamped = self.clampOriginToVisibleScreens(
                        origin: self.window.frame.origin,
                        size: self.window.frame.size
                    )
                    self.isProgrammaticMove = true
                    self.window.setFrameOrigin(clamped)
                    self.isProgrammaticMove = false
                }
            }
            .store(in: &cancellables)
    }
}
