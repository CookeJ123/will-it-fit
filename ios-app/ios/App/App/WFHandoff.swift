import UIKit
import WebKit
import Capacitor

/// Share-sheet → app handoff. The WFShare extension stashes a base64 payload
/// (same {u,t,x,s?,i?} JSON the web bookmarklet builds) in the shared App Group;
/// we drain it whenever the app becomes active and hand it to the web app as
/// the #shopadd= hash it already knows how to receive.
enum WFHandoff {
    static let groupId = "group.com.johncooke.willitfit"
    static let pendingKey = "wf.pending.shopadd"

    /// Store a payload (base64 of UTF-8 JSON) for the next drain.
    static func stash(b64: String) {
        UserDefaults(suiteName: groupId)?.set(b64, forKey: pendingKey)
    }

    /// willitfit://shopadd?d=<b64> — the ?d= is optional; the extension already
    /// stashed the payload, the URL is mostly just a wake-up call.
    static func handle(url: URL) {
        guard url.scheme?.lowercased() == "willitfit" else { return }
        if let d = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "d" })?.value, !d.isEmpty {
            stash(b64: d)
        }
    }

    /// If a payload is waiting, inject it into the web app. The page may still
    /// be booting when the scene activates, so probe for window.willitfit (the
    /// app's one deliberate global — everything else lives in an IIFE) and
    /// retry briefly instead of firing into a half-loaded page.
    static func drainAndInject(window: UIWindow?, attempt: Int = 0) {
        let defaults = UserDefaults(suiteName: groupId)
        guard let b64 = defaults?.string(forKey: pendingKey), !b64.isEmpty else { return }
        guard let webView = (window?.rootViewController as? CAPBridgeViewController)?.webView else { return }

        // percent-encode like JS encodeURIComponent (the receiver decodeURIComponents it)
        guard let enc = b64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            defaults?.removeObject(forKey: pendingKey); return
        }
        let js = "(function(){if(!window.willitfit)return 'wait';"
               + "window.wfTrace&&window.wfTrace('handoff inject');"
               + "location.hash='shopadd=\(enc)';location.reload();return 'ok';})()"
        webView.evaluateJavaScript(js) { result, _ in
            if (result as? String) == "ok" {
                defaults?.removeObject(forKey: pendingKey)
            } else if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    drainAndInject(window: window, attempt: attempt + 1)
                }
            }
        }
    }
}
