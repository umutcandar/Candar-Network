import Foundation
import UIKit
import GoogleMobileAds
import GoogleSignIn
import FirebaseCore
import FirebaseMessaging
import ObjectiveC
import StoreKit
import UserNotifications
import Security

private let candarGoogleClientID = "170015852669-362693n16e88llrtodo6f0b9saem6fp4.apps.googleusercontent.com"

@objcMembers
final class CandarGoogleSignInBridge: NSObject {
    static let shared = CandarGoogleSignInBridge()

    func configure(clientID: String = candarGoogleClientID) {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    func handleOpenURL(_ url: URL) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        let sceneWindow = scenes
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? scenes.flatMap { $0.windows }.first

        let fallbackWindow = UIApplication.shared.windows.first { $0.isKeyWindow } ?? UIApplication.shared.windows.first

        guard var top = (sceneWindow ?? fallbackWindow)?.rootViewController else {
            return nil
        }

        while true {
            if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
                top = visible
                continue
            }
            if let tab = top as? UITabBarController, let selected = tab.selectedViewController {
                top = selected
                continue
            }
            if let presented = top.presentedViewController {
                top = presented
                continue
            }
            break
        }

        return top
    }

    func signIn() {
        DispatchQueue.main.async {
            self.configure()

            guard let vc = self.topViewController() else {
                self.writeResult(ok: false, idToken: "", accessToken: "", email: "", name: "", error: "no_view_controller")
                return
            }

            GIDSignIn.sharedInstance.signIn(withPresenting: vc) { result, error in
                if let error = error {
                    self.writeResult(ok: false, idToken: "", accessToken: "", email: "", name: "", error: error.localizedDescription)
                    return
                }

                guard let result = result else {
                    self.writeResult(ok: false, idToken: "", accessToken: "", email: "", name: "", error: "no_result")
                    return
                }

                let user = result.user
                let idToken = user.idToken?.tokenString ?? ""
                let accessToken = user.accessToken.tokenString
                let email = user.profile?.email ?? ""
                let name = user.profile?.name ?? ""

                if idToken.isEmpty {
                    self.writeResult(ok: false, idToken: "", accessToken: "", email: "", name: "", error: "empty_id_token")
                    return
                }

                self.writeResult(ok: true, idToken: idToken, accessToken: accessToken, email: email, name: name, error: "")
            }
        }
    }

    private func writeResult(ok: Bool, idToken: String, accessToken: String, email: String, name: String, error: String) {
        let json: [String: Any] = [
            "ok": ok,
            "id_token": idToken,
            "access_token": accessToken,
            "email": email,
            "name": name,
            "error": error
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        CandarNativeBridge.shared.writeTextToCandidateDirs(text, fileName: "google_callback.json")
    }
}

@objcMembers
final class CandarNativeBridge: NSObject {
    static let shared = CandarNativeBridge()

    private var signInTimer: Timer?
    private var receiptTimer: Timer?
    private var secureSessionTimer: Timer?
    private var shareTimer: Timer?
    private var receiptRefreshRequest: SKReceiptRefreshRequest?
    private var urlHandlerTimer: Timer?
    private var started = false
    private var urlHandlerAttempts = 0

    private static var appURLHandlerInstalled = false
    private static var sceneURLHandlerInstalled = false
    private static var originalAppOpenURLIMP: IMP?
    private static var originalSceneOpenURLIMP: IMP?
    private static var originalContinueUserActivityIMP: IMP?

    func initAll() {
        guard !started else { return }
        started = true

        configureFirebaseAndPushNotifications()
        CandarGoogleSignInBridge.shared.configure()
		MobileAds.shared.start()
        removeFileFromCandidateDirs("signin_request.tmp")
        removeFileFromCandidateDirs("receipt_request.tmp")
        removeFileFromCandidateDirs("app_store_receipt.txt")
        // An interrupted Keychain response must not retain a previous session token.
        removeFileFromCandidateDirs("secure_session_response.json")
		removeFileFromCandidateDirs("share_request.json")
        startSignInRequestWatcher()
        startReceiptRequestWatcher()
        startSecureSessionRequestWatcher()
		startShareRequestWatcher()
        startURLHandlerInstaller()

        print("[CandarNativeBridge] initAll OK")
    }

