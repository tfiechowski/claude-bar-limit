import Foundation
import ServiceManagement

/// Thin wrapper over SMAppService (macOS 13+). No helper app or extra permissions needed.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var needsApproval = false
    @Published private(set) var lastError: String?

    init() { isEnabled = false; refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = (status == .enabled)
        needsApproval = (status == .requiresApproval)
    }

    func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = "Couldn't change login item. Try moving ClaudeBarLimit to Applications."
        }
        refresh()
    }
}
