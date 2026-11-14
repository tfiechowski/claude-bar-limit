import Foundation

enum Formatting {
    /// "2h 14m", "45m", "3d 4h", "<1m"
    static func countdown(to date: Date, from now: Date) -> String {
        let secs = Int(date.timeIntervalSince(now))
        guard secs > 0 else { return "now" }
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return m > 0 ? "\(m)m" : "<1m"
    }

    static func relativeAge(of date: Date, now: Date) -> String {
        let secs = Int(now.timeIntervalSince(date))
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        if secs < 86400 { return "\(secs / 3600)h ago" }
        return "\(secs / 86400)d ago"
    }

    /// Reset line: parsed times are shown as a countdown plus local clock time; otherwise the CLI's own text, verbatim.
    static func resetLine(_ m: UsageMetric, now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        if let d = m.resetDate {
            if d <= now { return "Reset time has passed" }
            let f = DateFormatter()
            f.locale = locale; f.timeZone = timeZone
            f.setLocalizedDateFormatFromTemplate(Calendar.current.isDate(d, inSameDayAs: now) ? "jmm" : "MMMd jmm")
            return "Resets in \(countdown(to: d, from: now)) (\(f.string(from: d)))"
        }
        return m.resetText.map { "Resets \($0)" }
    }
}
