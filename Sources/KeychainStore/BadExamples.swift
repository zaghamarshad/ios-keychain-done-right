import Foundation
import Security

/// Real anti-patterns seen in iOS assessments. Every one of these has shipped
/// in a production app. They are collected here so you recognize them in code
/// review. Do not copy them into your app.
public enum BadExamples {

    // WRONG: UserDefaults is a plaintext plist. Anyone with a device backup,
    // or any process on a jailbroken device, reads it directly. Auth tokens
    // and secrets do not belong here. Use the Keychain instead.
    public static func saveTokenInUserDefaults(_ token: String) {
        UserDefaults.standard.set(token, forKey: "authToken")
    }

    // WRONG: secrets compiled into the binary. Running `strings` on the IPA
    // reveals them in seconds, and you cannot rotate them without shipping an
    // update. Issue short-lived tokens from your backend instead.
    public static let hardcodedAPISecret = "sk-live-do-not-hardcode-secrets"

    // WRONG: weak accessibility. kSecAttrAccessibleAfterFirstUnlock (and the
    // deprecated kSecAttrAccessibleAlways) keeps the item readable while the
    // device is locked. A stolen locked phone should not give up your tokens.
    // Prefer kSecAttrAccessibleWhenUnlockedThisDeviceOnly.
    public static func saveWithWeakAccessibility(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "example",
            kSecAttrAccount as String: "token",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    // WRONG: a boolean "biometry passed" flag stored in UserDefaults, checked
    // before showing sensitive screens. An attacker flips the flag and walks
    // in. Bind the secret itself to biometry with SecAccessControl instead,
    // so there is nothing to read without the biometric check.
    public static func fakeBiometricGate() -> Bool {
        UserDefaults.standard.bool(forKey: "biometryPassed")
    }
}
