# iOS install guide

The `pyrx_synapse` Flutter plugin auto-registers with the Flutter
iOS plugin chain, so the SDK boots without any code changes to your
`AppDelegate.swift`. The work you still have to do is the
Apple-Developer-account-side stuff that no SDK can automate for you.

This guide assumes you're starting from a Flutter app that's already
running on iOS — `flutter run -d ios` succeeds against the unmodified
template. If it doesn't, fix that first (`flutter doctor` is your
friend).

---

## 1. Add the dependency

```yaml
# pubspec.yaml
dependencies:
  pyrx_synapse: ^0.1.0
```

```bash
flutter pub get
```

This pulls in `pyrx_synapse_ios` transitively. The first
`flutter build ios` or `flutter run -d ios` after the resolve drives
`pod install` automatically; the `PYRXSynapse 0.1.2+` CocoaPod
downloads from Trunk and links into your app target.

If your `ios/Podfile` overrides the iOS deployment target, ensure it's
at least `13.0`:

```ruby
# ios/Podfile
platform :ios, '13.0'
```

`PYRXSynapse`'s Podspec pushes this to `14.0` at install time —
that's the SDK's hard floor.

---

## 2. Apple Developer Program — APNs auth

You need an **APNs auth key** (`.p8`) configured on the Synapse
dashboard so the backend can send pushes through Apple's servers.

1. **Create the key** in
   [Apple Developer → Certificates, Identifiers & Profiles → Keys](https://developer.apple.com/account/resources/authkeys/list)
   → "+" → name it (e.g., "PYRX Synapse"), check **Apple Push
   Notifications service (APNs)** → Continue → Register → Download
   the `.p8` file (you can only download once; store it safely).
2. Note the **Key ID** (shown on the key detail page) and your
   **Team ID** (top-right of any developer page).
3. In the
   [PYRX Synapse dashboard](https://synapse-app.pyrx.tech) under
   Settings → Push Providers → Apple → upload the `.p8` and enter the
   Key ID + Team ID + your app's Bundle ID.

The auth-key path supports both sandbox (development) and production
APNs from a single credential. No separate certs needed.

---

## 3. Bundle ID + entitlements

Your app's Bundle ID (set in Xcode under Runner target → General →
Identity) must be registered in Apple Developer Console with the
**Push Notifications** capability enabled.

In Xcode → Runner target → Signing & Capabilities → "+ Capability" →
**Push Notifications**. This writes the `aps-environment` entitlement
to `Runner/Runner.entitlements`:

```xml
<!-- ios/Runner/Runner.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>aps-environment</key>
    <string>development</string>
</dict>
</plist>
```

`development` is correct for Xcode dev builds + simulators.

Set `production` for App Store / TestFlight builds. The easiest way:
keep one `Runner.entitlements` file with `production`, and use Xcode
build configurations (Debug / Release) to swap a Debug-specific
`RunnerDebug.entitlements` with `development` if your team needs
both.

---

## 4. Background mode (optional but recommended)

Add **Background fetch** and **Remote notifications** background
modes so silent pushes (`content-available: 1`) wake your app:

In Xcode → Runner target → Signing & Capabilities → "+ Capability" →
**Background Modes** → check **Remote notifications**.

This adds to `Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

---

## 5. Verify the install

Run the sample app or your own app:

```bash
flutter run -d ios
```

In Dart:

```dart
await Synapse.initialize(const PyrxConfig(
  workspaceId: '<your-workspace>',
  apiKey: 'psk_test_<your-key>',
  environment: PyrxEnvironment.sandbox,
));
final status = await Synapse.requestPushPermission();
print(status); // PushPermissionStatus.granted, hopefully
```

In the Xcode console you should see a log line from the SDK like:

```
[Synapse] Registered for push: <device-token-hex>
```

In the PYRX dashboard → Devices view, your device should now show up
with `sdk_name = PYRXSynapse-Flutter` (or similar — confirm in the
sample app's debugInfo panel).

Send a test push from the dashboard's push composer. It should land
within ~1 second.

---

## 6. The optional manual-forwarding fallback

The plugin auto-installs by extending the `FlutterAppDelegate` plugin
chain — your `AppDelegate.swift` does not need a parent class change.
If your app extends a custom AppDelegate parent (some apps with
multiple SDKs do), the plugin's auto-install MAY conflict with another
SDK's `UIApplicationDelegate` swizzling.

For that case, disable the auto-install and forward the relevant
delegate methods manually:

1. Set `FlutterAppDelegateAutoSetup = false` in your `Info.plist`
   under the `pyrx_synapse` dict (this disables the plugin's
   automatic registration).
2. In your `AppDelegate.swift`, import `PYRXSynapse` and call the
   forward methods directly:

   ```swift
   import UIKit
   import Flutter
   import PYRXSynapse

   @main
   @objc class AppDelegate: MyCustomParent {
     override func application(
       _ application: UIApplication,
       didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
     ) -> Bool {
       Pyrx.shared.applicationDidFinishLaunching(launchOptions: launchOptions)
       GeneratedPluginRegistrant.register(with: self)
       return super.application(application, didFinishLaunchingWithOptions: launchOptions)
     }

     override func application(
       _ application: UIApplication,
       didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
     ) {
       Pyrx.shared.handleDeviceToken(deviceToken)
       super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
     }

     override func application(
       _ application: UIApplication,
       didFailToRegisterForRemoteNotificationsWithError error: Error
     ) {
       Pyrx.shared.handleRegistrationError(error)
       super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
     }
   }
   ```

99% of customers don't need this — the auto-install just works.

---

## Troubleshooting

### `PYRXSynapse-Swift.h not found` during build

Your `pod install` didn't pick up the local SDK. Try:

```bash
flutter clean
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
cd ..
flutter build ios --debug --no-codesign
```

### Push permission granted but no token registers

Double-check the `aps-environment` entitlement is set on your build
configuration (Debug or Release as appropriate). The OS silently
refuses to issue a token if the entitlement is missing or set to the
wrong environment for the provisioning profile.

Verify by looking at the Xcode console for
`application:didRegisterForRemoteNotificationsWithDeviceToken:` —
if it's never called, the entitlement is the issue, not the SDK.

### Pushes work in TestFlight but not in Xcode dev builds (or vice-versa)

Wrong `aps-environment`. TestFlight + App Store need `production`;
Xcode + EAS dev builds need `development`. The PYRX backend
automatically picks the right APNs endpoint per token, so you don't
need to configure anything else.

### "No bundle identifier set" in PYRX dashboard

The dashboard's Apple-Push-Providers configuration needs your exact
Bundle ID (the one set in Xcode → General → Identity, NOT the
project name). Triple-check it matches.
