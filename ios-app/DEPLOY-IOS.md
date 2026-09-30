# Will It Fit — iPhone app, the no-Mac route (GitHub Actions → TestFlight)

The iOS project in this folder is **complete and Mac-free**: the WFShare share
extension is pre-built into the Xcode project file (no Xcode GUI step left), a
shared build scheme is committed, and `.github/workflows/ios.yml` in the repo
builds, signs and uploads the app to TestFlight on GitHub's free macOS runners.
Signing is fully automatic via an App Store Connect API key.

## One-time setup (owner, ~30 min of clicking + Apple's enrollment wait)

1. **Join the Apple Developer Program** (£79/yr) — developer.apple.com/programs/enroll
   (works from the iPhone; easiest via the "Apple Developer" app). Approval
   usually lands within a day or two.
2. **Note your Team ID** — developer.apple.com → Account → Membership details
   → Team ID (looks like `ABCDE12345`).
3. **Create an App Store Connect API key** — appstoreconnect.apple.com →
   Users and Access → Integrations → App Store Connect API → Team Keys →
   Generate. Role: **Admin** (needed so the build can create certificates
   itself). Download the `AuthKey_XXXX.p8` file — Apple only offers it once —
   and note the **Key ID** and the **Issuer ID** shown above the key list.
4. **Add four secrets to the GitHub repo** — github.com/CookeJ123/will-it-fit
   → Settings → Secrets and variables → Actions → New repository secret:
   - `ASC_KEY_ID` — the Key ID
   - `ASC_ISSUER_ID` — the Issuer ID
   - `ASC_KEY_P8` — open the .p8 file in a text editor, paste its whole contents
   - `APPLE_TEAM_ID` — the Team ID
5. **Re-paste `worker.js`** in the Cloudflare dashboard if not done since
   22 Aug (adds the app's `capacitor://localhost` origin — without it the app
   gets 403 from the proxy and community cache).

## First build

Repo → **Actions** → **iOS TestFlight** → **Run workflow**. (Pushes touching
`ios-app/` also trigger it; while the secrets are missing it skips itself
with a notice instead of failing.)

The first run auto-registers the two bundle ids
(`com.johncooke.willitfit` + `.WFShare`), certificates and profiles. Two
things can need a one-time nudge:

- **"No suitable application records were found"** on the upload step →
  create the app record once: App Store Connect → My Apps → **+** → New App →
  iOS, name **Will It Fit**, primary language English (UK), bundle ID
  `com.johncooke.willitfit`, SKU `willitfit` → re-run the workflow.
- **App Group error** (rare — automatic signing usually registers it) →
  developer.apple.com → Certificates, Identifiers & Profiles → Identifiers →
  App Groups → **+** → `group.com.johncooke.willitfit` → re-run.

## Install it on the iPhone

App Store Connect → Will It Fit → **TestFlight** tab → wait for the build to
finish processing (~5–15 min) → add yourself to an internal testing group →
install the **TestFlight** app on the iPhone → the build appears there.
Add your partner as another internal tester (instant, no review, up to 100).

Then test the share flow: Safari → any product page → Share → **Add to Will
It Fit** (first time: scroll the share sheet → More → enable it) → the
"Added ✓" card → the app opens with the product waiting.

## Shipping updates

1. After web changes: run `ios-app\wf_ios_sync.ps1` (rebuilds the product,
   refreshes `www/` and `ios/App/App/public/`).
2. Commit + push `ios-app/` to the repo → the workflow builds and uploads the
   next TestFlight build automatically (build number = the run number).

## App Store proper (when ready)

Everything TestFlight needs is automated. For the public App Store listing,
App Store Connect additionally wants: screenshots (6.7" iPhone at minimum),
a description, and the privacy policy URL —
**https://cookej123.github.io/will-it-fit/privacy.html** (already live).
Privacy questionnaire answers: no data collected linked to identity; the
community size cache stores product data only. Then "Submit for review".

## Appendix — building on a real Mac instead

Still fully supported: `cd ios-app && npm install && npx cap sync ios &&
npx cap open ios`. The WFShare target, scheme, entitlements and icons are
already in the project — just pick your team under Signing & Capabilities
for both targets and press Run. Capacitor 8 uses Swift Package Manager, so
there is no CocoaPods step.

## Handoff internals (for future sessions)

- Share payload: `{u,t,x,s?,i?}` JSON → UTF-8 → base64 → percent-encode →
  App Group `group.com.johncooke.willitfit`, key `wf.pending.shopadd` →
  WFHandoff injects `#shopadd=` and reloads. The probe is `window.willitfit`
  (the app's only global — everything else is inside an IIFE).
  `test\e2e_wfshare.js` + `test\e2e_appframe.js` lock the whole chain.
- `ShareViewController.tryOpenApp` uses the responder-chain `openURL:`
  workaround to hop straight into the app; set it to `false` if App Review
  ever objects (the payload still arrives on next app open).
- The pbxproj's `FADE…` object ids are the hand-added WFShare/WFHandoff
  wiring — keep them if regenerating anything with `cap add ios`.
