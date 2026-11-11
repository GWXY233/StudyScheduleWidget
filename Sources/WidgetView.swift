import AppKit
import Combine
import SwiftUI

@MainActor
final class WidgetUIState: ObservableObject {
    @Published var editingDay: StudyDay?
    @Published var draftTask: String = ""
    @Published var draftNote: String = ""
    @Published var draftIsRed: Bool = false
    @Published var draftIsCompleted: Bool = false

    @Published var isEditingTitle: Bool = false
    @Published var draftTitle: String = ""
    @Published var hoveredDate: String?

    func beginEditingDay(_ day: StudyDay) {
        editingDay = day
        draftTask = day.task
        draftNote = day.note
        draftIsRed = day.isHighlightRed
        draftIsCompleted = day.isCompleted
    }

    func endEditingDay() {
        editingDay = nil
    }

    func beginEditingTitle(_ currentTitle: String) {
        draftTitle = currentTitle
        isEditingTitle = true
    }

    func endEditingTitle() {
        isEditingTitle = false
    }
}

struct WindowDragHandleView: NSViewRepresentable {
    let isLocked: Bool
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DragNSView {
        let view = DragNSView()
        view.isLocked = isLocked
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DragNSView, context: Context) {
        nsView.isLocked = isLocked
        nsView.onDoubleClick = onDoubleClick
    }

    final class DragNSView: NSView {
        var isLocked: Bool = false
        var onDoubleClick: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool {
            !isLocked
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
                return
            }
            guard !isLocked else { return }
            window?.performDrag(with: event)
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct WidgetView: View {
    @ObservedObject var store: ScheduleStore
    @ObservedObject var uiState: WidgetUIState
    let onResetPosition: () -> Void
    let onHideWidget: () -> Void
    let onQuitApp: () -> Void
    let onBeginTextEdit: () -> Void

    private let weekdayHeaders = ["一", "二", "三", "四", "五", "六", "日"]

    private var isPureWhite: Bool {
        store.preferences.appearanceMode == .pureWhite
    }

    var body: some View {
        ZStack {
            if isPureWhite {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.75)
                    )
            } else {
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    )
            }

