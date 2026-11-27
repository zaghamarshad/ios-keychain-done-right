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
7. **Large blobs in the Keychain.** The Keychain is built for small secrets such as tokens, passwords, and keys, not for files, photos, or large JSON payloads. Storing large data there is slow and hard to manage. Keep the encryption key in the Keychain instead, and store the encrypted data in the app's file storage.
8. **Turning on iCloud Keychain sync for device-only tokens.** If an item is marked synchronizable, it can move to other devices signed into the same Apple account. That is the wrong default for a token tied to this device. Keep synchronizable off unless the user is meant to carry the secret across devices.
9. **Printing secrets to the console.** Logging a token or key while debugging leaves it in device logs and crash reports, where other apps and tools may be able to read it. Log that an item was saved or read, and its key name, never the secret value itself, and remove debug logging before release.
10. **Sharing a Keychain access group too widely.** An item placed in a shared access group can be read by every app or extension in that group. Keep items in the app's own group by default, and move an item into a shared group only when another app or extension genuinely needs that one secret.
11. **Assuming the Keychain is cleared when the app is deleted.** On iOS, Keychain items can survive an app uninstall, so a fresh install can read a token left behind by the old install. On first launch, check for a first run marker stored in the app sandbox; if it is missing, delete any old Keychain items for the service before saving new ones.
12. **Reusing one item key for different secrets.** Giving an access token and a refresh token the same account key means one save overwrites the other, and a delete meant for one removes both. Give each secret its own key name, and name keys for what they hold, not for the screen that saved them.
13. **Saving over an existing item without updating it.** Adding an item that already exists fails with a duplicate item status and saves nothing, so a refreshed token can look saved while the old value stays in place. Update the existing item, or delete it first and then add the new value, and check the status either way.
14. **Testing Keychain code only in the simulator.** The simulator handles access groups, biometry, and item persistence differently from a real device, so code that passes there can still fail or behave differently on hardware. Test save, read, update, and delete on a physical device before release, including one run with the device locked.
15. **Treating every read error as a missing item.** A locked device, a changed biometric set, and a missing entitlement can all make a read fail while the item is still there. Check the status code and handle each case, instead of saving a fresh token over an item the app simply could not open at that moment.
16. **Triggering a biometric prompt just to check if an item exists.** Reading a biometry protected item to see whether it is there can prompt the user for Face ID or Touch ID at a moment they did not expect. Check for the item without asking for its data, and only read the secret when the user is ready to use it.
17. **Leaving items behind when the account changes.** Signing out is not the only moment to clear the Keychain. If a different account signs in on the same device and the old items are still there, the app can read the previous account's token by mistake. Delete the items for the old account as part of the account switch, and save the new account's items only after that delete has succeeded.
18. **Saving a secret before its use is clear.** Storing a token or key at sign up, before the feature that needs it is used, leaves a secret on the device for longer than needed and widens what a backup or device check can find. Save each secret at the point the feature first needs it, and delete it when that feature is turned off.
19. **Mixing staging and production items under one service name.** If a test build and the release build share a service name and key names, a staging token saved during testing can be read later by the release build, or the other way round. Give each environment its own service name, so test items and real items never meet.
20. **Using the Keychain for data that is not secret.** Ordinary settings, cached profile text, and feature flags do not need Keychain protection, and putting them there makes reads slower and can trigger access prompts the user did not expect. Keep the Keychain for secrets only, and store non secret data in the app storage that fits it.
21. **Deleting only some items on logout.** Clearing the access token but leaving a refresh token or recovery key behind means the session is not really ended on the device. Delete every item for that account on logout, and check that a read after logout returns item not found for each key.
22. **Assuming a delete succeeded without checking its status.** A delete call can fail, for example when the item is protected and the device is locked, and the secret then stays on the device after the app reports the user as signed out. Check the status returned by each delete, and confirm with a read that returns item not found before treating the secret as removed.
23. **Renaming a key without migrating the old item.** Changing the key name for a secret in a new release leaves the old item sitting in the Keychain under its old name, and a read for the new name returns item not found even though the secret is still on the device. Keep the old key name, or migrate on first launch after the change: read the old item, save it under the new key, and delete the old one, so a rename does not look like a lost secret.
24. **Falling back to UserDefaults when a Keychain save fails.** If a save fails, for example when the device is locked or an entitlement is missing, writing the secret to UserDefaults so the feature keeps working puts a plaintext copy where the Keychain was meant to keep it out. Treat a failed save as a failed save: surface the error, retry when the device is unlocked, and never store the secret anywhere less protected as a workaround.
