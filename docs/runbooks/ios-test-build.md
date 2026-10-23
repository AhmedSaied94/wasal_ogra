# iOS test build

Until there is a paid Apple Developer account, an iPhone runs the app the way Xcode's free
"Personal Team" does: an IPA signed with your Apple ID, which works for 7 days. There is no Mac, so
Codemagic builds the IPA unsigned, and [Impactor](https://github.com/claration/impactor) signs and
installs it from Linux over USB.

What it is: the **dev** flavor in release mode (`وصّل dev`, `com.wassalogra.app.dev`). It plays
offline from the bundled sample pack. It can't reach a local backend: there is no `adb reverse` on
iOS. Staging and prod wait for a pack in `apps/mobile/assets/content/release/`, as on Android.

## 1. Build the IPA

1. In Codemagic, open the app, choose **Start new build**, the branch, and the workflow
   **iOS dev (unsigned IPA)** (`codemagic.yaml`). It takes about 15–25 minutes on the free M2
   machine.
2. Download the artifact `wassal-dev-unsigned.ipa` from the build page.

## 2. One-time setup on the Linux machine

1. `sudo pacman -S usbmuxd` (it talks to the iPhone over USB).
2. Download `Impactor-linux-x86_64.appimage` from the
   [latest release](https://github.com/claration/impactor/releases/latest) and
   `chmod +x` it, or install it from Flathub (`dev.khcrysalis.PlumeImpactor`).

## 3. Install on the iPhone

1. Connect the iPhone by USB, unlock it, and accept **Trust This Computer**. If Impactor doesn't
   see the phone, unplug it, start Impactor, then plug it in again (usbmuxd stops when no device
   is connected).
2. In Impactor, sign in with your Apple ID (Apple sends a two-factor code), choose the IPA, and
   install.
3. On the iPhone:
   - iOS 16 or later: **Settings → Privacy & Security → Developer Mode**, turn it on, and restart.
     The switch only appears after the first install attempt.
   - **Settings → General → VPN & Device Management**, tap your Apple ID, and **Trust**.
4. Open `وصّل dev`.

## Limits of a free Apple ID

- The install expires after **7 days**: the app no longer opens. Install the same IPA again, or a
  newer one, with the phone connected. The app's data stays as long as the bundle ID doesn't change.
- At most 3 sideloaded apps on the phone at once, and 10 new app IDs a week.
- No push notifications, Sign in with Apple, or in-app purchases. None of them is built yet.

## Later: a paid account

With an Apple Developer Program membership, add an App Store Connect API key to Codemagic, and add
a signed workflow that uploads to TestFlight. Testers then install from TestFlight, for 90 days a
build, without a computer. That is phase 3's job (`docs/delivery-plan.md`), together with Apple's
purchases and Sign in with Apple.
