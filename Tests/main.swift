import Foundation

// Minimal dependency-free test harness (works with just the Command Line Tools).
nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0
func check(_ cond: @autoclosure () async -> Bool, _ msg: String, line: Int = #line) async {
    checks += 1
    if !(await cond()) { failures += 1; print("  FAIL (line \(line)): \(msg)") }
}
func test(_ name: String, _ body: () async throws -> Void) async {
    print("• \(name)")
    do { try await body() } catch { failures += 1; print("  FAIL: threw \(error)") }
}
func fixture(_ n: String) -> String {
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    return try! String(contentsOf: dir.appendingPathComponent(n), encoding: .utf8)
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 23, minute: 30))!

await test("parser: full real-world output") {
    let r = try UsageParser.parse(fixture("usage_full.txt"), now: now)
    await check(r.session.percentUsed == 36, "session 36")
    await check(r.session.percentRemaining == 64, "remaining 64")
    await check(r.weekly?.percentUsed == 30, "weekly 30")
    await check(r.extraWeekly.count == 1 && r.extraWeekly[0].percentUsed == 0, "extra model week")
    let expected = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 2, minute: 10))!
    await check(r.session.resetDate == expected, "session reset date \(String(describing: r.session.resetDate))")
    await check(r.session.resetText == "Nov 15 at 2:10am (Europe/Warsaw)", "reset text preserved")
    let wk = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 11))!
    await check(r.weekly?.resetDate == wk, "weekly reset date")
}
await test("parser: ANSI + time-only reset") {
    let r = try UsageParser.parse(fixture("usage_ansi_timeonly.txt"), now: now)
    await check(r.session.percentUsed == 81, "81")
    let expected = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 2))!
    await check(r.session.resetDate == expected, "next 2am")
    await check(r.weekly == nil, "no weekly")
}
await test("parser: missing reset, no weekly") {
    let r = try UsageParser.parse(fixture("usage_no_reset.txt"), now: now)
    await check(r.session.percentUsed == 5 && r.session.resetText == nil && r.session.resetDate == nil, "no reset")
}
await test("parser: year rollover and unparseable reset keep original text") {
    let dec = cal.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12))!
    let r = try UsageParser.parse("Current session: 10% used · resets Jan 2 at 1am (Europe/Warsaw)", now: dec)
    await check(r.session.resetDate == cal.date(from: DateComponents(year: 2027, month: 1, day: 2, hour: 1)), "next year")
    let r2 = try UsageParser.parse("Current session: 10% used · resets tomorrow-ish", now: now)
    await check(r2.session.resetDate == nil && r2.session.resetText == "tomorrow-ish", "raw text kept")
    let r3 = try UsageParser.parse("Current session: 10% used · resets 2am (Nowhere/Land)", now: now)
    await check(r3.session.resetDate == nil, "bad tz -> no date")
}
await test("parser: clamps and errors") {
    let r = try UsageParser.parse("Current session: 140% used", now: now)
    await check(r.session.percentUsed == 100, "clamped")
    do { _ = try UsageParser.parse(fixture("changed_format.txt"), now: now); await check(false, "should throw") }
    catch { await check((error as? UsageParseError) == .noUsageData, "noUsageData") }
    do { _ = try UsageParser.parse("Current session: lots used", now: now); await check(false, "should throw") }
    catch { await check((error as? UsageParseError) == .unexpectedFormat, "unexpectedFormat") }
}

await test("service: error classification") {
    func run(_ out: String, status: Int32? = 0, timedOut: Bool = false) -> Result<UsageReport, UsageError> {
        ClaudeUsageService.interpret(ProcessResult(status: status, output: out, timedOut: timedOut, truncated: false, launchError: nil), now: now)
    }
    if case .success = run(fixture("usage_full.txt")) {} else { await check(false, "success expected") }
    await check(run(fixture("not_logged_in.txt"), status: 1) == .failure(.notAuthenticated), "auth")
    await check(run("", timedOut: true) == .failure(.timedOut), "timeout")
    await check(run("getaddrinfo ENOTFOUND api.anthropic.com", status: 1) == .failure(.offline), "offline")
    await check(run("boom", status: 7) == .failure(.processFailed(status: 7)), "nonzero")
    await check(run(fixture("changed_format.txt")) == .failure(.unexpectedFormat), "format")
}
await test("locator: discovery order, symlinks, custom path last") {
    let found = ClaudeLocator.find(home: "/h", pathEnv: "/x", customPath: "/custom/claude", isExecutable: { $0 == "/opt/homebrew/bin/claude" })
    await check(found?.path == "/opt/homebrew/bin/claude", "auto beats custom")
    let c = ClaudeLocator.find(home: "/h", pathEnv: "", customPath: "/custom/claude", isExecutable: { $0 == "/custom/claude" })
    await check(c?.path == "/custom/claude", "custom fallback")
    await check(ClaudeLocator.find(home: "/h", pathEnv: "", customPath: nil, isExecutable: { _ in false }) == nil, "none")
}

