# Use TV Guardian without owning a Mac

You can keep using Windows and your iPhone. Xcode still runs on a Mac, but that
Mac can be a GitHub-hosted cloud runner. The resulting device build is then
signed and installed using your Windows PC and your own Apple account.

**The first cloud build passed on 2026-11-18:** all 26 XCTest cases and the device
archive succeeded using Xcode 26.6. The compiled unsigned IPA is saved locally at
`dist/TVGuardian-unsigned.ipa`, with a ZIP at `dist/TVGuardian-Windows-install.zip`.
You can go directly to step 3 below. The package needs Apple signing through the
Windows installer before it can run on your phone.

[Successful run and downloadable artifacts](https://github.com/zadwen/TVGuardian/actions/runs/44339943672).
GitHub artifacts from this run expire on 2026-11-21; the local downloaded files
remain available. SHA-256 of the compiled IPA:

`38cd4f6525fd430e284f68ab06731d70014c0f27b078ffa6ef89b0f577510913`

## 1. Choose a GitHub repository

The project is uploaded to [zadwen/TVGuardian](https://github.com/zadwen/TVGuardian).
Use that repository for future builds, or choose another repository you control.
No Apple password, signing certificate or provisioning profile is needed for
this build workflow. Do not upload the ZIP as a single repository file: the
actual extracted files, including `.github/workflows`, must be at the root.

If moving/uploading the project yourself on Windows, use Git/GitHub Desktop to publish these source
paths: `ios`, `bridge`, `companion`, `docs`, `tools`, `.github`, `.gitattributes`,
`.gitignore`, `README.md` and `LICENSE`. Keep `.build`, `.research`, `dist`, local
configuration, certificate/private-key files and generated secret files out.

The existing verification workflow runs Node checks on a push. Apple simulator
jobs run manually. The new IPA build runs manually or on the dedicated
`build/iphone` branch, which the agent can use to start a run through the connected
GitHub integration. The build times out after 30 minutes
and retains artifacts for three days. Private-repository compute/storage use
depends on your GitHub plan; check its Actions budget before dispatching a job.
No paid runner or plan is purchased automatically.

Source: [GitHub-hosted runners](https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/use-github-hosted-runners),
[GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

## 2. Build on the cloud Mac

In the repository on GitHub:

1. Open **Actions**.
2. Select **Build iPhone app for Windows installation**.
3. Select **Run workflow**, keep the branch and bundle identifier consistent,
   and start the run.
4. The job runs contract tests, compiles/runs the supplied XCTest suite in an
   iPhone simulator, then archives an iPhoneOS device app without signing.
5. If compilation/testing fails, inspect **TVGuardian-build-diagnostics**.
   Share the run link with the agent to fix actual compiler/test failures.
   No success artifact is published when those steps fail.
6. After a successful run, download **TVGuardian-for-Windows-signing** from its
   Artifacts section. Extract the artifact ZIP on Windows. It contains
   `TVGuardian-unsigned.ipa`, a checksum and the next installation steps.

The `.ipa` is an actual compiled device app only after a successful run; the
source ZIP supplied earlier is different. No TV compatibility is established
by a simulator pass. The job requests no Apple credentials and performs no
TestFlight upload or account enrollment.

## 3. Sign and install from Windows

Follow the current [official AltStore Classic Windows guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows).
Download AltServer only through the official AltStore site/guide. That guide
covers the required Apple desktop components, device trust, signing in,
Wi-Fi synchronization and iPhone Developer Mode.

1. Install AltServer on Windows and AltStore Classic on the iPhone using that
   guide. Connect/trust the iPhone as directed.
2. Keep AltServer running and reachable from the phone. Transfer the compiled
   `TVGuardian-unsigned.ipa` to the iPhone's Files app using your chosen file
   transfer method.
3. In AltStore Classic, open **My Apps**, use its add/import action and select
   the IPA. AltStore/AltServer handles signing/provisioning with your account.
4. Enter Apple credentials only in the legitimate installer's sign-in flow.
   No Apple password belongs in this chat, repository or cloud build secrets.
5. Enable Developer Mode/trust the development app if required by iOS, then open
   TV Guardian, create the parent PIN and follow [the pairing guide](INSTALL.md#pair-locally).
6. Keep the same bundle identifier and signing account for updates. With a free
   account, sideloaded apps need renewal after seven days and are subject to app
   and App ID limits. AltServer must be reachable for refresh. Review the
   installer's current diagnostics if Apple authorization fails.

Source: [AltStore getting started and refresh limits](https://faq.altstore.io/altstore-classic/your-altstore).

This is developer sideloading with Apple signing, not a signing bypass. Windows
cannot compile the SwiftUI/Xcode project locally using these tools. The cloud
runner supplies that missing compilation step.

## TestFlight alternative

If you already have a suitable Apple Developer Program membership and want a
managed beta install, a separately configured signed cloud build can upload to
App Store Connect/TestFlight. That needs authorized signing/API setup and the
app record; external testing can require beta review. This unsigned workflow
does not perform that distribution or require you to buy membership.

Source: [Apple TestFlight](https://developer.apple.com/testflight/).
