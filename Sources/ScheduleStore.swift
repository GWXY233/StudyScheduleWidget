import AppKit
import Combine
import Foundation

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var days: [StudyDay] = []
    @Published var weeks: [WeekMeta] = []
    @Published var preferences: WidgetPreferences = WidgetPreferences()
    @Published var currentDate: Date = Date()
    @Published var launchAtLoginEnabled: Bool = false

    private let fileManager = FileManager.default
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private var appSupportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("StudyScheduleWidget", isDirectory: true)
    }

    var scheduleFileURL: URL {
        appSupportDirectory.appendingPathComponent("schedule.json")
    }

    var preferencesFileURL: URL {
        appSupportDirectory.appendingPathComponent("preferences.json")
    }

    static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "zh_CN")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    static let chineseDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "zh_CN")
        df.timeZone = TimeZone.current
        df.dateFormat = "M月d日 EEEE"
        return df
    }()

    init() {
        ensureDirectory()
        weeks = Self.defaultWeeks()
        loadSchedule()
        loadPreferences()
        launchAtLoginEnabled = LaunchAgentManager.isEnabled()
        setupDateRefreshObservers()
    }

    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: appSupportDirectory.path) {
            try? fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        }
    }

    private func setupDateRefreshObservers() {
        // Refresh every 60 seconds so midnight rollover is detected quickly
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDateIfNeeded()
            }
        }

        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshDateIfNeeded(force: true)
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshDateIfNeeded(force: true)
                }
            }
            .store(in: &cancellables)
    }

    func refreshDateIfNeeded(force: Bool = false) {
        let now = Date()
        if force || Self.dateFormatter.string(from: now) != Self.dateFormatter.string(from: currentDate) {
            currentDate = now
        }
    }

    // MARK: - Persistence

    func loadSchedule() {
        if let data = try? Data(contentsOf: scheduleFileURL),
           let decoded = try? JSONDecoder().decode([StudyDay].self, from: data),
           !decoded.isEmpty {
            days = decoded
        } else {
            days = Self.defaultSchedule()
            saveSchedule()
        }
    }

    func saveSchedule() {
        ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(days) {
            try? data.write(to: scheduleFileURL, options: .atomic)
        }
    }

    func loadPreferences() {
        if let data = try? Data(contentsOf: preferencesFileURL),
           var decoded = try? JSONDecoder().decode(WidgetPreferences.self, from: data) {
            if decoded.styleVersion < 2 {
                decoded.appearanceMode = .pureWhite
                decoded.opacity = 1.0
                decoded.styleVersion = 2
                preferences = decoded
                savePreferences()
            } else {
                preferences = decoded
            }
        } else {
            preferences = WidgetPreferences()
            savePreferences()
        }
    }

    func savePreferences() {
        ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(preferences) {
            try? data.write(to: preferencesFileURL, options: .atomic)
        }
    }

    func resetToDefaultSchedule() {
        days = Self.defaultSchedule()
        saveSchedule()
    }

    // MARK: - Computed Properties

    var todayString: String {
        Self.dateFormatter.string(from: currentDate)
    }

    var todayDisplayString: String {
        Self.chineseDateFormatter.string(from: currentDate)
    }

    var tomorrowString: String {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        return Self.dateFormatter.string(from: tomorrow)
    }

    var todayItem: StudyDay? {
        days.first { $0.dateString == todayString }
    }

    var tomorrowItem: StudyDay? {
        days.first { $0.dateString == tomorrowString }
    }

    var examDate: Date? {
        if let examDay = days.first(where: { $0.isExamDay }) {
            return Self.dateFormatter.date(from: examDay.dateString)
        }
        return Self.dateFormatter.date(from: "2026-12-12")
    }

    var daysUntilExam: Int {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: currentDate)
        guard let target = examDate else { return 0 }
        let startTarget = cal.startOfDay(for: target)
        return cal.dateComponents([.day], from: startToday, to: startTarget).day ?? 0
    }

    var nextMilestone: (day: StudyDay, daysRemaining: Int)? {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: currentDate)
        for item in days where item.isHighlightRed || item.isExamDay {
            guard let d = Self.dateFormatter.date(from: item.dateString) else { continue }
            let diff = cal.dateComponents([.day], from: startToday, to: cal.startOfDay(for: d)).day ?? -1
            if diff >= 0 {
                return (item, diff)
            }
        }
        return nil
    }

    var completedCount: Int {
        days.filter { $0.isCompleted }.count
    }

    var totalCount: Int {
        days.count
    }

    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var currentWeekIndex: Int {
        if let today = todayItem {
            return today.weekIndex
        }
        if let firstDateStr = days.first?.dateString, todayString < firstDateStr {
            return 0
        }
        return max(0, weeks.count - 1)
    }

    func day(for weekIndex: Int, weekdayIndex: Int) -> StudyDay? {
        days.first { $0.weekIndex == weekIndex && $0.weekdayIndex == weekdayIndex }
    }

    func isPast(_ item: StudyDay) -> Bool {
        item.dateString < todayString
    }

    func isToday(_ item: StudyDay) -> Bool {
        item.dateString == todayString
    }

    // MARK: - Mutations

    func toggleCompleted(dateString: String) {
        guard let idx = days.firstIndex(where: { $0.dateString == dateString }) else { return }
        days[idx].isCompleted.toggle()
        saveSchedule()
    }

    func toggleTodayCompleted() {
        toggleCompleted(dateString: todayString)
    }

    func updateDay(dateString: String, task: String, note: String, isHighlightRed: Bool, isCompleted: Bool) {
        guard let idx = days.firstIndex(where: { $0.dateString == dateString }) else { return }
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            days[idx].task = trimmed
        }
        days[idx].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        days[idx].isHighlightRed = isHighlightRed
        days[idx].isCompleted = isCompleted
        saveSchedule()
    }

    func setCompactMode(_ compact: Bool) {
        preferences.isCompactMode = compact
        savePreferences()
    }

    func toggleCompactMode() {
        setCompactMode(!preferences.isCompactMode)
    }

    func setWindowLevelMode(_ mode: WindowLevelMode) {
        preferences.windowLevelMode = mode
        savePreferences()
    }

    func toggleWindowLevelMode() {
        let next: WindowLevelMode = preferences.windowLevelMode == .desktop ? .floating : .desktop
        setWindowLevelMode(next)
    }

    func setPositionLocked(_ locked: Bool) {
        preferences.isPositionLocked = locked
        savePreferences()
    }

    func togglePositionLocked() {
        setPositionLocked(!preferences.isPositionLocked)
    }

    func setAppearanceMode(_ mode: WidgetAppearanceMode) {
        preferences.appearanceMode = mode
        savePreferences()
    }

    func setOpacity(_ value: Double) {
        preferences.opacity = min(1.0, max(0.55, value))
        savePreferences()
    }

    func setHidden(_ hidden: Bool) {
        preferences.isHidden = hidden
        savePreferences()
    }

    func saveOrigin(_ point: NSPoint) {
        preferences.originX = point.x
        preferences.originY = point.y
        savePreferences()
    }

    func clearSavedOrigin() {
        preferences.originX = nil
        preferences.originY = nil
        savePreferences()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            LaunchAgentManager.enable()
        } else {
            LaunchAgentManager.disable()
        }
        launchAtLoginEnabled = LaunchAgentManager.isEnabled()
    }

    // MARK: - Default Schedule (Exact match from user's table)

    static func defaultWeeks() -> [WeekMeta] {
        [
            WeekMeta(id: 0, label: "11.9-11.15", phase: .phase1),
            WeekMeta(id: 1, label: "11.16-11.22", phase: .phase1),
            WeekMeta(id: 2, label: "11.23-11.29", phase: .phase2),
            WeekMeta(id: 3, label: "11.30-12.6", phase: .phase2),
            WeekMeta(id: 4, label: "12.7-12.12", phase: .phase3),
        ]
    }

    static func defaultSchedule() -> [StudyDay] {
        struct RawEntry {
            let month: Int
            let day: Int
            let weekdayIndex: Int
            let weekIndex: Int
            let phase: StudyPhase
            let task: String
            let isRed: Bool
            let isExam: Bool
        }

        let entries: [RawEntry] = [
            // Week 1: 11.9 - 11.15
            RawEntry(month: 11, day: 9,  weekdayIndex: 0, weekIndex: 0, phase: .phase1, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 11, day: 10, weekdayIndex: 1, weekIndex: 0, phase: .phase1, task: "听力", isRed: false, isExam: false),
            RawEntry(month: 11, day: 11, weekdayIndex: 2, weekIndex: 0, phase: .phase1, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 11, day: 12, weekdayIndex: 3, weekIndex: 0, phase: .phase1, task: "听力", isRed: false, isExam: false),
            RawEntry(month: 11, day: 13, weekdayIndex: 4, weekIndex: 0, phase: .phase1, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 11, day: 14, weekdayIndex: 5, weekIndex: 0, phase: .phase1, task: "写作翻译+刷题", isRed: false, isExam: false),
            RawEntry(month: 11, day: 15, weekdayIndex: 6, weekIndex: 0, phase: .phase1, task: "写作翻译+看错题", isRed: false, isExam: false),

            // Week 2: 11.16 - 11.22
            RawEntry(month: 11, day: 16, weekdayIndex: 0, weekIndex: 1, phase: .phase1, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 11, day: 17, weekdayIndex: 1, weekIndex: 1, phase: .phase1, task: "听力", isRed: false, isExam: false),
            RawEntry(month: 11, day: 18, weekdayIndex: 2, weekIndex: 1, phase: .phase1, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 11, day: 19, weekdayIndex: 3, weekIndex: 1, phase: .phase1, task: "听力", isRed: false, isExam: false),
            RawEntry(month: 11, day: 20, weekdayIndex: 4, weekIndex: 1, phase: .phase1, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 11, day: 21, weekdayIndex: 5, weekIndex: 1, phase: .phase1, task: "写作翻译+刷题", isRed: false, isExam: false),
            RawEntry(month: 11, day: 22, weekdayIndex: 6, weekIndex: 1, phase: .phase1, task: "写作翻译+看错题", isRed: false, isExam: false),

            // Week 3: 11.23 - 11.29
            RawEntry(month: 11, day: 23, weekdayIndex: 0, weekIndex: 2, phase: .phase2, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 11, day: 24, weekdayIndex: 1, weekIndex: 2, phase: .phase2, task: "听力", isRed: false, isExam: false),
            RawEntry(month: 11, day: 25, weekdayIndex: 2, weekIndex: 2, phase: .phase2, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 11, day: 26, weekdayIndex: 3, weekIndex: 2, phase: .phase2, task: "听力", isRed: false, isExam: false),
            RawEntry(month: 11, day: 27, weekdayIndex: 4, weekIndex: 2, phase: .phase2, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 11, day: 28, weekdayIndex: 5, weekIndex: 2, phase: .phase2, task: "写作翻译+刷题", isRed: false, isExam: false),
            RawEntry(month: 11, day: 29, weekdayIndex: 6, weekIndex: 2, phase: .phase2, task: "写作翻译+看错题", isRed: false, isExam: false),

            // Week 4: 11.30 - 12.6
            RawEntry(month: 11, day: 30, weekdayIndex: 0, weekIndex: 3, phase: .phase2, task: "听力", isRed: false, isExam: false),
            RawEntry(month: 12, day: 1,  weekdayIndex: 1, weekIndex: 3, phase: .phase2, task: "模拟考试1", isRed: true, isExam: false),
            RawEntry(month: 12, day: 2,  weekdayIndex: 2, weekIndex: 3, phase: .phase2, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 12, day: 3,  weekdayIndex: 3, weekIndex: 3, phase: .phase2, task: "写作翻译", isRed: false, isExam: false),
            RawEntry(month: 12, day: 4,  weekdayIndex: 4, weekIndex: 3, phase: .phase2, task: "听力", isRed: false, isExam: false),
            RawEntry(month: 12, day: 5,  weekdayIndex: 5, weekIndex: 3, phase: .phase2, task: "模拟考试2", isRed: true, isExam: false),
            RawEntry(month: 12, day: 6,  weekdayIndex: 6, weekIndex: 3, phase: .phase2, task: "写作翻译+看错题", isRed: false, isExam: false),

            // Week 5: 12.7 - 12.12
            RawEntry(month: 12, day: 7,  weekdayIndex: 0, weekIndex: 4, phase: .phase3, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 12, day: 8,  weekdayIndex: 1, weekIndex: 4, phase: .phase3, task: "模拟考试3", isRed: true, isExam: false),
            RawEntry(month: 12, day: 9,  weekdayIndex: 2, weekIndex: 4, phase: .phase3, task: "阅读", isRed: false, isExam: false),
            RawEntry(month: 12, day: 10, weekdayIndex: 3, weekIndex: 4, phase: .phase3, task: "写作翻译", isRed: false, isExam: false),
            RawEntry(month: 12, day: 11, weekdayIndex: 4, weekIndex: 4, phase: .phase3, task: "写作翻译", isRed: false, isExam: false),
            RawEntry(month: 12, day: 12, weekdayIndex: 5, weekIndex: 4, phase: .phase3, task: "考试日", isRed: true, isExam: true),
        ]

        return entries.map { e in
            let ds = String(format: "2026-%02d-%02d", e.month, e.day)
            return StudyDay(
                dateString: ds,
                month: e.month,
                day: e.day,
                weekdayIndex: e.weekdayIndex,
                weekIndex: e.weekIndex,
                phase: e.phase,
                task: e.task,
                note: "",
                isHighlightRed: e.isRed,
                isExamDay: e.isExam,
                isCompleted: false
            )
        }
    }
}

enum LaunchAgentManager {
    static let label = "com.gwxy.studyschedulewidget"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func enable() {
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let executablePath = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: plistURL, options: .atomic)
        }
    }

    static func disable() {
        try? FileManager.default.removeItem(at: plistURL)
    }
}