await test("runner: success, timeout, huge output, missing binary") {
    let r = SystemProcessRunner()
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let ok = await r.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["hi"], environment: [:], workingDirectory: home, timeout: 5, maxOutputBytes: 1000)
    await check(ok.status == 0 && ok.output == "hi\n" && !ok.timedOut, "echo")
    let t0 = Date()
    let to = await r.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], environment: [:], workingDirectory: home, timeout: 0.5, maxOutputBytes: 1000)
    await check(to.timedOut && Date().timeIntervalSince(t0) < 5, "timeout kills child quickly")
    let big = await r.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "yes | head -c 5000000"], environment: [:], workingDirectory: home, timeout: 10, maxOutputBytes: 4096)
    await check(big.status == 0 && big.output.utf8.count == 4096 && big.truncated, "cap, no deadlock")
    let miss = await r.run(executable: URL(fileURLWithPath: "/nonexistent/claude"), arguments: [], environment: [:], workingDirectory: home, timeout: 2, maxOutputBytes: 10)
    await check(miss.launchError != nil, "launch error")
}

// Store tests
actor Script: UsageFetching {
    var results: [Result<UsageReport, UsageError>]
    var calls = 0
    var delay: UInt64 = 0
    init(_ r: [Result<UsageReport, UsageError>], delay: UInt64 = 0) { results = r; self.delay = delay }
    func fetch() async -> Result<UsageReport, UsageError> {
        calls += 1
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return results.count > 1 ? results.removeFirst() : results[0]
    }
    func callCount() -> Int { calls }
}
let sample = UsageReport(session: UsageMetric(label: "session", percentUsed: 19, resetText: nil, resetDate: nil), weekly: nil, extraWeekly: [])

await test("store: title modes, stale marking, backoff") {
    let d = UserDefaults(suiteName: "claudebarlimit.tests.\(UUID())")!
    let svc = Script([.success(sample), .failure(.timedOut)])
    let store = await UsageStore(service: svc, defaults: d, clock: { now })
    await check(store.menuBarTitle(at: now) == "C: ?%", "unavailable")
    await store.refresh()
    await check(store.menuBarTitle(at: now) == "C: 19%", "used")
    await MainActor.run { store.showRemaining = true }
    await check(store.menuBarTitle(at: now) == "C: 81%", "remaining")
    await check(d.bool(forKey: "showRemaining"), "persisted")
    await store.refresh()
    await check(store.menuBarTitle(at: now).hasSuffix("⚠︎"), "stale after failure")
    await check(store.isStale(at: now), "isStale")
    await check(store.nextDelay == 120, "backoff 60 -> 120")
    await store.refresh(); await store.refresh()
    await check(store.nextDelay == 480 , "backoff x8 = \(await store.nextDelay)")
    for _ in 0..<5 { await store.refresh() }
    await check(store.nextDelay == 600, "capped")
}
await test("store: stale when too old or reset passed; no overlap") {
    let d = UserDefaults(suiteName: "claudebarlimit.tests.\(UUID())")!
    let past = UsageReport(session: UsageMetric(label: "session", percentUsed: 50, resetText: "x", resetDate: now.addingTimeInterval(-10)), weekly: nil, extraWeekly: [])
    let store = await UsageStore(service: Script([.success(past)]), defaults: d, clock: { now })
    await store.refresh()
    await check(store.isStale(at: now), "reset passed => stale")
    let slow = Script([.success(sample)], delay: 200_000_000)
    let s2 = await UsageStore(service: slow, defaults: d, clock: { now })
    async let a: Void = s2.refresh(); async let b: Void = s2.refresh(); _ = await (a, b)
    await check(slow.callCount() == 1, "overlapping refresh ignored (calls=\(await slow.callCount()))")
    await check(s2.isStale(at: now.addingTimeInterval(3600)), "old => stale")
}
await test("formatting") {
    await check(Formatting.countdown(to: now.addingTimeInterval(2*3600+14*60+5), from: now) == "2h 14m", "h m")
    await check(Formatting.countdown(to: now.addingTimeInterval(3*86400+4*3600), from: now) == "3d 4h", "d h")
    await check(Formatting.countdown(to: now.addingTimeInterval(20), from: now) == "<1m", "<1m")
    let raw = UsageMetric(label: "s", percentUsed: 1, resetText: "weird text", resetDate: nil)
    await check(Formatting.resetLine(raw, now: now) == "Resets weird text", "raw")
}

print(failures == 0 ? "\nAll \(checks) checks passed." : "\n\(failures) of \(checks) checks FAILED.")
exit(failures == 0 ? 0 : 1)
