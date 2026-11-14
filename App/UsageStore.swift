import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    static let allowedIntervals: [TimeInterval] = [60, 300, 600]
    static let maxBackoff: TimeInterval = 600

    @Published private(set) var report: UsageReport?
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var lastError: UsageError?
    @Published private(set) var refreshing = false
    @Published private(set) var consecutiveFailures = 0

    @Published var showRemaining: Bool { didSet { defaults.set(showRemaining, forKey: "showRemaining") } }
    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: "refreshInterval"); if loop != nil { reschedule() } }
    }

    private let service: UsageFetching
    private let defaults: UserDefaults
    private let clock: () -> Date
    private var loop: Task<Void, Never>?

    init(service: UsageFetching, defaults: UserDefaults = .standard, clock: @escaping () -> Date = { Date() }) {
        self.service = service
        self.defaults = defaults
        self.clock = clock
        self.showRemaining = defaults.bool(forKey: "showRemaining")
        let saved = defaults.double(forKey: "refreshInterval")
        self.refreshInterval = Self.allowedIntervals.contains(saved) ? saved : 60
    }

    deinit { loop?.cancel() }

    // MARK: Scheduling

    func start() {
        guard loop == nil else { return }
        reschedule()
    }

    /// Delay until the next automatic refresh: the user's interval, doubled per consecutive failure, capped.
    var nextDelay: TimeInterval {
        guard consecutiveFailures > 0 else { return refreshInterval }
        let factor = pow(2.0, Double(min(consecutiveFailures, 6)))
        return min(Self.maxBackoff, max(refreshInterval, refreshInterval * factor))
    }

    private func reschedule() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let delay = self.nextDelay
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    // MARK: Refresh

    /// Manual and automatic refreshes share this path. Overlapping calls are ignored.
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        let result = await service.fetch()
        switch result {
        case .success(let r):
            report = r
            lastSuccess = clock()
            lastError = nil
            consecutiveFailures = 0
        case .failure(let e):
            lastError = e
            consecutiveFailures += 1
        }
        refreshing = false
    }

    func refreshNow() { Task { await refresh() } }

    // MARK: Derived state

    /// Cached data is stale if the latest refresh failed, it is too old, or its reset time has already passed.
    func isStale(at now: Date = Date()) -> Bool {
        guard report != nil, let lastSuccess else { return false }
        if lastError != nil { return true }
        if now.timeIntervalSince(lastSuccess) > max(refreshInterval * 3, 180) { return true }
        if let reset = report?.session.resetDate, reset < now { return true }
        return false
    }

    func percent(for metric: UsageMetric) -> Int { showRemaining ? metric.percentRemaining : metric.percentUsed }

    func menuBarTitle(at now: Date = Date()) -> String {
        guard let report else { return "C: ?%" }
        let base = "C: \(percent(for: report.session))%"
        return isStale(at: now) ? base + " ⚠︎" : base
    }

    func accessibilityTitle(at now: Date = Date()) -> String {
        guard let report else { return "Claude usage unavailable" }
        let p = percent(for: report.session)
        let kind = showRemaining ? "remaining" : "used"
        return "Claude session usage: \(p) percent \(kind)" + (isStale(at: now) ? ", data may be out of date" : "")
    }
}
