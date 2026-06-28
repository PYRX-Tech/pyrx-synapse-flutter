# Android install guide

The `pyrx_synapse` Flutter plugin auto-registers with the Flutter
Android plugin chain and calls `PyrxPush.install(applicationContext)`
during `onAttachedToEngine`, so the SDK boots without any code
changes to your `MainActivity.kt` or `AndroidManifest.xml`. The work
you still have to do is the Firebase-project + app-config side that
no SDK can automate.

This guide assumes you're starting from a Flutter app that's already
running on Android — `flutter run -d <emulator>` succeeds against the
unmodified template. If it doesn't, fix that first (`flutter doctor`
is your friend).

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

This pulls in `pyrx_synapse_android` transitively. The next
`flutter build apk` (or `flutter run`) drives a Gradle sync; the
`tech.pyrx.synapse:synapse-core` and `:synapse-push` AARs download
from Maven Central into your app's classpath.

---

## 2. Toolchain floor

Ensure your `android/app/build.gradle` declares the correct minimum:

```gradle
android {
    compileSdk 34

    defaultConfig {
        minSdk 24
        targetSdk 34
        // ...
    }
}
```

`minSdk 24` is the hard floor (matches `synapse-core`). If your app
declares a lower minSdk, the Gradle build fails with a "manifest
merger" error pointing at this constraint.

The Gradle build itself needs **JDK 17**. If your system Java is
different, set `JAVA_HOME` before invoking Flutter:

```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.0.x.jdk/Contents/Home
flutter build apk
```

Or configure it in your `~/.zshrc` / `~/.bash_profile` so every
shell picks it up.

---

## 3. Firebase project + `google-services.json`

Push delivery on Android goes through Firebase Cloud Messaging (FCM),
so you need a Firebase project linked to your app.

1. **Create the Firebase project** at
   [console.firebase.google.com](https://console.firebase.google.com/).
2. **Add an Android app** to the project — use your app's
   `applicationId` (in `android/app/build.gradle`) as the package name.
3. **Download `google-services.json`** from the Firebase console
   (Project Settings → Your apps → Android → ⚙ → Download).
4. **Place it at** `android/app/google-services.json`. **NOT** at the
   project root, **NOT** in `android/`. Flutter's tooling picks it up
   from this exact location.
5. **Add it to `.gitignore`** — it's app-specific config. (`flutter
   create`'s default `.gitignore` does NOT ignore it; add the line
   yourself.)

Apply the Google Services Gradle plugin:

```gradle
// android/build.gradle (project-level)
buildscript {
    dependencies {
        classpath 'com.google.gms:google-services:4.4.2'
    }
}

// android/app/build.gradle (app-level)
plugins {
    id 'com.android.application'
    id 'kotlin-android'
    id 'dev.flutter.flutter-gradle-plugin'
    id 'com.google.gms.google-services'  // ← add this
}
```

The `synapse-push` AAR depends on `firebase-messaging:24.x` and
auto-registers its FCM service via Android's manifest merger — you do
NOT need to declare a `<service>` block in your `AndroidManifest.xml`.

---

## 4. Configure the PYRX dashboard

In the
[PYRX Synapse dashboard](https://synapse-app.pyrx.tech) under
Settings → Push Providers → Android → upload your Firebase service
account JSON (`Project Settings → Service accounts → Generate new
private key`). The backend uses this credential to send pushes via
FCM HTTP v1.

You'll also enter your Firebase project ID (the dashboard verifies it
matches what's in your uploaded credential).

---

## 5. Android 13+ notification permission

Android 13 introduced runtime `POST_NOTIFICATIONS` permission. The
`synapse-push` AAR auto-adds the manifest entry, but YOUR app must
request the permission at runtime — the SDK does NOT auto-prompt.

Use [`permission_handler`](https://pub.dev/packages/permission_handler)
(or any equivalent) before calling
`Synapse.requestPushPermission()`:

```dart
import 'package:permission_handler/permission_handler.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

Future<void> requestPushPermissionsAndroid13Plus() async {
  // OS-level prompt — required on Android 13+ before pushes display.
  await Permission.notification.request();

  // Then let the Synapse SDK trigger registration. On Android,
  // requestPushPermission is mostly an FCM-token-trigger no-op
  // (the OS prompt above is the real gate).
  await Synapse.requestPushPermission();
}
```

If the OS-level prompt is denied, the FCM token still registers but
the user won't SEE incoming notifications — they'll show in the
notification center but no banner / sound.

---

## 6. Verify the install

Run the sample app or your own app:

```bash
flutter run -d <android-device-or-emulator>
```

In Dart:

```dart
await Synapse.initialize(const PyrxConfig(
  workspaceId: '<your-workspace>',
  apiKey: 'psk_test_<your-key>',
  environment: PyrxEnvironment.sandbox,
));
await Synapse.requestPushPermission();
final info = await Synapse.debugInfo();
print(info.deviceTokenFingerprint); // FCM token, truncated
```

In Logcat (filter by your app's tag or `synapse`):

```
synapse-push: FCM token registered: <token-prefix>...
synapse-core: device registered with backend
```

In the PYRX dashboard → Devices view, your device should now show up
with `sdk_name = PYRXSynapse-Flutter` and `platform = android`.

Send a test push from the dashboard's push composer. It should land
within ~1 second.

---

## 7. ProGuard / R8 (release builds)

The `synapse-core` AAR ships consumer ProGuard rules that preserve
the public API. If your app's R8 setup uses an aggressive shrinker
profile and you see crashes on release builds at first SDK call,
add these rules to `android/app/proguard-rules.pro`:

```proguard
-keep class tech.pyrx.synapse.** { *; }
-keepclassmembers class tech.pyrx.synapse.** { *; }
-dontwarn tech.pyrx.synapse.**
```

This is overkill for most apps — the consumer rules in the AAR
usually suffice — but it's a known-good escape hatch.

---

## Troubleshooting

### "google-services.json is missing"

The Google Services Gradle plugin is added but the JSON file isn't
at `android/app/google-services.json`. Re-download from Firebase
console and place it exactly there.

### Manifest merger conflict on `minSdkVersion`

Your app declares `minSdk < 24`. Bump it to 24 (or higher).
`synapse-core` won't support lower — the native SDK uses APIs only
available on 24+.

### FCM token registers but no push lands

Check three things:

1. The Firebase project ID in `google-services.json` matches the
   one configured on the PYRX dashboard.
2. The dashboard's Firebase service account credential is for the
   SAME Firebase project.
3. The user has granted `POST_NOTIFICATIONS` on Android 13+.

If all three check out, send a push and watch Logcat —
`synapse-push: notification posted` confirms FCM delivered it; if
that line never appears the issue is upstream of the SDK.

### `Pyrx.events` never fires `IdentityChanged` after `identify`

Make sure you `await` the future returned by `Synapse.identify` —
the event fires after the native SDK completes the merge round-trip
to the backend, which takes 100-500ms. If you don't `await` the
identify call, your test may inspect state before the event has
arrived.

### Gradle build fails with `java.lang.UnsupportedClassVersionError`

You're not on JDK 17. Set `JAVA_HOME` and re-run:

```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk-17.0.x.jdk/Contents/Home
flutter build apk
```
