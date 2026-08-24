import UIKit
import WebKit
import Capacitor

/// Reads a portal listing INSIDE the app when the remote fetch chain cannot.
/// Zoopla's bot wall blocks every server on the internet — but a real WebKit
/// view on the user's own phone is indistinguishable from a human visitor.
/// The web layer asks for a read via the `wfListingRead` script message; we
/// load the page in a hidden WKWebView, run the same harvest JS the share
/// extension uses, and hand the result to the existing WFHandoff pipeline
/// (which reloads the app page with #shopadd= and traces the plan).
/// If Cloudflare insists on an interactive check, the page is presented for
/// one tap and then finishes automatically.
final class WFListingReader: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIAdaptivePresentationControllerDelegate {
    static let shared = WFListingReader()

    private weak var window: UIWindow?
    private var webView: WKWebView?
    private var host: UIViewController?
    private var timer: Timer?
    private var deadline = Date.distantPast
    private var challengeSince: Date?
    private var reading = false
    private var presented = false

    private static var safeAreaInstalled = false

    /// Idempotent; call on every scene activation.
    func attach(to window: UIWindow?) {
        self.window = window
        guard let bridgeVC = window?.rootViewController as? CAPBridgeViewController,
              let ucc = bridgeVC.webView?.configuration.userContentController else { return }
        ucc.removeScriptMessageHandler(forName: "wfListingRead")
        ucc.add(self, name: "wfListingRead")
        // env(safe-area-inset-*) proved unreliable in the Capacitor webview on a real
        // phone (returned 0 -> top bar under the clock), so expose the authoritative
        // UIKit insets as --wf-sat/--wf-sab: a user script covers every future page
        // load (handoff reloads included), the immediate eval covers the current one.
        if let w = window {
            let t = Int(w.safeAreaInsets.top.rounded()), b = Int(w.safeAreaInsets.bottom.rounded())
            let src = "document.documentElement.style.setProperty('--wf-sat','\(t)px');"
                    + "document.documentElement.style.setProperty('--wf-sab','\(b)px')"
            if !Self.safeAreaInstalled {
                ucc.addUserScript(WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: true))
                Self.safeAreaInstalled = true
            }
            bridgeVC.webView?.evaluateJavaScript(src, completionHandler: nil)
        }
    }

    // web -> native: window.webkit.messageHandlers.wfListingRead.postMessage(url)
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let url = message.body as? String else { return }
        read(urlString: url)
    }

    func read(urlString: String) {
        guard !reading, let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else { return }
        DispatchQueue.main.async { self.start(url) }
    }

    /// Drop a breadcrumb into the web app's wf:apptrace log (fixed strings only).
    private func note(_ m: String, then: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            guard let mainWV = (self.window?.rootViewController as? CAPBridgeViewController)?.webView else { then?(); return }
            mainWV.evaluateJavaScript("window.wfTrace&&window.wfTrace('native: \(m)')") { _, _ in then?() }
        }
    }

    private func start(_ url: URL) {
        reading = true
        challengeSince = nil
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 760), configuration: cfg)
        // The default WKWebView UA carries no Safari token, which Cloudflare flags as a bot
        // on its own — identify as real mobile Safari so the wall treats us like a visitor.
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        wv.navigationDelegate = self
        wv.isHidden = true
        window?.addSubview(wv)
        webView = wv
        deadline = Date().addingTimeInterval(45)
        note("reader start")
        wv.load(URLRequest(url: url))
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        guard let wv = webView else { return finish(nil) }
        if Date() > deadline { return finish(nil) }
        wv.evaluateJavaScript(Self.harvestJS) { [weak self] result, _ in
            guard let self else { return }
            guard let s = result as? String else { return }
            if s == "challenge" { self.challengeShowing(); return }
            if s == "wait" { return }
            self.finish(s) // base64 {k:'l',...} payload
        }
    }

    /// CF managed checks usually auto-resolve in real WebKit within seconds;
    /// only present the page if one lingers and needs a human tap.
    private func challengeShowing() {
        if challengeSince == nil { challengeSince = Date(); note("challenge detected") }
        guard !presented, let since = challengeSince, Date().timeIntervalSince(since) > 6,
              let wv = webView, let root = window?.rootViewController else { return }
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        wv.isHidden = false
        wv.frame = vc.view.bounds
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        vc.view.addSubview(wv)
        vc.presentationController?.delegate = self
        root.present(vc, animated: true)
        host = vc
        presented = true
        note("challenge presented for a tap")
        deadline = Date().addingTimeInterval(90) // give the human time
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        presented = false
        host = nil
        finish(nil)
    }

    private func finish(_ b64: String?) {
        timer?.invalidate(); timer = nil
        if presented { host?.dismiss(animated: true); presented = false }
        host = nil
        webView?.removeFromSuperview(); webView = nil
        reading = false
        if let b64, !b64.isEmpty {
            // note() then hand over inside its completion — the handoff reloads the
            // page, so the breadcrumb must land in localStorage first
            note("harvest ok, handing over") {
                WFHandoff.stash(b64: b64)
                WFHandoff.drainAndInject(window: self.window)
            }
        } else {
            note("reader gave up (deadline or dismissed)")
        }
    }

    /// The same harvest as WFShare.js's listing mode — keep them in lockstep.
    /// Returns 'challenge' | 'wait' | base64(UTF-8 JSON {k:'l',u,t,fp,ph,a?,pr?}).
    private static let harvestJS = #"""
