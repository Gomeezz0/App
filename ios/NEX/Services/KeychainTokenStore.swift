import Foundation
import NEXCore
import Security

/// Guarda la sesión en el Keychain (solo accesible con el dispositivo desbloqueado al menos una vez,
/// para que la navegación con pantalla bloqueada pueda renovar el token).
final class KeychainTokenStore: TokenStore {
    private let service = "app.nex.ios.session"
    private let account = "tokens"
    private let lock = NSLock()
    private var cache: AuthTokens?
    private var loaded = false

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> AuthTokens? {
        lock.lock()
        defer { lock.unlock() }
        if loaded { return cache }
        loaded = true
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            cache = try? JSONDecoder().decode(AuthTokens.self, from: data)
        }
        return cache
    }

    func save(_ tokens: AuthTokens) {
        lock.lock()
        defer { lock.unlock() }
        cache = tokens
        loaded = true
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache = nil
        loaded = true
        SecItemDelete(baseQuery as CFDictionary)
    }
}
