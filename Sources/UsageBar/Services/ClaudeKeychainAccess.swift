import Foundation
import Security

enum ClaudeKeychainAccess {
    // Legacy login-Keychain ACL dialogs are not reliably controlled by LAContext.
    // This setting is process-wide, so serialize reads and restore it afterwards.
    private static let lock = NSLock()

    static func withInteractionPolicy<Value>(
        allowAuthenticationUI: Bool,
        getPolicy: () -> Bool? = {
            var allowed: DarwinBoolean = false
            guard SecKeychainGetUserInteractionAllowed(&allowed) == errSecSuccess else { return nil }
            return allowed.boolValue
        },
        setPolicy: (Bool) -> Bool = {
            SecKeychainSetUserInteractionAllowed($0) == errSecSuccess
        },
        operation: () -> Value?
    ) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let previousPolicy = getPolicy(), setPolicy(allowAuthenticationUI) else {
            // Fail closed: do not read if the no-dialog policy could not be set.
            return nil
        }
        defer { _ = setPolicy(previousPolicy) }
        return operation()
    }
}