(function(){
 try{
  if(/just a moment|attention required/i.test(document.title||''))return 'challenge';
  if(document.querySelector('script[src*="challenge-platform"]'))return 'challenge';
  var H=document.documentElement.innerHTML,fp=[],ph=[],S={};
  var A=function(u){u=String(u).split('\\/').join('/');if(u.indexOf('http')===0&&!S[u]&&fp.length<6){S[u]=1;fp.push(u.slice(0,400));}};
  var re=/https?:\\?\/\\?\/[^"'\s>\\]*(?:floor[-_]?plan|_FLP_)[^"'\s>\\]*\.(?:jpe?g|png|gif|webp)/gi,m;
  while(m=re.exec(H))A(m[0]);
  var ix=H.indexOf('floorPlan');
  while(ix>=0&&fp.length<6){var w=H.slice(ix,ix+4000),r2=/\\?"filename\\?":\\?"([0-9a-f]{16,}\.(?:jpe?g|png|gif))/gi,m2;while(m2=r2.exec(w))A('https://lc.zoocdn.com/'+m2[1]);ix=H.indexOf('floorPlan',ix+9);}
  if(!fp.length)return 'wait';
  var im=document.images,i;
  for(i=0;i<im.length&&ph.length<10;i++){var s=im[i].currentSrc||im[i].src||'';if(/^https?:/.test(s)&&im[i].naturalWidth>350&&!S[s]){S[s]=1;ph.push(s.slice(0,400));}}
  var t2=document.body?document.body.innerText:'';
  var am=/([\d,]+(?:\.\d+)?)\s*(?:sq\.?\s?m\b|sqm\b|m²|square met|sq\.?\s?ft|sqft|ft²|square f)/i.exec(t2);
  var pr=/([£€][\d,]{4,}(?:\s?pcm)?)/.exec(t2);
  var og=document.querySelector('meta[property="og:title"]');
  var p={k:'l',u:location.href.slice(0,500),t:((og&&og.content)||document.title||'').slice(0,140),fp:fp,ph:ph};
  if(am)p.a=am[0].slice(0,40);
  if(pr)p.pr=pr[1].slice(0,30);
  return btoa(unescape(encodeURIComponent(JSON.stringify(p))));
 }catch(e){return 'wait';}
})();
"""#
}
