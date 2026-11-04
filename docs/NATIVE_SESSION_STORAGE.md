# Candar Network — native Firebase session storage

## Contract

- Android: `CandarSecureStore` singleton is registered from `GodotApp.getHostPlugins`.
  `saveRefreshToken(token)`, `loadRefreshToken()`, `clearRefreshToken()`
  persist AES-256-GCM ciphertext only; the non-exportable AES key lives in
  Android Keystore. Missing/invalid key or tampered payload means re-login.
- iOS: the **compiled, existing** `ios/s.swift` bridge (via
  `CandarNativeBridge.initAll()`) watches
  `user://secure_session_request.json`. It saves/loads/deletes the actual
  Firebase refresh token in Keychain with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. A
  `secure_session_response.json` mirrors the request id. GDScript deletes
  responses immediately.
- Both: `global.gd` uses in-memory cache while the process is alive.
  `user://refresh_token.txt` is **never written again**. On first launch
  the old unencrypted token is read once, migrated, and removed. If secure
  persistence is unavailable the user must sign in again after restart.
- Firebase refresh token != Google OAuth refresh token. Google OAuth's
  `refresh_token` must never populate the Firebase session store.
- Logout clears native credential before removing local UID; the cached
  Firebase ID token and FirebaseClient tokens are cleared.
- A UID mismatch on Secure Token response rejects the rotated session.

## Important iOS transport limitation

The existing Godot iOS app uses file IPC (also used by Google Sign-In).
The Keychain **persists** the credential, but until a native Godot singleton
plugin is compiled there is a **brief plaintext IPC window** between GDScript
and the Swift Keychain handler. GDScript removes responses immediately and
Swift removes requests before processing, and the Swift response uses
`completeFileProtection` and is excluded from backup. If the app terminates
between native response and GDScript receipt, the response could remain until
the next startup. For strict no-plaintext-at-any-time threat models, a
compiled Godot iOS plugin exposing Keychain calls directly is still required.

## Real-device release checklist

1. Build Android **with the checked-in Gradle custom export template**, and
   verify `Engine.has_singleton("CandarSecureStore")` on the packaged build.
   Confirm automatic sign-in after relaunch and sign-out after full process
   termination. Verify no `refresh_token.txt` is created.
2. Build the **`ios/candarnetwork.xcodeproj`** target that compiles `s.swift`
   and invokes `CandarBootstrap.m`. A different Xcode target or regenerated
   Godot export may not contain this Swift bridge.
3. iOS: verify token save/load after cold restart, sign-out removal, device
   lock behavior, and migration from an existing test account. Inspect the
   container for leftover `secure_session_{request,response}.json` after
   normal requests.
4. Test failure of Android Keystore after OS backup restore, and Keychain
   locked/unavailable. Expected: user can log in manually; no unencrypted
   fallback is written.
5. Verify iOS native `SecItem` operations and Android Java compile on
   actual release build. Current GitHub CI tests the **GDScript protocol**,
   not an iOS signed IPA or Android AAB.
6. Remove the remaining iOS file-IPC credential exposure by compiling a
   dedicated Keychain Godot plugin before claiming zero-plaintext transport.
