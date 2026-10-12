import Foundation
import Security

/// Errors from Keychain operations.
public enum KeychainError: Error, Equatable {
    case itemNotFound
    case unexpectedStatus(OSStatus)
}

/// A thin, honest wrapper around the Keychain Services API.
///
/// The default accessibility is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
/// the item can only be read while the device is unlocked, and it never
/// migrates to a new device through iCloud or local backups. That is the right
/// default for auth tokens and other secrets.
///
/// There are no force-unwraps and no ignored errors: every SecItem call has
/// its status checked.
public struct KeychainStore {

    private let service: String

    public init(service: String) {
        self.service = service
    }

    // MARK: - Save

    /// Saves data, updating the item if it already exists.
    public func save(_ data: Data, for account: String) throws {
        var query = baseQuery(for: account)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            try update(data, for: account)
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Saves data so it can only be read after a biometric check (Face ID /
    /// Touch ID). On devices without biometry enrolled, fall back to
    /// `save(_:for:)` and handle the choice in your UI.
    public func saveRequiringBiometry(_ data: Data, for account: String) throws {
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryAny,
            nil
        ) else {
            throw KeychainError.unexpectedStatus(errSecParam)
        }

        var query = baseQuery(for: account)
        query[kSecAttrAccessControl as String] = accessControl
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            try update(data, for: account)
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Read

    /// Reads data for an account. Throws `itemNotFound` when nothing is stored.
    public func read(for account: String) throws -> Data {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedStatus(errSecInternalError)
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Update

    /// Replaces the data for an existing item.
    public func update(_ data: Data, for account: String) throws {
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Delete

    /// Deletes the item. Deleting something that is not there is not an error.
    public func delete(for account: String) throws {
        let query = baseQuery(for: account)
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Private

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
