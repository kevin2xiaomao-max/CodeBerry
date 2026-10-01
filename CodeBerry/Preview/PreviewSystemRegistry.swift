import Foundation

// MARK: - 4.0.3 S2 (P0-D): Foundation / System type registry
//
// The evaluator never executes real system APIs. Known system types get
// safe approximations: pure values, no side effects, deterministic where
// it matters (a random UUID per render would make previews flicker and
// tests flaky). Anything not covered here falls through to the normal
// unknown-identifier path — the registry is additive, never a lie.
//
// Severity is always `.info` (via `diagSystemApproximation`): a system
// approximation is never an error.

enum PreviewSystemRegistry {
    /// System types covered by the registry.
    static let knownTypes: Set<String> = [
        "Calendar", "Date", "Locale", "TimeZone", "UUID", "URL", "DateComponents",
    ]

    // MARK: - Static members: `Calendar.current`, `Locale.current`

    /// `Type.member` without a call, e.g. `Calendar.current`.
    /// Returns the stub value + a human-readable approximation note.
    static func staticMember(of type: String, name: String) -> (value: PreviewValue, note: String)? {
        switch (type, name) {
        case ("Calendar", "current"), ("Calendar", "autoupdatingCurrent"):
            return (.system("Calendar"), "当前日历")
        case ("Locale", "current"):
            return (.string("zh_CN"), "当前语言区域")
        case ("TimeZone", "current"):
            return (.string("Asia/Shanghai"), "固定时区近似")
        default:
            return nil
        }
    }

    // MARK: - Construction: `Date()`, `UUID()`, `URL(string:)`

    /// `Type(...)` construction. Arguments are already evaluated by the
    /// caller; the registry stays pure.
    static func construct(type: String,
                          args: [(label: String?, value: PreviewValue)])
        -> (value: PreviewValue, note: String)?
    {
        switch type {
        case "Date":
            return (.string(currentDateString()), "当前时间")
        case "UUID":
            return (.string(fixedUUIDString()), "固定占位 UUID")
        case "URL":
            if let s = args.first(where: { $0.label == "string" })?.value.display,
               !s.isEmpty {
                return (.string(s), "URL 字符串")
            }
            return (.string(""), "空 URL")
        case "Locale":
            if let id = args.first(where: { $0.label == "identifier" })?.value.display,
               !id.isEmpty {
                return (.string(id), "指定语言区域")
            }
            return (.string("zh_CN"), "当前语言区域")
        case "Calendar":
            return (.system("Calendar"), "当前日历")
        case "TimeZone":
            return (.string("Asia/Shanghai"), "固定时区近似")
        case "DateComponents":
            return (.system("DateComponents"), "日期组件")
        default:
            return nil
        }
    }

    // MARK: - Method calls on a stub: `Calendar.current.component(.hour, from: Date())`

    /// Method calls on a system stub value. Arguments are already evaluated
    /// by the caller; the registry stays pure.
    static func call(type: String, method: String,
                     args: [(label: String?, value: PreviewValue)])
        -> (value: PreviewValue, note: String)?
    {
        switch (type, method) {
        case ("Calendar", "component"):
            // `component(.hour, from: date)` — the greeting-prefix pattern.
            // Only `.hour` is meaningful for a preview; other units are an
            // honest 0 rather than a crash.
            let unit = args.first(where: { $0.label == nil })?.value.display
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if unit == "hour" {
                return (.number(Double(currentHour())), "使用当前时间近似")
            }
            return (.number(0), "非 hour 的 calendar component 近似为 0")
        case ("Calendar", "date"):
            // `date(byAdding:to:)` / `date(from:)` — approximate with the
            // date operand; the preview only needs a date-shaped value.
            if let to = args.first(where: { $0.label == "to" })?.value { return (to, "日期运算近似") }
            if let from = args.first(where: { $0.label == "from" })?.value { return (from, "日期运算近似") }
            return (.string(currentDateString()), "当前时间")
        case ("Calendar", "dateInterval"):
            // `dateInterval(of:for:)` — approximate with the `for:` date;
            // `?.start ?? today` then degrades gracefully to `today`.
            if let forDate = args.first(where: { $0.label == "for" })?.value {
                return (forDate, "dateInterval 近似为 for 日期")
            }
            return (.string(currentDateString()), "当前时间")
        case ("Calendar", "dateComponents"):
            return (.system("DateComponents"), "日期组件")
        case ("Calendar", "startOfDay"):
            if let forDate = args.first(where: { $0.label == "for" })?.value {
                return (forDate, "startOfDay 近似")
            }
            return (.string(currentDateString()), "当前时间")
        case ("Calendar", "isDateInToday"):
            return (.bool(false), "isDateInToday 近似为 false")
        case ("DateComponents", _):
            return (.system("DateComponents"), "日期组件")
        default:
            return nil
        }
    }

    // MARK: - Instance members on a stub: `UUID().uuidString`

    /// Instance members on a system stub value.
    static func member(of type: String, name: String) -> (value: PreviewValue, note: String)? {
        switch (type, name) {
        case (_, "uuidString"):
            return (.string(fixedUUIDString()), "固定占位 UUID")
        case (_, "isToday"):
            return (.bool(false), "isToday 近似为 false")
        default:
            return nil
        }
    }

    // MARK: - Time source

    /// Real clock. The evaluator memoizes approximations per evaluation
    /// pass, so one preview never sees the hour flip mid-render.
    static func currentHour() -> Int {
        Foundation.Calendar.autoupdatingCurrent.component(.hour, from: Date())
    }

    static func currentDateString() -> String {
        let f = DateFormatter()
        f.locale = Foundation.Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    /// Deterministic placeholder — a fresh UUID per render would make
    /// previews flicker and tests flaky.
    static func fixedUUIDString() -> String {
        "00000000-0000-4000-8000-000000000000"
    }
}
