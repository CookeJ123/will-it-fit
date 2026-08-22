import UIKit
import Social

/// "Add to Will It Fit" — the share-sheet extension.
///
/// From Safari the WFShare.js preprocessing file has already run inside the
/// page itself (immune to shop bot-walls, exactly like the web bookmarklet)
/// and hands us {u,t,x,s?,i?}. From other apps we fall back to the shared URL
/// or plain text. Either way the payload is stashed in the App Group and the
/// main app injects it as #shopadd= next time it comes to the front.
class ShareViewController: UIViewController {

    static let groupId = "group.com.johncooke.willitfit"
    static let pendingKey = "wf.pending.shopadd"
    /// Jump straight into the app after stashing. Uses the well-known
    /// responder-chain openURL workaround; if App Review ever objects,
    /// set this to false — the payload still arrives on next app open.
    static let tryOpenApp = true

    private var payload: [String: Any] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        collectPayload()
    }

    // MARK: payload

    private func collectPayload() {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        // Safari web page (preprocessing JS results) beats a bare URL beats text
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier("com.apple.property-list") }) {
            p.loadItem(forTypeIdentifier: "com.apple.property-list", options: nil) { [weak self] item, _ in
                let dict = item as? NSDictionary
                // JS results normally sit under NSExtensionJavaScriptPreprocessingResultsKey;
                // fall back to the dict itself if the payload shape is ever flat
                let results = (dict?[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary)
                    ?? (dict?["u"] != nil ? dict : nil)
                var out: [String: Any] = [:]
                if let r = results {
                    for (k, v) in r { if let key = k as? String { out[key] = v } }
                }
                DispatchQueue.main.async { self?.finish(with: out) }
            }
            return
        }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.url") }) {
            p.loadItem(forTypeIdentifier: "public.url", options: nil) { [weak self] item, _ in
                let url = (item as? URL)?.absoluteString ?? (item as? String) ?? ""
                DispatchQueue.main.async { self?.finish(with: ["u": String(url.prefix(500)), "t": "", "x": ""]) }
            }
            return
        }
        if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.plain-text") }) {
            p.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { [weak self] item, _ in
                let text = (item as? String) ?? ""
                DispatchQueue.main.async { self?.finish(with: ["u": "", "t": "", "x": String(text.prefix(6000))]) }
            }
            return
        }
        finish(with: nil)
    }

    private func finish(with payload: [String: Any]?) {
        var ok = false
        if let p = payload, !((p["u"] as? String ?? "").isEmpty && (p["x"] as? String ?? "").isEmpty),
           let data = try? JSONSerialization.data(withJSONObject: p),
           let defaults = UserDefaults(suiteName: Self.groupId) {
            defaults.set(data.base64EncodedString(), forKey: Self.pendingKey)
            ok = true
        }
        showCard(ok: ok)
        if ok && Self.tryOpenApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { self.openContainerApp() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (ok ? 1.15 : 1.8)) {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    // MARK: open the app (responder-chain workaround)

    private func openContainerApp() {
        guard let url = URL(string: "willitfit://shopadd") else { return }
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let r = responder {
            if r.responds(to: selector), !(r is UIViewController) {
                _ = r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }

    // MARK: tiny brand card

    private func showCard(ok: Bool) {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(red: 0.047, green: 0.208, blue: 0.196, alpha: 1) // Deep Pine
        card.layer.cornerRadius = 18

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = ok ? "Added to Will It Fit" : "Nothing to add from here"
        title.textColor = UIColor(red: 0.953, green: 0.957, blue: 0.945, alpha: 1)   // Paper
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textAlignment = .center

        let sub = UILabel()
        sub.translatesAutoresizingMaskIntoConstraints = false
        sub.text = ok ? "It will be waiting in the Library." : "Try sharing a product page or its size text."
        sub.textColor = UIColor(red: 0.561, green: 0.851, blue: 0.788, alpha: 1)     // Seafoam
        sub.font = .systemFont(ofSize: 13)
        sub.textAlignment = .center
        sub.numberOfLines = 2

        let mark = UILabel()
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.text = ok ? "✓" : "…"
        mark.textColor = UIColor(red: 0.804, green: 0.937, blue: 0.898, alpha: 1)    // Mist
        mark.font = .systemFont(ofSize: 30, weight: .bold)
        mark.textAlignment = .center

        card.addSubview(mark); card.addSubview(title); card.addSubview(sub)
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 280),
            mark.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            mark.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            title.topAnchor.constraint(equalTo: mark.bottomAnchor, constant: 6),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            sub.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            sub.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            sub.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
        ])

        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.22) {
            card.alpha = 1
            card.transform = .identity
        }
    }
}
