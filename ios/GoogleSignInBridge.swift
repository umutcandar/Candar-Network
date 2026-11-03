import Foundation
import UIKit
import GoogleSignIn

@objcMembers
final class GoogleSignInBridge: NSObject {

    static let shared = GoogleSignInBridge()

    func configure(clientID: String) {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    private func topViewController() -> UIViewController? {
        // Aktif sahneyi ve buna bağlı key window'u bul
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        
        let window = scenes
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        // RootViewController üzerinden en üstteki presented controller'ı bul
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    func signIn() {
        DispatchQueue.main.async {
            guard let vc = self.topViewController() else {
                self.writeResult(ok: false, idToken: "", accessToken: "", email: "", name: "", error: "no_view_controller")
                return
            }

            guard GIDSignIn.sharedInstance.configuration != nil else {
                self.writeResult(ok: false, idToken: "", accessToken: "", email: "", name: "", error: "not_configured")
                return
                print("DEBUG: Top VC is \(String(describing: vc))")
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
              let txt = String(data: data, encoding: .utf8) else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("google_callback.json")
        try? txt.write(to: url, atomically: true, encoding: .utf8)
    }
}