    private func configureFirebaseAndPushNotifications() {
        if FirebaseApp.app() == nil {
            guard let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                  let options = FirebaseOptions(contentsOfFile: plistPath) else {
                print("[CandarNativeBridge] GoogleService-Info.plist missing or invalid; push disabled")
                return
            }
            FirebaseApp.configure(options: options)
        }

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("[CandarNativeBridge] notification permission failed: \(error.localizedDescription)")
            }

            self.writeNotificationPermissionState(granted: granted, error: error)
            guard granted else {
                print("[CandarNativeBridge] notification permission denied")
                return
            }

            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func writeNotificationPermissionState(granted: Bool, error: Error?) {
        let payload: [String: Any] = [
            "granted": granted,
            "error": error?.localizedDescription ?? "",
            "updated_at": Int(Date().timeIntervalSince1970)
        ]
        writeJSON(payload, fileName: "notification_permission.json")
    }

    private func writePushToken(_ token: String) {
        guard !token.isEmpty else { return }
        let language = Locale.preferredLanguages.first?.split(separator: "-").first.map(String.init) ?? "en"
        writeJSON([
            "token": token,
            "platform": "ios",
            "language": language,
            "updated_at": Int(Date().timeIntervalSince1970)
        ], fileName: "fcm_token.json")
        print("[CandarNativeBridge] FCM token ready")
    }

    private func writePushPayload(_ userInfo: [AnyHashable: Any]) {
        var payload: [String: Any] = [:]
        for (key, value) in userInfo {
            payload[String(describing: key)] = value
        }
        payload["received_at"] = Int(Date().timeIntervalSince1970)
        writeJSON(payload, fileName: "push_notification.json")
    }

