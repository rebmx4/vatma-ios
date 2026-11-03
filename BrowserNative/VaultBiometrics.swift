import Foundation
import LocalAuthentication
import Security

enum VaultBiometrics {
    private static let service = "ru.atma.browser.private-desktop"

    static func status() -> [String: Any] {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let kind: String
        switch context.biometryType {
        case .faceID: kind = "faceID"
        case .touchID: kind = "touchID"
        default: kind = "none"
        }
        return ["available": available, "kind": kind]
    }

    private static func account(_ body: [String: Any]) throws -> String {
        guard let value = body["vaultId"] as? String, UUID(uuidString: value) != nil else {
            throw BrowserFailure.invalid("Invalid private desktop identifier.")
        }
        return value
    }

    static func enroll(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) throws {
        let vaultId = try account(body)
        guard let encoded = body["secret"] as? String,
              let secret = Data(base64Encoded: encoded), secret.count == 32 else {
            throw BrowserFailure.invalid("Invalid private desktop key.")
        }
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            throw BrowserFailure.invalid("Face ID или Touch ID недоступен. Настройте биометрию и код устройства.")
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "Защитить приватный стол ATMA") { granted, error in
            guard granted else {
                DispatchQueue.main.async { reply(nil, error?.localizedDescription ?? "Биометрия не подтверждена.") }
                return
            }
            var accessError: Unmanaged<CFError>?
            guard let control = SecAccessControlCreateWithFlags(nil,
                    kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                    .biometryCurrentSet, &accessError) else {
                DispatchQueue.main.async { reply(nil, "Не удалось защитить ключ в Keychain.") }
                return
            }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: vaultId,
                kSecAttrAccessControl as String: control,
                kSecValueData as String: secret,
                kSecUseAuthenticationContext as String: context
            ]
            let result = SecItemAdd(query as CFDictionary, nil)
            DispatchQueue.main.async {
                if result == errSecSuccess { reply(["enrolled": true], nil) }
                else { reply(nil, "Не удалось сохранить ключ в Keychain (\(result)).") }
            }
        }
    }

    static func unlock(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) throws {
        let vaultId = try account(body)
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            throw BrowserFailure.invalid("Face ID или Touch ID недоступен.")
        }
        context.localizedReason = "Открыть приватный стол ATMA"
        DispatchQueue.global(qos: .userInitiated).async {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: vaultId,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: context
            ]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            DispatchQueue.main.async {
                guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
                    reply(nil, status == errSecItemNotFound
                          ? "Ключ приватного стола недоступен на этом устройстве."
                          : "Не удалось открыть приватный стол через биометрию (\(status)).")
                    return
                }
                reply(["secret": data.base64EncodedString()], nil)
            }
        }
    }
}
