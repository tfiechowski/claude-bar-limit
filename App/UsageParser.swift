import Foundation

/// One usage meter, e.g. the 5-hour session or the weekly limit.
struct UsageMetric: Equatable {
    var label: String          // e.g. "session", "week (all models)"
    var percentUsed: Int       // 0...100
    var resetText: String?     // original text after "resets", safe to display as-is
    var resetDate: Date?       // only set when the text could be parsed reliably

    var percentRemaining: Int { 100 - percentUsed }
}

struct UsageReport: Equatable {
    var session: UsageMetric
    var weekly: UsageMetric?        // "Current week (all models)"
    var extraWeekly: [UsageMetric]  // per-model weekly meters, e.g. "Current week (Opus)"
}

enum UsageParseError: Error, Equatable {
    /// Output did not contain any "Current ..." usage lines.
    case noUsageData
    /// A usage line was found but the percentage could not be read.
    case unexpectedFormat
}

/// Pure parsing of `claude -p "/usage"` output. No I/O.
enum UsageParser {
    static func parse(_ raw: String, now: Date = Date()) throws -> UsageReport {
        let text = stripANSI(raw)
        var session: UsageMetric?
        var weekly: UsageMetric?
        var extra: [UsageMetric] = []
        var sawUsageLine = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix("current ") else { continue }
            guard let m = lineRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                let l = line.lowercased()
                if line.contains("%") || l.hasPrefix("current session") || l.hasPrefix("current week") { sawUsageLine = true }
                continue
            }
            sawUsageLine = true
            let kind = group(m, 1, in: line)?.lowercased() ?? ""
            let qualifier = group(m, 2, in: line)
            guard let pctText = group(m, 3, in: line), let pct = Int(pctText) else { continue }
            let resetText = group(m, 4, in: line).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
            let metric = UsageMetric(
                label: qualifier.map { "\(kind) (\($0))" } ?? kind,
                percentUsed: min(100, max(0, pct)),
                resetText: resetText,
                resetDate: resetText.flatMap { parseReset($0, now: now) }
            )
            if kind == "session" {
                if session == nil { session = metric }
            } else if kind == "week" {
                if qualifier?.lowercased() == "all models" || qualifier == nil {
                    if weekly == nil { weekly = metric }
                } else {
                    extra.append(metric)
                }
            }
        }

        guard let session else {
            throw sawUsageLine ? UsageParseError.unexpectedFormat : UsageParseError.noUsageData
        }
        return UsageReport(session: session, weekly: weekly, extraWeekly: extra)
    }

    // MARK: - Internals

    // "Current session: 36% used · resets Nov 15 at 2:10am (Europe/Warsaw)"
    // "Current week (all models): 30% used · resets Nov 20 at 11am (Europe/Warsaw)"
    private static let lineRegex = try! NSRegularExpression(
        pattern: #"^current\s+(session|week)(?:\s*\(([^)]*)\))?\s*:\s*(\d{1,3})\s*%\s*used(?:\s*[·•|\-–—]\s*resets?\s*(.*))?$"#,
        options: [.caseInsensitive]
    )

    private static let ansiRegex = try! NSRegularExpression(pattern: #"\x{1B}\[[0-9;?]*[ -/]*[@-~]|\x{1B}\][^\x{07}]*\x{07}"#)

    static func stripANSI(_ s: String) -> String {
        ansiRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String? {
        guard m.range(at: i).location != NSNotFound, let r = Range(m.range(at: i), in: s) else { return nil }
        return String(s[r])
    }

    // "Nov 15 at 2:10am (Europe/Warsaw)", "2am (Europe/Warsaw)", "Nov 20 at 11am"
    private static let resetRegex = try! NSRegularExpression(
        pattern: #"^(?:([A-Za-z]{3,9})\s+(\d{1,2})(?:,?\s+(\d{4}))?\s+(?:at\s+)?)?(\d{1,2})(?::(\d{2}))?\s*([ap]m)\s*(?:\(([^)]+)\))?\s*$"#,
        options: [.caseInsensitive]
    )

    /// Returns a date only when the text is unambiguous; otherwise nil (caller shows the original text).
    static func parseReset(_ text: String, now: Date) -> Date? {
        guard let m = resetRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let tzName = group(m, 7, in: text)
        let tz: TimeZone
        if let tzName { guard let t = TimeZone(identifier: tzName) else { return nil }; tz = t } else { tz = .current }

        guard var hour = group(m, 4, in: text).flatMap(Int.init), (1...12).contains(hour) else { return nil }
        let minute = group(m, 5, in: text).flatMap(Int.init) ?? 0
        guard (0..<60).contains(minute), let ampm = group(m, 6, in: text)?.lowercased() else { return nil }
        if ampm == "pm", hour != 12 { hour += 12 }
        if ampm == "am", hour == 12 { hour = 0 }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = DateComponents()
        comps.hour = hour; comps.minute = minute; comps.second = 0

        if let monthText = group(m, 1, in: text), let day = group(m, 2, in: text).flatMap(Int.init) {
            guard let month = monthNumber(monthText) else { return nil }
            comps.month = month; comps.day = day
            if let y = group(m, 3, in: text).flatMap(Int.init) {
                comps.year = y
                return cal.date(from: comps)
            }
            // No year: next occurrence of that date, tolerating a small past offset.
            let thisYear = cal.component(.year, from: now)
            for y in [thisYear, thisYear + 1] {
                comps.year = y
                if let d = cal.date(from: comps), d > now.addingTimeInterval(-3600 * 24) { return d }
            }
            return nil
        }
        // Time only: next occurrence after now.
        return cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
    }

    private static func monthNumber(_ s: String) -> Int? {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let i = names.firstIndex(of: String(s.lowercased().prefix(3))) else { return nil }
        return i + 1
    }
}