    private func writeJSON(_ object: [String: Any], fileName: String) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            print("[CandarNativeBridge] invalid JSON for \(fileName)")
            return
        }
        writeTextToCandidateDirs(text, fileName: fileName)
    }

    func writeTextToCandidateDirs(_ text: String, fileName: String) {
        let fm = FileManager.default
        for dir in candidateDirs() {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
                try text.write(to: dir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            } catch {
                print("[CandarNativeBridge] write failed \(dir.path)/\(fileName): \(error.localizedDescription)")
            }
        }
    }

    private func startSignInRequestWatcher() {
        signInTimer?.invalidate()
        signInTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard let requestFile = self.findExistingFile(named: "signin_request.tmp") else { return }

            print("[CandarNativeBridge] sign-in request found: \(requestFile.path)")
            self.removeFileFromCandidateDirs("signin_request.tmp")
            CandarGoogleSignInBridge.shared.signIn()
        }

        if let signInTimer {
            RunLoop.main.add(signInTimer, forMode: .common)
        }
    }

    // A transport for the existing Godot runtime, which cannot call Swift
    // Keychain APIs directly without a separately compiled iOS Godot plugin.
    // Only the Keychain persists the token. The short-lived request/response
    // files are removed immediately and excluded from backup.
    // A future compiled native Godot plugin should replace this file IPC.
    private func keychainQuery() -> [CFString: Any] {
        return [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.candarnetwork.app.firebase_refresh_v1",
            kSecAttrAccount: "firebase"
        ]
    }

    private func saveToKeychain(_ token: String) -> Bool {
        guard token.utf8.count >= 16 && token.utf8.count <= 8192 else { return false }
        let query = keychainQuery()
        let update: [CFString: Any] = [kSecValueData: Data(token.utf8)]
        let existing = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if existing == errSecSuccess { return true }
        if existing != errSecItemNotFound { return false }
        var creation = query
        creation[kSecValueData] = Data(token.utf8)
        creation[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(creation as CFDictionary, nil) == errSecSuccess
    }

    private func loadFromKeychain() -> String {
        var query = keychainQuery()
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return ""
        }
        return token
    }

    private func clearKeychainToken() -> Bool {
        let status = SecItemDelete(keychainQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func startSecureSessionRequestWatcher() {
        secureSessionTimer?.invalidate()
        secureSessionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.processSecureSessionRequest()
        }
        if let secureSessionTimer {
            RunLoop.main.add(secureSessionTimer, forMode: .common)
        }
    }

    private func processSecureSessionRequest() {
        guard let requestURL = findExistingFile(named: "secure_session_request.json"),
              let raw = try? Data(contentsOf: requestURL) else { return }

        // Remove any plaintext input before touching Keychain. Do not log it.
        try? FileManager.default.removeItem(at: requestURL)
        guard let request = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let requestId = request["request_id"] as? String,
              requestId.count >= 8 && requestId.count <= 128,
              let operation = request["operation"] as? String,
              let createdAt = request["created_at"] as? Int,
              abs(Int(Date().timeIntervalSince1970) - createdAt) <= 30 else { return }

        let response: [String: Any]
        switch operation {
        case "save":
            let token = request["token"] as? String ?? ""
            response = ["request_id": requestId, "ok": saveToKeychain(token)]
        case "load":
            let token = loadFromKeychain()
            response = ["request_id": requestId, "ok": !token.isEmpty, "token": token]
        case "clear":
            response = ["request_id": requestId, "ok": clearKeychainToken()]
        default:
            response = ["request_id": requestId, "ok": false]
        }

        guard let encoded = try? JSONSerialization.data(withJSONObject: response) else { return }
        let responseURL = requestURL.deletingLastPathComponent()
            .appendingPathComponent("secure_session_response.json")
        // File protection applies while locked; these brief IPC artifacts
        // never belong in the user's backup.
        do {
            try encoded.write(to: responseURL, options: [.atomic, .completeFileProtection])
            var url = responseURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            // Fail closed. The caller will require an interactive login.
        }
    }

    private func startReceiptRequestWatcher() {
        receiptTimer?.invalidate()
        receiptTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard self.findExistingFile(named: "receipt_request.tmp") != nil else { return }
            self.removeFileFromCandidateDirs("receipt_request.tmp")
            self.removeFileFromCandidateDirs("app_store_receipt.txt")
            self.refreshAppStoreReceipt()
        }

        if let receiptTimer {
            RunLoop.main.add(receiptTimer, forMode: .common)
        }
    }

    private func startShareRequestWatcher() {
        shareTimer?.invalidate()
        shareTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            guard let requestFile = self.findExistingFile(named: "share_request.json"),
                  let data = try? Data(contentsOf: requestFile),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            self.removeFileFromCandidateDirs("share_request.json")
            let text = (payload["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let urlText = (payload["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty || !urlText.isEmpty else { return }

            DispatchQueue.main.async {
                self.presentShareSheet(text: text, urlText: urlText)
            }
        }

        if let shareTimer {
            RunLoop.main.add(shareTimer, forMode: .common)
        }
    }

    private func presentShareSheet(text: String, urlText: String) {
        var items: [Any] = []
        if !text.isEmpty {
            items.append(text)
        }
        if !urlText.isEmpty, let url = URL(string: urlText) {
            items.append(url)
        }
        guard !items.isEmpty, let presenter = topViewController() else { return }

        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.maxY - 1,
                                        width: 1,
                                        height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(sheet, animated: true)
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
            ?? scenes.flatMap { $0.windows }.first
        guard var top = window?.rootViewController else { return nil }

        while true {
            if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
                top = visible
            } else if let tab = top as? UITabBarController, let selected = tab.selectedViewController {
                top = selected
            } else if let presented = top.presentedViewController {
                top = presented
            } else {
                break
            }
        }
        return top
    }

    @discardableResult
    private func writeCurrentAppStoreReceipt() -> Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receiptData = try? Data(contentsOf: receiptURL),
              !receiptData.isEmpty else {
            return false
        }

        writeTextToCandidateDirs(
            receiptData.base64EncodedString(),
            fileName: "app_store_receipt.txt"
        )
        print("[CandarNativeBridge] App Store receipt ready (\(receiptData.count) bytes)")
        return true
    }

    private func refreshAppStoreReceipt() {
        guard receiptRefreshRequest == nil else { return }
        print("[CandarNativeBridge] Requesting fresh App Store receipt")
        let request = SKReceiptRefreshRequest()
        receiptRefreshRequest = request
        request.delegate = self
        request.start()
    }

    private func startURLHandlerInstaller() {
        urlHandlerTimer?.invalidate()
        urlHandlerTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            self.urlHandlerAttempts += 1
            self.installURLHandlersIfPossible()

            if (Self.appURLHandlerInstalled && Self.sceneURLHandlerInstalled) || self.urlHandlerAttempts >= 20 {
                timer.invalidate()
            }
        }

        if let urlHandlerTimer {
            RunLoop.main.add(urlHandlerTimer, forMode: .common)
        }

        installURLHandlersIfPossible()
    }

    private func installURLHandlersIfPossible() {
        installAppDelegateOpenURLHandler()
        installSceneOpenURLHandler()
        installUniversalLinkHandler()
    }

    private func recordIncomingURL(_ url: URL) {
        writeTextToCandidateDirs(url.absoluteString, fileName: "launch_url.txt")
        print("[CandarNativeBridge] incoming URL recorded: \(url.absoluteString)")
    }

    private typealias AppOpenURLC = @convention(c) (AnyObject, Selector, UIApplication, URL, NSDictionary) -> Bool

    private func installAppDelegateOpenURLHandler() {
        guard !Self.appURLHandlerInstalled else { return }
        guard let delegate = UIApplication.shared.delegate else {
            print("[CandarNativeBridge] app delegate missing; Google URL handler skipped")
            return
        }
        guard let cls: AnyClass = object_getClass(delegate) else { return }

        let selector = #selector(UIApplicationDelegate.application(_:open:options:))
        let block: @convention(block) (AnyObject, UIApplication, URL, NSDictionary) -> Bool = { object, app, url, options in
            CandarNativeBridge.shared.recordIncomingURL(url)
            let handledByGoogle = CandarGoogleSignInBridge.shared.handleOpenURL(url)
            var handledByOriginal = false

            if let original = Self.originalAppOpenURLIMP {
                let fn = unsafeBitCast(original, to: AppOpenURLC.self)
                handledByOriginal = fn(object, selector, app, url, options)
            }

            return handledByGoogle || handledByOriginal
        }

        let newIMP = imp_implementationWithBlock(block as Any)
        if let method = class_getInstanceMethod(cls, selector) {
            Self.originalAppOpenURLIMP = method_getImplementation(method)
            method_setImplementation(method, newIMP)
        } else {
            class_addMethod(cls, selector, newIMP, "B@:@@@")
        }

        Self.appURLHandlerInstalled = true
        print("[CandarNativeBridge] app openURL handler installed")
    }

    private typealias SceneOpenURLC = @convention(c) (AnyObject, Selector, UIScene, NSSet) -> Void

    private func installSceneOpenURLHandler() {
        guard !Self.sceneURLHandlerInstalled else { return }
        guard let sceneDelegate = UIApplication.shared.connectedScenes.compactMap({ $0.delegate }).first else { return }
        guard let cls: AnyClass = object_getClass(sceneDelegate) else { return }

        let selector = #selector(UIWindowSceneDelegate.scene(_:openURLContexts:))
        let block: @convention(block) (AnyObject, UIScene, NSSet) -> Void = { object, scene, contexts in
            for item in contexts {
                if let ctx = item as? UIOpenURLContext {
                    CandarNativeBridge.shared.recordIncomingURL(ctx.url)
                    _ = CandarGoogleSignInBridge.shared.handleOpenURL(ctx.url)
                }
            }

            if let original = Self.originalSceneOpenURLIMP {
                let fn = unsafeBitCast(original, to: SceneOpenURLC.self)
                fn(object, selector, scene, contexts)
            }
        }

        let newIMP = imp_implementationWithBlock(block as Any)
        if let method = class_getInstanceMethod(cls, selector) {
            Self.originalSceneOpenURLIMP = method_getImplementation(method)
            method_setImplementation(method, newIMP)
        } else {
            class_addMethod(cls, selector, newIMP, "v@:@@")
        }

        Self.sceneURLHandlerInstalled = true
        print("[CandarNativeBridge] scene openURL handler installed")
    }

    private typealias ContinueUserActivityC = @convention(c) (AnyObject, Selector, UIApplication, NSUserActivity, AnyObject?) -> Bool

    private func installUniversalLinkHandler() {
        guard let delegate = UIApplication.shared.delegate,
              let cls: AnyClass = object_getClass(delegate) else { return }

        let selector = #selector(UIApplicationDelegate.application(_:continue:restorationHandler:))
        let block: @convention(block) (AnyObject, UIApplication, NSUserActivity, AnyObject?) -> Bool = { object, app, activity, restorationHandler in
            if let url = activity.webpageURL {
                CandarNativeBridge.shared.recordIncomingURL(url)
            }

            if let original = Self.originalContinueUserActivityIMP {
                let fn = unsafeBitCast(original, to: ContinueUserActivityC.self)
                return fn(object, selector, app, activity, restorationHandler)
            }
            return activity.webpageURL != nil
        }

        let newIMP = imp_implementationWithBlock(block as Any)
        if let method = class_getInstanceMethod(cls, selector) {
            Self.originalContinueUserActivityIMP = method_getImplementation(method)
            method_setImplementation(method, newIMP)
        } else {
            class_addMethod(cls, selector, newIMP, "B@:@@@?")
        }
        print("[CandarNativeBridge] universal link handler installed")
    }

    private func findExistingFile(named fileName: String) -> URL? {
        let fm = FileManager.default
        for dir in candidateDirs() {
            let file = dir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: file.path) {
                return file
            }
        }
        return nil
    }

    private func removeFileFromCandidateDirs(_ fileName: String) {
        let fm = FileManager.default
        for dir in candidateDirs() {
            let file = dir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: file.path) {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func candidateDirs() -> [URL] {
        let fm = FileManager.default
        var dirs: [URL] = []

        func add(_ url: URL?) {
            guard let url else { return }
            let normalized = url.standardizedFileURL
            if !dirs.contains(where: { $0.standardizedFileURL.path == normalized.path }) {
                dirs.append(normalized)
            }
        }

        add(fm.urls(for: .documentDirectory, in: .userDomainMask).first)

        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            add(support)
            add(support.appendingPathComponent("CandarNetwork"))
            add(support.appendingPathComponent("Candar Network"))
            add(support.appendingPathComponent("candarnetwork"))
            add(support.appendingPathComponent("app_userdata/CandarNetwork"))
            add(support.appendingPathComponent("app_userdata/Candar Network"))
            add(support.appendingPathComponent("app_userdata/candarnetwork"))
            add(support.appendingPathComponent("Godot/app_userdata/CandarNetwork"))
            add(support.appendingPathComponent("Godot/app_userdata/Candar Network"))
            add(support.appendingPathComponent("Godot/app_userdata/candarnetwork"))
        }

        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            add(caches)
            add(caches.appendingPathComponent("CandarNetwork"))
            add(caches.appendingPathComponent("Candar Network"))
            add(caches.appendingPathComponent("candarnetwork"))
        }

        return dirs
    }
}

extension CandarNativeBridge: SKRequestDelegate {
    func requestDidFinish(_ request: SKRequest) {
        guard request === receiptRefreshRequest else { return }
        receiptRefreshRequest = nil
        if !writeCurrentAppStoreReceipt() {
            print("[CandarNativeBridge] App Store receipt refresh completed without a receipt")
        }
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        guard request === receiptRefreshRequest else { return }
        receiptRefreshRequest = nil
        print("[CandarNativeBridge] App Store receipt refresh failed: \(error.localizedDescription)")
    }
}

extension CandarNativeBridge: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        writePushToken(fcmToken)
    }
}

extension CandarNativeBridge: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        writePushPayload(notification.request.content.userInfo)
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        writePushPayload(response.notification.request.content.userInfo)
        completionHandler()
    }
}
