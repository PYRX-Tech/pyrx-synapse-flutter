# pyrx_synapse_platform_interface

Platform-interface contract for the [`pyrx_synapse`](https://pub.dev/packages/pyrx_synapse)
Flutter SDK. Defines the abstract Dart surface that platform
implementations (`pyrx_synapse_ios`, `pyrx_synapse_android`) extend,
plus the [Pigeon](https://pub.dev/packages/pigeon) spec that codegens
the type-safe MethodChannel + EventChannel layer between Dart and the
iOS / Android native SDKs.

**You do not depend on this package directly.** Add the umbrella
`pyrx_synapse` package to your `pubspec.yaml` and let federation pull
this in transitively.

## When you would consume this directly

- You're implementing a **custom platform package** (e.g.,
  `pyrx_synapse_web` wrapping `@pyrx/synapse-browser` via JS interop,
  or `pyrx_synapse_macos` wrapping a future macOS native SDK).
  Subclass `PyrxSynapsePlatform`, install your instance via
  `PyrxSynapsePlatform.instance = ...` in your plugin's
  `registerWith()`, declare your package's
  `flutter.plugin.implements: pyrx_synapse`, and Flutter's
  federated-plugin resolver routes calls to your code on the right
  platform.

- You're writing an integration test that needs to **fake the entire
  platform layer** below the umbrella's transforms. Subclass
  `PyrxSynapsePlatform` (don't go through `Mockito.mock` — the
  PlatformInterface token check rejects untyped mocks), install your
  fake, and the `Synapse.*` calls + `Synapse.events` stream route
  through it without touching real platform channels.

## Federated structure

```text
   ┌──────────────────────────┐
   │  pyrx_synapse (umbrella) │   ← what apps depend on
   └────────────┬─────────────┘
                │ depends on
   ┌────────────▼─────────────┐
   │  pyrx_synapse_platform_  │   ← THIS package
   │  interface               │
   └────┬───────────────┬─────┘
        │ extended by   │ extended by
   ┌────▼────────┐  ┌───▼──────────┐
   │ pyrx_synapse│  │ pyrx_synapse_│
   │ _ios        │  │ android      │
   └─────────────┘  └──────────────┘
```

Mirrors `firebase_core` / `firebase_messaging`. Per
[Flutter's plugin recommendations](https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins).

## Pigeon spec

The single source of truth for the Dart ↔ native wire shape lives at
[`pigeons/pyrx_synapse_messages.dart`](pigeons/pyrx_synapse_messages.dart).
Generated outputs are committed to:

- `lib/src/generated/pyrx_synapse_messages.g.dart` (Dart)
- `../pyrx_synapse_ios/ios/Classes/PyrxSynapseMessages.g.swift` (Swift)
- `../pyrx_synapse_android/android/src/main/kotlin/.../generated/PyrxSynapseMessages.g.kt`
  (Kotlin)

To regenerate after editing the spec, run from the repo root:

```bash
melos run pigeon-generate
melos run pigeon-check   # CI guard — fails if outputs diverge
```

## Repo + issues

The Flutter SDK ships from
[`PYRX-Tech/pyrx-synapse-flutter`](https://github.com/PYRX-Tech/pyrx-synapse-flutter).
File issues there.

## License

MIT — see [LICENSE](./LICENSE).