            VStack(spacing: 8) {
                topBarView
                heroCardView

                if store.preferences.isCompactMode {
                    compactWeekStrip
                } else {
                    fullScheduleGrid
                }

                footerBarView
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let target = uiState.editingDay {
                DayEditorOverlay(
                    day: target,
                    uiState: uiState,
                    onSave: {
                        store.updateDay(
                            dateString: target.dateString,
                            task: uiState.draftTask,
                            note: uiState.draftNote,
                            isHighlightRed: uiState.draftIsRed,
                            isCompleted: uiState.draftIsCompleted
                        )
                        uiState.endEditingDay()
                    },
                    onCancel: {
                        uiState.endEditingDay()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if uiState.isEditingTitle {
                TitleEditorOverlay(
                    title: $uiState.draftTitle,
                    onSave: {
                        let cleaned = uiState.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            store.preferences.widgetTitle = cleaned
                            store.savePreferences()
                        }
                        uiState.endEditingTitle()
                    },
                    onCancel: {
                        uiState.endEditingTitle()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(
            width: store.preferences.isCompactMode ? 356 : 620,
            height: store.preferences.isCompactMode ? 220 : 392
        )
        .environment(\.colorScheme, store.preferences.appearanceMode == .dark ? .dark : .light)
        .opacity(store.preferences.opacity)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: store.preferences.isCompactMode)
        .animation(.easeOut(duration: 0.16), value: uiState.editingDay != nil)
        .animation(.easeOut(duration: 0.16), value: uiState.isEditingTitle)
    }

    // MARK: - Top Bar

    private var topBarView: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Image(systemName: store.preferences.isPositionLocked ? "lock.fill" : "line.3.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(store.preferences.isPositionLocked ? Color.secondary : Color.blue.opacity(0.85))

                    Text(store.preferences.widgetTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                WindowDragHandleView(isLocked: store.preferences.isPositionLocked) {
                    onBeginTextEdit()
                    uiState.beginEditingTitle(store.preferences.widgetTitle)
                }
            }
            .frame(height: 22)
            .help(store.preferences.isPositionLocked ? "位置已锁定（点击右侧锁头解锁后可拖动）" : "按住此处拖动小组件位置（双击可改标题）")

            HStack(spacing: 4) {
                toolbarIconButton(
                    systemName: store.preferences.isCompactMode
                        ? "rectangle.expand.vertical"
                        : "rectangle.compress.vertical",
                    helpText: store.preferences.isCompactMode ? "展开完整 5 周视图" : "切换精简卡片视图"
                ) {
                    store.toggleCompactMode()
                }

                toolbarIconButton(
                    systemName: store.preferences.windowLevelMode == .floating ? "pin.fill" : "pin",
                    helpText: store.preferences.windowLevelMode == .floating
                        ? "当前：置顶悬浮（点击切回贴合桌面）"
                        : "当前：贴合桌面（点击设为置顶悬浮）",
                    isActive: store.preferences.windowLevelMode == .floating
                ) {
                    store.toggleWindowLevelMode()
                }

                toolbarIconButton(
                    systemName: store.preferences.isPositionLocked ? "lock.fill" : "lock.open",
                    helpText: store.preferences.isPositionLocked ? "已锁定位置（点击解锁拖动）" : "允许拖动（点击锁定位置）",
                    isActive: store.preferences.isPositionLocked
                ) {
                    store.togglePositionLocked()
                }

                Menu {
                    Button {
                        onBeginTextEdit()
                        uiState.beginEditingTitle(store.preferences.widgetTitle)
                    } label: {
                        Label("修改小组件标题...", systemImage: "pencil")
                    }

                    Divider()

                    Menu("外观风格") {
                        ForEach(WidgetAppearanceMode.allCases, id: \.self) { mode in
                            Button {
                                store.setAppearanceMode(mode)
                            } label: {
                                if store.preferences.appearanceMode == mode {
                                    Label(mode.displayName, systemImage: "checkmark")
                                } else {
                                    Text(mode.displayName)
                                }
                            }
                        }
                    }

                    Menu("不透明度 (\(Int(store.preferences.opacity * 100))%)") {
                        ForEach([1.0, 0.96, 0.90, 0.82, 0.72], id: \.self) { level in
                            Button("\(Int(level * 100))%") {
                                store.setOpacity(level)
                            }
                        }
                    }

                    Divider()

                    Button {
                        store.setLaunchAtLogin(!store.launchAtLoginEnabled)
                    } label: {
                        if store.launchAtLoginEnabled {
                            Label("开机自动启动", systemImage: "checkmark")
                        } else {
                            Label("开机自动启动", systemImage: "power")
                        }
                    }

                    Button {
                        onResetPosition()
                    } label: {
                        Label("自动停靠空余桌面位置", systemImage: "arrow.up.right.square")
                    }

                    Button {
                        onHideWidget()
                    } label: {
                        Label("隐藏桌面卡片（菜单栏可恢复）", systemImage: "eye.slash")
                    }

                    Divider()

                    Button(role: .destructive) {
                        store.resetToDefaultSchedule()
                    } label: {
                        Label("恢复默认表格日程", systemImage: "arrow.counterclockwise")
                    }

                    Button(role: .destructive) {
                        onQuitApp()
                    } label: {
                        Label("退出小组件", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多设置")
            }
        }
    }

    private func toolbarIconButton(
        systemName: String,
        helpText: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    // MARK: - Today Hero Card

    private var heroCardView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(store.todayDisplayString)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if let tomorrow = store.tomorrowItem, !store.preferences.isCompactMode {
                        Text("· 明日：\(tomorrow.task)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.85))
                            .lineLimit(1)
                    }
                }

                if let today = store.todayItem {
                    HStack(spacing: 7) {
                        Image(systemName: today.categorySymbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(today.isHighlightRed ? .red : .accentColor)

                        Text(today.task)
                            .font(.system(size: store.preferences.isCompactMode ? 17 : 19, weight: .bold))
                            .foregroundStyle(today.isHighlightRed ? Color.red : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        if !today.note.isEmpty {
                            Image(systemName: "note.text")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                                .help(today.note)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onBeginTextEdit()
                        uiState.beginEditingDay(today)
                    }
                } else {
                    Text(store.daysUntilExam < 0 ? "本阶段安排已完成" : "今日暂无安排")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                countdownBadge

                if let today = store.todayItem {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                            store.toggleTodayCompleted()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: today.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(today.isCompleted ? "已打卡" : "打卡")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(today.isCompleted ? Color.white : Color.accentColor)
                        .background(
                            Capsule(style: .continuous)
                                .fill(today.isCompleted ? Color.green : Color.accentColor.opacity(0.14))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("点击切换今日完成状态")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isPureWhite ? Color(red: 0.96, green: 0.97, blue: 0.985) : Color.primary.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isPureWhite ? 0.05 : 0.08), lineWidth: 1)
                )
        )
    }

    private var countdownBadge: some View {
        let diff = store.daysUntilExam
        let isUrgent = diff >= 0 && diff <= 7
        return VStack(alignment: .trailing, spacing: 1) {
            Text(diff > 0 ? "距考试" : (diff == 0 ? "12.12" : "已结束"))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            if diff > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(diff)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isUrgent ? Color.red : Color.primary)
                    Text("天")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else if diff == 0 {
                Text("加油!")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.red)
            } else {
                Text("+\(-diff)天")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isUrgent ? Color.red.opacity(0.12) : Color.primary.opacity(0.04))
        )
    }

    // MARK: - Full 5-Week Schedule Grid

    private var fullScheduleGrid: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text("周次")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .center)

                ForEach(0..<7, id: \.self) { col in
                    let isTodayCol = store.todayItem?.weekdayIndex == col
                    Text("星期\(weekdayHeaders[col])")
                        .font(.system(size: 10.5, weight: isTodayCol ? .bold : .semibold))
                        .foregroundStyle(isTodayCol ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)

            ForEach(store.weeks) { week in
                weekRowView(week: week)
            }
        }
    }

    private func weekRowView(week: WeekMeta) -> some View {
        let isCurrentWeek = store.currentWeekIndex == week.id
        return HStack(spacing: 5) {
            VStack(spacing: 2) {
                Text(week.label)
                    .font(.system(size: 10.5, weight: isCurrentWeek ? .bold : .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isCurrentWeek ? Color.accentColor : Color.primary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if isCurrentWeek {
                    Text("本周")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .frame(width: 70, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(phaseTint(week.phase).opacity(0.85))
            )

            ForEach(0..<7, id: \.self) { weekday in
                if let item = store.day(for: week.id, weekdayIndex: weekday) {
                    dayCellView(item: item)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.025))
                        .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                }
            }
        }
    }

    private func dayCellView(item: StudyDay) -> some View {
        let isToday = store.isToday(item)
        let isPast = store.isPast(item)
        let isHovered = uiState.hoveredDate == item.dateString

        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                store.toggleCompleted(dateString: item.dateString)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Text(item.shortDate)
                            .font(.system(size: 8.5, weight: isToday ? .bold : .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(
                                item.isHighlightRed
                                    ? Color.white.opacity(0.88)
                                    : (isToday ? Color.accentColor : Color.secondary.opacity(0.85))
                            )

                        if !item.note.isEmpty {
                            Circle()
                                .fill(item.isHighlightRed ? Color.yellow : Color.orange)
                                .frame(width: 4, height: 4)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 5)
                    .padding(.top, 3)

                    Spacer(minLength: 0)

                    Text(item.formattedTask)
                        .font(.system(
                            size: item.task.count >= 6 ? 9.5 : 10.8,
                            weight: (item.isExamDay || item.isHighlightRed || isToday) ? .bold : .medium
                        ))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(cellTextColor(item: item, isToday: isToday, isPast: isPast))
                        .padding(.horizontal, 3)

                    Spacer(minLength: 2)
                }
                .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cellBackground(item: item, isToday: isToday, isHovered: isHovered))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isToday
                                ? (item.isHighlightRed ? Color.yellow : Color.accentColor)
                                : (isHovered ? Color.primary.opacity(0.28) : Color.primary.opacity(0.06)),
                            lineWidth: isToday ? 2 : 0.8
                        )
                )

                if item.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(item.isHighlightRed ? Color.white : Color.green)
                        .background(
                            Circle()
                                .fill(item.isHighlightRed ? Color.red : (isPureWhite ? Color.white : Color(nsColor: .windowBackgroundColor)))
                                .padding(1.5)
                        )
                        .padding(3)
                } else if isToday {
                    Text("今")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(item.isHighlightRed ? Color.red : Color.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(item.isHighlightRed ? Color.white : Color.accentColor)
                        )
                        .padding(2.5)
                }
            }
            .opacity(isPast && !item.isCompleted && !item.isHighlightRed ? 0.65 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            uiState.hoveredDate = hovering ? item.dateString : (uiState.hoveredDate == item.dateString ? nil : uiState.hoveredDate)
        }
        .help(tooltipText(for: item))
        .contextMenu {
            Button {
                store.toggleCompleted(dateString: item.dateString)
            } label: {
                Label(
                    item.isCompleted ? "取消已完成" : "标记为已完成",
                    systemImage: item.isCompleted ? "circle" : "checkmark.circle.fill"
                )
            }

            Button {
                onBeginTextEdit()
                uiState.beginEditingDay(item)
            } label: {
                Label("编辑任务 / 备注...", systemImage: "pencil")
            }
        }
    }

    // MARK: - Compact Week Strip

    private var compactWeekStrip: some View {
        let weekIdx = store.currentWeekIndex
        let weekLabel = store.weeks.first(where: { $0.id == weekIdx })?.label ?? ""

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("本周安排 (\(weekLabel))")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let tomorrow = store.tomorrowItem {
                    Text("明日：\(tomorrow.task)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { col in
                    if let item = store.day(for: weekIdx, weekdayIndex: col) {
                        compactDayChip(item: item)
                    } else {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
                    }
                }
            }
        }
    }

    private func compactDayChip(item: StudyDay) -> some View {
        let isToday = store.isToday(item)
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                store.toggleCompleted(dateString: item.dateString)
            }
        } label: {
            VStack(spacing: 2) {
                Text(weekdayHeaders[item.weekdayIndex])
                    .font(.system(size: 9, weight: isToday ? .bold : .medium))
                    .foregroundStyle(item.isHighlightRed ? Color.white.opacity(0.9) : (isToday ? Color.accentColor : Color.secondary))

                Text(item.task)
                    .font(.system(size: 9.2, weight: (isToday || item.isHighlightRed) ? .bold : .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(cellTextColor(item: item, isToday: isToday, isPast: store.isPast(item)))

                if item.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(item.isHighlightRed ? .white : .green)
                } else {
                    Text(item.shortDate)
                        .font(.system(size: 8, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(item.isHighlightRed ? Color.white.opacity(0.75) : Color.secondary.opacity(0.75))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(cellBackground(item: item, isToday: isToday, isHovered: false))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isToday ? Color.accentColor : Color.primary.opacity(0.07), lineWidth: isToday ? 1.8 : 0.7)
            )
        }
        .buttonStyle(.plain)
        .help(tooltipText(for: item))
        .contextMenu {
            Button("编辑任务 / 备注...") {
                onBeginTextEdit()
                uiState.beginEditingDay(item)
            }
        }
    }

    // MARK: - Footer Progress Bar

    private var footerBarView: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.green],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * store.progressFraction))
                }
            }
            .frame(height: 5)

            Text("已打卡 \(store.completedCount)/\(store.totalCount) 天")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if !store.preferences.isCompactMode, let milestone = store.nextMilestone, milestone.daysRemaining > 0 {
                Text("· 距\(milestone.day.task) \(milestone.daysRemaining)天")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(milestone.daysRemaining <= 5 ? Color.red : Color.secondary)
            }
        }
    }

    // MARK: - Styling Helpers

    private func phaseTint(_ phase: StudyPhase) -> Color {
        if isPureWhite {
            switch phase {
            case .phase1:
                return Color(red: 0.87, green: 0.94, blue: 1.0)
            case .phase2:
                return Color(red: 0.99, green: 0.93, blue: 0.84)
            case .phase3:
                return Color(red: 0.955, green: 0.96, blue: 0.972)
            }
        }
        switch phase {
        case .phase1:
            return Color(red: 0.22, green: 0.62, blue: 0.96).opacity(0.18)
        case .phase2:
            return Color(red: 0.95, green: 0.68, blue: 0.18).opacity(0.20)
        case .phase3:
            return Color.primary.opacity(0.055)
        }
    }

    private func cellBackground(item: StudyDay, isToday: Bool, isHovered: Bool) -> Color {
        if item.isHighlightRed {
            return Color(red: 0.89, green: 0.16, blue: 0.18).opacity(isHovered ? 1.0 : 0.92)
        }
        let base = phaseTint(item.phase)
        if isToday {
            return isPureWhite ? Color(red: 0.88, green: 0.935, blue: 1.0) : Color.accentColor.opacity(0.18)
        }
        if item.isCompleted {
            return isPureWhite ? Color(red: 0.88, green: 0.97, blue: 0.91) : Color.green.opacity(0.13)
        }
        if isHovered {
            return isPureWhite ? Color(red: 0.92, green: 0.93, blue: 0.95) : Color.primary.opacity(0.11)
        }
        return base
    }

    private func cellTextColor(item: StudyDay, isToday: Bool, isPast: Bool) -> Color {
        if item.isHighlightRed {
            return .white
        }
        if isToday {
            return .primary
        }
        if item.isCompleted {
            return .primary.opacity(0.75)
        }
        return isPast ? .secondary : .primary
    }

    private func tooltipText(for item: StudyDay) -> String {
        var parts = ["\(item.month)月\(item.day)日 \(item.weekdayLabel)：\(item.task)"]
        parts.append(item.isCompleted ? "状态：已完成（点击取消）" : "状态：待完成（点击打卡）")
        if !item.note.isEmpty {
            parts.append("备注：\(item.note)")
        }
        parts.append("右键可编辑任务与备注")
        return parts.joined(separator: "\n")
    }
}

// MARK: - Inline Edit Overlays

private struct DayEditorOverlay: View {
    let day: StudyDay
    @ObservedObject var uiState: WidgetUIState
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("编辑 \(day.month)月\(day.day)日 (\(day.weekdayLabel))")
                        .font(.system(size: 13.5, weight: .bold))
                    Spacer()
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("任务名称")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("例如：阅读 / 模拟考试1", text: $uiState.draftTask)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("备注（可选）")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("例如：真题 2024.6 第一套", text: $uiState.draftNote)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                }

                HStack(spacing: 16) {
                    Toggle("红色重点标记", isOn: $uiState.draftIsRed)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))

                    Toggle("已完成打卡", isOn: $uiState.draftIsCompleted)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                }

                HStack {
                    Spacer()
                    Button("取消", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("保存", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
            )
        }
    }
}

private struct TitleEditorOverlay: View {
    @Binding var title: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .onTapGesture { onCancel() }

            VStack(alignment: .leading, spacing: 10) {
                Text("修改小组件标题")
                    .font(.system(size: 13.5, weight: .bold))

                TextField("输入标题", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))

                HStack {
                    Spacer()
                    Button("取消", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("保存", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
            )
        }
    }
}
