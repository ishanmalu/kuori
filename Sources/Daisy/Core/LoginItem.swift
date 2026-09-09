import Foundation
import ServiceManagement

/// "Open at Login" via SMAppService (macOS 13+). No-op meaning outside a real
/// .app bundle, but harmless.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    static func toggle() -> Bool {
        do {
            if isEnabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("Daisy login item: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
