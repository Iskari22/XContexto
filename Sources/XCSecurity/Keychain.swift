import Foundation
import Security
import XCCore

/// Guarda la clave de la API en el Llavero (nunca en archivos ni en UserDefaults).
public enum KeychainStore {
    public static let service = "com.xcontexto.anthropic"
    public static let account = "api-key"
    /// Compartido entre la app y sus extensiones cuando se configura el Keychain Sharing.
    public static let accessGroup: String? = nil

    private static func baseQuery() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let g = accessGroup { q[kSecAttrAccessGroup as String] = g }
        return q
    }

    public static func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-ant-") else { throw XCError.blockedByPolicy("la clave no parece de Anthropic (sk-ant-…)") }
        SecItemDelete(baseQuery() as CFDictionary)
        var q = baseQuery()
        q[kSecValueData as String] = Data(trimmed.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw XCError.blockedByPolicy("Llavero: error \(status)") }
    }

    public static func load() -> String? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public static func delete() { SecItemDelete(baseQuery() as CFDictionary) }

    /// Orden de búsqueda: Llavero → variable de entorno ANTHROPIC_API_KEY (útil para la CLI).
    public static func resolveAPIKey() throws -> String {
        if let k = load(), !k.isEmpty { return k }
        if let k = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !k.isEmpty { return k }
        throw XCError.missingAPIKey
    }
}
