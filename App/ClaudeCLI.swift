import Foundation

// MARK: - Errors

enum UsageError: Error, Equatable {
    case cliNotFound
    case notAuthenticated
    case timedOut
    case offline
    case processFailed(status: Int32)
    case launchFailed(String)
    case unexpectedFormat
    case noSubscriptionData

    /// Short, friendly, actionable text. Never includes raw CLI output.
    var message: String {
        switch self {
        case .cliNotFound:
            return "Claude Code not found. Install it from https://docs.claude.com/en/docs/claude-code, then sign in."
        case .notAuthenticated:
            return "Claude Code isn't signed in. Run `claude` in Terminal and sign in once."
        case .timedOut:
            return "Claude Code took too long to respond. Will retry."
        case .offline:
            return "Couldn't reach Claude (offline?). Will retry."
        case .processFailed(let status):
            return "Claude Code exited with an error (code \(status)). Will retry."
        case .launchFailed:
            return "Couldn't start Claude Code. Check that the installed binary is executable."
        case .unexpectedFormat:
            return "Claude Code's usage output changed and couldn't be read. Please update ClaudeBarLimit or report an issue."
        case .noSubscriptionData:
            return "No usage limits reported. Limits are only shown when Claude Code is signed in with a Claude subscription."
        }
    }
}

// MARK: - Process running

struct ProcessResult: Equatable {
    var status: Int32?        // nil if it never ran or was killed on timeout
    var output: String        // stdout + stderr, capped
    var timedOut: Bool
    var truncated: Bool
    var launchError: String?
}

protocol ProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], environment: [String: String],
             workingDirectory: URL, timeout: TimeInterval, maxOutputBytes: Int) async -> ProcessResult
}

/// Runs a child process with no shell, a hard timeout and a capped output buffer.
/// stdout and stderr share one pipe that is drained concurrently, so large output cannot deadlock.
struct SystemProcessRunner: ProcessRunning {
    func run(executable: URL, arguments: [String], environment: [String: String],
             workingDirectory: URL, timeout: TimeInterval, maxOutputBytes: Int) async -> ProcessResult {
        await withCheckedContinuation { cont in
            let job = Job(maxBytes: maxOutputBytes, continuation: cont)
            job.start(executable: executable, arguments: arguments, environment: environment,
                      workingDirectory: workingDirectory, timeout: timeout)
        }
    }

    private final class Job: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var truncated = false
        private var timedOut = false
        private var finished = false
        private var terminated = false
        private var eof = false
        private var status: Int32?
        private let maxBytes: Int
        private let continuation: CheckedContinuation<ProcessResult, Never>
        private let process = Process()
        private let pipe = Pipe()

        init(maxBytes: Int, continuation: CheckedContinuation<ProcessResult, Never>) {
            self.maxBytes = maxBytes
            self.continuation = continuation
        }

        func start(executable: URL, arguments: [String], environment: [String: String],
                   workingDirectory: URL, timeout: TimeInterval) {
            process.executableURL = executable
            process.arguments = arguments
            process.environment = environment
            process.currentDirectoryURL = workingDirectory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                self.lock.lock()
                if data.isEmpty {
                    self.eof = true
                } else if self.buffer.count < self.maxBytes {
                    let room = self.maxBytes - self.buffer.count
                    self.buffer.append(data.prefix(room))
                    if data.count > room { self.truncated = true }
                } else {
                    self.truncated = true
                }
                let isEOF = self.eof
                self.lock.unlock()
                if isEOF { handle.readabilityHandler = nil; self.maybeFinish() }
            }
            process.terminationHandler = { p in
                self.lock.lock()
                self.terminated = true
                self.status = self.timedOut ? nil : p.terminationStatus
                self.lock.unlock()
                // Grace period: if a grandchild keeps the pipe open, don't wait forever.
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { self.finish(force: true) }
                self.maybeFinish()
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                finish(launchError: error.localizedDescription)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                self.lock.lock()
                let alreadyDone = self.finished || self.terminated
                if !alreadyDone { self.timedOut = true }
                self.lock.unlock()
                guard !alreadyDone else { return }
                self.process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if self.process.isRunning { kill(self.process.processIdentifier, SIGKILL) }
                }
            }
        }

        private func maybeFinish() {
            lock.lock()
            let ready = terminated && eof
            lock.unlock()
            if ready { finish(force: false) }
        }

        private func finish(force: Bool = false, launchError: String? = nil) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            pipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            let result = ProcessResult(
                status: status,
                output: String(decoding: buffer, as: UTF8.self),
                timedOut: timedOut,
                truncated: truncated,
                launchError: launchError
            )
            lock.unlock()
            try? pipe.fileHandleForReading.close()
            continuation.resume(returning: result)
        }
    }
}

