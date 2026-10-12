# iOS Keychain, Done Right

A correct Keychain wrapper for iOS, plus the wrong patterns it replaces. The wrong ones are real: they show up in production apps during assessments.

## How to use it

```swift
let store = KeychainStore(service: "com.yourapp.tokens")

// Save an auth token (readable only while unlocked, never leaves the device)
try store.save(tokenData, for: "accessToken")

// Save something that needs Face ID / Touch ID to read
try store.saveRequiringBiometry(secretData, for: "recoveryKey")

// Read it back
let token = try store.read(for: "accessToken")

// Clean up on logout
try store.delete(for: "accessToken")
```

Every operation throws `KeychainError.itemNotFound` or `KeychainError.unexpectedStatus(OSStatus)` instead of failing silently.

## Which accessibility level to use

| Level | Readable when | Leaves device in backups? | Use for |
|---|---|---|---|
| `WhenUnlockedThisDeviceOnly` | Device unlocked | No | Auth tokens, secrets. **The default here.** |
| `WhenUnlocked` | Device unlocked | Yes, in encrypted backups | Data the user expects to survive a device change |
| `AfterFirstUnlock` | After first unlock since boot | Depends | Background refresh tokens. Weaker: readable on a locked phone. |
| `AfterFirstUnlockThisDeviceOnly` | After first unlock since boot | No | Same tradeoff, no migration |
| `Always` / `AlwaysThisDeviceOnly` | Deprecated by Apple | - | Do not use. Kept readable on a locked device. |

Rule of thumb: start with `WhenUnlockedThisDeviceOnly` for anything secret. Loosen it only when you have a concrete reason (background fetch, device migration), and document why.

## The biometric option

`saveRequiringBiometry` attaches a `SecAccessControl` with `.biometryAny` to the item. The Keychain itself enforces the check: without Face ID or Touch ID, the data cannot be read, even by your own app. This is different from the common anti-pattern of storing a "biometryPassed = true" flag in UserDefaults and checking it before showing a screen. Flags can be flipped; Keychain access control cannot be bypassed without the biometric.

Note: `.biometryAny` accepts any enrolled biometric. If your threat model needs "the same finger/face that enrolled", use `.biometryCurrentSet`, which invalidates the item when biometry enrollment changes.

## Common mistakes from real apps

1. **Tokens in UserDefaults.** Plaintext plist, readable from backups. The single most common finding.
2. **Hardcoded API secrets.** `strings` on the IPA reveals them. They cannot be rotated without an app update.
3. **Weak accessibility.** `AfterFirstUnlock` (or the deprecated `Always`) on tokens means a stolen locked phone gives them up.
4. **Boolean biometric gates.** A UserDefaults flag is not access control. Bind the secret to biometry in the Keychain.
5. **No cleanup on logout.** Tokens left in the Keychain after logout stay valid if the backend does not invalidate them. Delete on logout, and invalidate server-side too.
6. **Ignoring OSStatus.** Keychain calls fail for real reasons (duplicate items, locked device, no entitlement). Check the status; this wrapper throws instead of swallowing it.
