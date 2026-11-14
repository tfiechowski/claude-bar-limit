import SwiftUI
import AppKit

struct UsageSnapshot {
    var used: Int?
    var reset: String?
    var error: String?
    var updated: Date?
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshot = UsageSnapshot()
    @Published var refreshing = false
    @AppStorage("showRemaining") var showRemaining = false

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var menuBarTitle: String {
        guard let used = snapshot.used else { return "C: ?%" }
        return "C: \(showRemaining ? 100 - used : used)%"
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task.detached(priority: .utility) {
            let result = Self.readUsage()
            await MainActor.run {
                self.snapshot = result
                self.refreshing = false
            }
        }
    }

    nonisolated private static func readUsage() -> UsageSnapshot {
        let locations = [
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
            NSHomeDirectory() + "/.local/bin/claude",
            NSHomeDirectory() + "/.claude/bin/claude"
        ]
        guard let path = locations.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return UsageSnapshot(error: "Claude Code CLI not found. Install Claude Code and sign in once.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-p", "/usage"]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + NSHomeDirectory() + "/.local/bin:" + NSHomeDirectory() + "/.claude/bin"
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            guard let line = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("Current session:") }) else {
                return UsageSnapshot(error: "Could not read usage. Check that Claude Code is signed in.")
            }
            let pattern = #"^Current session:\s*(\d+)% used(?:\s*·\s*resets\s*(.*))?"#
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let percentageRange = Range(match.range(at: 1), in: line),
                  let used = Int(line[percentageRange]) else {
                return UsageSnapshot(error: "Unexpected Claude usage format.")
            }
            var reset: String? = nil
            if match.range(at: 2).location != NSNotFound,
               let resetRange = Range(match.range(at: 2), in: line) {
                reset = String(line[resetRange])
            }
            return UsageSnapshot(used: min(100, max(0, used)), reset: reset, updated: Date())
        } catch {
            return UsageSnapshot(error: "Failed to launch Claude Code: \(error.localizedDescription)")
        }
    }
}

@main
struct ClaudeLimitApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra(store.menuBarTitle) {
            if let used = store.snapshot.used {
                Text("Current session: \(used)% used")
                Text("Remaining: \(100 - used)%")
                if let reset = store.snapshot.reset {
                    Text("Resets: \(reset)")
                }
            } else {
                Text(store.snapshot.error ?? "Loading usage…")
            }
            Divider()
            Button(store.refreshing ? "Refreshing…" : "Refresh now") { store.refresh() }
                .disabled(store.refreshing)
            Toggle("Show remaining percentage", isOn: $store.showRemaining)
            Link("Open Claude billing", destination: URL(string: "https://claude.ai/settings/billing")!)
            Link("Open Claude", destination: URL(string: "https://claude.ai")!)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