// MARK: - Executable discovery

enum ClaudeLocator {
    static func candidatePaths(home: String, pathEnv: String?) -> [String] {
        var c = [
            "\(home)/.local/bin/claude",          // native installer
            "\(home)/.claude/local/claude",       // legacy local install
            "\(home)/.claude/bin/claude",
            "/opt/homebrew/bin/claude",           // Homebrew (Apple Silicon)
            "/usr/local/bin/claude",              // Homebrew (Intel) / npm global
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude",
        ]
        // A GUI app has a minimal PATH, but include whatever it has.
        c += (pathEnv ?? "").split(separator: ":").map { "\($0)/claude" }
        return c
    }

    /// Auto-discovery first; the user-configured path is used only if that fails.
    static func find(home: String = NSHomeDirectory(),
                     pathEnv: String? = ProcessInfo.processInfo.environment["PATH"],
                     customPath: String? = nil,
                     isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL? {
        var seen = Set<String>()
        var all = candidatePaths(home: home, pathEnv: pathEnv)
        if let customPath, !customPath.isEmpty { all.append((customPath as NSString).expandingTildeInPath) }
        for path in all where seen.insert(path).inserted {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            if isExecutable(resolved) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
}

// MARK: - Service

protocol UsageFetching: Sendable {
    func fetch() async -> Result<UsageReport, UsageError>
}

struct ClaudeUsageService: UsageFetching {
    var runner: ProcessRunning = SystemProcessRunner()
    var locate: @Sendable () -> URL? = {
        ClaudeLocator.find(customPath: UserDefaults.standard.string(forKey: "customCLIPath"))
    }
    var timeout: TimeInterval = 15
    var maxOutputBytes = 256 * 1024
    var now: @Sendable () -> Date = { Date() }

    func fetch() async -> Result<UsageReport, UsageError> {
        guard let exe = locate() else { return .failure(.cliNotFound) }
        let home = NSHomeDirectory()
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                       "\(home)/.local/bin", "\(home)/.claude/bin"].joined(separator: ":")
        env["NO_COLOR"] = "1"

        // `/usage` is a local slash command: it prints limits and sends no prompt to the model.
        // --no-session-persistence stops the CLI from writing a transcript file on every poll.
        // Older CLIs may not know that flag, so fall back to plain `-p /usage` if it is rejected.
        func run(_ args: [String]) async -> ProcessResult {
            await runner.run(executable: exe, arguments: args, environment: env,
                             workingDirectory: URL(fileURLWithPath: home),
                             timeout: timeout, maxOutputBytes: maxOutputBytes)
        }
        var result = await run(["-p", "--no-session-persistence", "/usage"])
        let lower = result.output.lowercased()
        if (result.status ?? 0) != 0, lower.contains("no-session-persistence"),
           lower.contains("unknown") || lower.contains("unrecognized") || lower.contains("invalid") {
            result = await run(["-p", "/usage"])
        }
        return Self.interpret(result, now: now())
    }

    static func interpret(_ r: ProcessResult, now: Date) -> Result<UsageReport, UsageError> {
        if let e = r.launchError { return .failure(.launchFailed(e)) }
        if r.timedOut { return .failure(.timedOut) }

        // Try parsing first: the output is authoritative if it contains usage lines.
        switch Result(catching: { try UsageParser.parse(r.output, now: now) }) {
        case .success(let report): return .success(report)
        case .failure(let err):
            let lower = r.output.lowercased()
            if lower.contains("not logged in") || lower.contains("/login") || lower.contains("please run")
                || lower.contains("invalid api key") || lower.contains("authentication") || lower.contains("unauthorized") {
                return .failure(.notAuthenticated)
            }
            if ["enotfound", "econnrefused", "econnreset", "etimedout", "network", "offline", "could not connect", "unable to connect"]
                .contains(where: lower.contains) {
                return .failure(.offline)
            }
            if let s = r.status, s != 0 { return .failure(.processFailed(status: s)) }
            if (err as? UsageParseError) == .noUsageData {
                // Ran fine but printed no limits (e.g. API-key auth).
                return .failure(lower.contains("api key") || lower.contains("api usage") || lower.contains("console") ? .noSubscriptionData : .unexpectedFormat)
            }
            return .failure(.unexpectedFormat)
        }
    }
}
