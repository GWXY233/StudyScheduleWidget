import Foundation

enum StudyPhase: String, Codable, CaseIterable {
    case phase1 // 11.9 - 11.22 (Blue)
    case phase2 // 11.23 - 12.6 (Amber)
    case phase3 // 12.7 - 12.12 (Final Sprint)
}

struct StudyDay: Identifiable, Codable, Equatable {
    var id: String { dateString }
    let dateString: String // "yyyy-MM-dd"
    let month: Int
    let day: Int
    let weekdayIndex: Int // 0 = Mon ... 6 = Sun
    let weekIndex: Int    // 0 ... 4
    let phase: StudyPhase
    var task: String
    var note: String
    var isHighlightRed: Bool
    var isExamDay: Bool
    var isCompleted: Bool

    var shortDate: String {
        "\(month).\(day)"
    }

    var formattedTask: String {
        if task.contains("+") {
            return task.replacingOccurrences(of: "+", with: "\n+")
        }
        return task
    }

    var weekdayLabel: String {
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard weekdayIndex >= 0 && weekdayIndex < names.count else { return "" }
        return names[weekdayIndex]
    }

    var categorySymbol: String {
        if isExamDay { return "flag.checkered" }
        if isHighlightRed || task.contains("模拟") { return "doc.text.fill" }
        if task.contains("阅读") { return "book.fill" }
        if task.contains("听力") { return "headphones" }
        if task.contains("写作") || task.contains("翻译") { return "pencil.and.outline" }
        return "checkmark.circle"
    }
}

struct WeekMeta: Identifiable, Codable, Equatable {
    let id: Int
    let label: String
    let phase: StudyPhase
}

enum WindowLevelMode: String, Codable, CaseIterable {
    case desktop  // Stays on desktop above wallpaper/icons, below normal windows
    case floating // Always on top of normal windows

    var displayName: String {
        switch self {
        case .desktop: return "贴合桌面"
        case .floating: return "置顶悬浮"
        }
    }
}

enum WidgetAppearanceMode: String, Codable, CaseIterable {
    case pureWhite
    case light
    case dark

    var displayName: String {
        switch self {
        case .pureWhite: return "纯白卡片"
        case .light: return "浅色玻璃"
        case .dark: return "深色玻璃"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "pureWhite": self = .pureWhite
        case "light": self = .light
        case "dark": self = .dark
        default: self = .pureWhite
        }
    }
}

struct WidgetPreferences: Codable, Equatable {
    var widgetTitle: String = "备考安排 · 冲刺 12.12"
    var isCompactMode: Bool = false
    var windowLevelMode: WindowLevelMode = .desktop
    var isPositionLocked: Bool = false
    var appearanceMode: WidgetAppearanceMode = .pureWhite
    var opacity: Double = 1.0
    var isHidden: Bool = false
    var originX: Double?
    var originY: Double?
    var styleVersion: Int = 2
}
