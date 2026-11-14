import SwiftUI
import AppKit

@main
struct ClaudeLimitApp: App {
    @StateObject private var store = UsageStore(service: ClaudeUsageService())

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Text(store.menuBarTitle())
                .accessibilityLabel(store.accessibilityTitle())
                .task { store.start() }
        }
    }
}

struct MenuContent: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        let now = Date()
        Text(headerText(now))
        if let report = store.report {
            metricRows(title: "Current session (5h)", report.session, now: now)
            if let weekly = report.weekly {
                metricRows(title: "Weekly (7d)", weekly, now: now)
            }
            ForEach(report.extraWeekly, id: \.label) { m in
                Text("\(m.label.capitalized): \(store.percent(for: m))% \(store.showRemaining ? "remaining" : "used")")
            }
        }
        if let err = store.lastError {
            Divider()
            Text(err.message)
        }
        Divider()
        Button(store.refreshing ? "Refreshing…" : "Refresh now") { store.refreshNow() }
            .keyboardShortcut("r")
            .disabled(store.refreshing)
        Toggle("Show remaining in menu bar", isOn: $store.showRemaining)
        Picker("Refresh every", selection: $store.refreshInterval) {
            Text("1 minute").tag(60.0)
            Text("5 minutes").tag(300.0)
            Text("10 minutes").tag(600.0)
        }
        Divider()
        Link("Open Claude billing", destination: URL(string: "https://claude.ai/settings/billing")!)
        Link("Open Claude", destination: URL(string: "https://claude.ai")!)
        Divider()
        Text("Unofficial · not affiliated with Anthropic")
        Button("Quit ClaudeLimit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func headerText(_ now: Date) -> String {
        guard let t = store.lastSuccess else { return store.refreshing ? "ClaudeLimit — loading…" : "ClaudeLimit — no data yet" }
        let age = Formatting.relativeAge(of: t, now: now)
        return store.isStale(at: now) ? "ClaudeLimit — STALE, last updated \(age)" : "ClaudeLimit — updated \(age)"
    }

    @ViewBuilder
    private func metricRows(title: String, _ m: UsageMetric, now: Date) -> some View {
        Text("\(title): \(store.percent(for: m))% \(store.showRemaining ? "remaining" : "used")")
        Text("   \(store.showRemaining ? m.percentUsed : m.percentRemaining)% \(store.showRemaining ? "used" : "remaining")")
        if let r = Formatting.resetLine(m, now: now) { Text("   \(r)") }
    }
}
