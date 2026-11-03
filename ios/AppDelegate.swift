import UIKit
import GoogleMobileAds
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import StoreKit

@objcMembers
final class GodotLibraryBridge: NSObject, MessagingDelegate, UNUserNotificationCenterDelegate {
    static let shared = GodotLibraryBridge()

    private var signInTimer: Timer?
    private var pushTimer: Timer?
    private var reviewTimer: Timer?
    private var shareTimer: Timer?

    func initAll() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        GoogleSignInBridge.shared.configure(
            clientID: "170015852669-362693n16e88llrtodo6f0b9saem6fp4.apps.googleusercontent.com"
        )
        configurePushNotifications()
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        startSignInRequestWatcher()
        startPushTokenRefreshWatcher()
        startReviewRequestWatcher()
        startShareRequestWatcher()
        print("✅ GodotLibraryBridge initAll OK")
    }

    private func configurePushNotifications() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("⚠️ Push permission error: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                self.refreshFcmToken()
            }
        }
    }

    private func startPushTokenRefreshWatcher() {
        pushTimer?.invalidate()
        pushTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            self.refreshFcmToken()
        }
        RunLoop.main.add(pushTimer!, forMode: .common)
    }

    private func refreshFcmToken() {
        Messaging.messaging().token { token, error in
            if let error = error {
                print("⚠️ FCM token error: \(error.localizedDescription)")
                return
            }
            guard let token = token, !token.isEmpty else { return }
            self.writeFcmToken(token)
        }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else { return }
        writeFcmToken(token)
    }

    private func writeFcmToken(_ token: String) {
        let json: [String: Any] = [
            "token": token,
            "platform": "ios",
            "updated_at": Int(Date().timeIntervalSince1970)
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []),
              let txt = String(data: data, encoding: .utf8) else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("fcm_token.json")
        try? txt.write(to: url, atomically: true, encoding: .utf8)
    }

    private func startSignInRequestWatcher() {
        signInTimer?.invalidate()
        signInTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let requestFile = docs.appendingPathComponent("signin_request.tmp")
            if FileManager.default.fileExists(atPath: requestFile.path) {
                print("🚀 Godot'tan Giriş İsteği Geldi! Pop-up açılıyor...")
                try? FileManager.default.removeItem(at: requestFile)
                GoogleSignInBridge.shared.signIn()
            }
        }
        RunLoop.main.add(signInTimer!, forMode: .common)
    }

    private func startReviewRequestWatcher() {
        reviewTimer?.invalidate()
        reviewTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let candidates = self.reviewRequestCandidateURLs()
            guard let requestFile = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                return
            }
            try? FileManager.default.removeItem(at: requestFile)
            DispatchQueue.main.async {
                if let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }) {
                    SKStoreReviewController.requestReview(in: scene)
                    print("⭐️ Store review prompt requested.")
                } else if let url = URL(string: "https://apps.apple.com/app/id6756212781?action=write-review") {
                    UIApplication.shared.open(url)
                    print("⭐️ Store review fallback opened App Store listing.")
                }
            }
        }
        RunLoop.main.add(reviewTimer!, forMode: .common)
    }

    private func reviewRequestCandidateURLs() -> [URL] {
        var urls: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docs.appendingPathComponent("review_request.tmp"))
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(appSupport.appendingPathComponent("review_request.tmp"))
        }
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            urls.append(caches.appendingPathComponent("review_request.tmp"))
        }
        return urls
    }

    private func startShareRequestWatcher() {
        shareTimer?.invalidate()
        shareTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            let candidates = self.shareRequestCandidateURLs()
            guard let requestFile = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let data = try? Data(contentsOf: requestFile),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            try? FileManager.default.removeItem(at: requestFile)
            let text = String(describing: payload["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let urlText = String(describing: payload["url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty || !urlText.isEmpty else { return }
            DispatchQueue.main.async {
                self.presentShareSheet(text: text, urlText: urlText)
            }
        }
        RunLoop.main.add(shareTimer!, forMode: .common)
    }

    private func shareRequestCandidateURLs() -> [URL] {
        var urls: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docs.appendingPathComponent("share_request.json"))
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(appSupport.appendingPathComponent("share_request.json"))
        }
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            urls.append(caches.appendingPathComponent("share_request.json"))
        }
        return urls
    }

    private func presentShareSheet(text: String, urlText: String) {
        var activityItems: [Any] = []
        if !text.isEmpty {
            activityItems.append(text)
        }
        if let url = URL(string: urlText), !urlText.isEmpty {
            activityItems.append(url)
        }
        guard !activityItems.isEmpty,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        let share = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        if let popover = share.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(share, animated: true)
    }
}
