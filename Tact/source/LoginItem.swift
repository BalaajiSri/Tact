import ServiceManagement
import SwiftUI

final class LoginItem: ObservableObject {
    @Published private(set) var status = SMAppService.Status.notRegistered
    @Published private(set) var errorMessage: String?

    private let service = SMAppService.mainApp
    private let configuredKey = "didConfigureOpenAtLogin"

    var enabled: Bool { status == .enabled || status == .requiresApproval }

    func configureDefault() {
        refresh()
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: configuredKey) else { return }
        defaults.set(true, forKey: configuredKey)
        if status == .notRegistered { setEnabled(true) }
    }

    func refresh() {
        let current = service.status
        if status != current { status = current }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(true, forKey: configuredKey)
        errorMessage = nil
        defer { refresh() }
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch {
            refresh()
            if self.enabled != enabled {
                errorMessage = error.localizedDescription
            }
        }
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
