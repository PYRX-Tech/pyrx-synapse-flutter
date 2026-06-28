# Changelog — pyrx-synapse-flutter

All notable changes to the PYRX Synapse Flutter SDK. The federated
plugin ships four pub.dev packages in lockstep — per-package
changelogs are at `packages/<package>/CHANGELOG.md`.

This file is the repo-level summary. Use the per-package CHANGELOG
when you need the exact pub.dev release notes.

## [0.1.0] - 2026-06-28

First public release. The Flutter SDK wraps the published native iOS
(`PYRXSynapse 0.1.2+`) and Android
(`tech.pyrx.synapse:synapse-{core,push} 0.1.4+`) SDKs through a
federated plugin per Flutter's recommended pattern.

### Ships as 4 pub.dev packages

- [`pyrx_synapse@0.1.0`](https://pub.dev/packages/pyrx_synapse) — the
  app-facing umbrella. The only package customers add to their
  `pubspec.yaml`.
- [`pyrx_synapse_platform_interface@0.1.0`](https://pub.dev/packages/pyrx_synapse_platform_interface)
  — Pigeon-codegen'd contract.
- [`pyrx_synapse_ios@0.1.0`](https://pub.dev/packages/pyrx_synapse_ios)
  — iOS Swift bridge.
- [`pyrx_synapse_android@0.1.0`](https://pub.dev/packages/pyrx_synapse_android)
  — Android Kotlin bridge.

### Public Dart surface

- `Synapse` namespace — 12 imperative methods:
  - Lifecycle: `initialize`, `setLogLevel`, `debugInfo`
  - Identity: `identify`, `alias`, `logout`
  - Events: `track`, `screen`
  - Push: `requestPushPermission`, `registerForPushNotifications`
  - Privacy: `setTrackingEnabled`, `deleteUser`
- `Synapse.events` — broadcast `Stream<PyrxEvent>` carrying the
  5-event observer surface fixed in Phase 9.2.1 (ADR-0005):
  `PushReceived`, `PushClicked`, `PushReceivedColdStart`,
  `QueueDrained`, `IdentityChanged`
- Sealed `PyrxAttributeValue` typed sum (`Str`, `Int64`, `Dbl`,
  `Bool`, `Null`, `Arr`, `Obj`) mirroring the native typed attribute
  value used in push payloads.
- Typed config + result classes: `PyrxConfig`, `PyrxEnvironment`,
  `PyrxLogLevel`, `PushPermissionStatus`, `IdentityResult`,
  `DebugInfo`, `PushReceivedEvent`, `PushClickedEvent`,
  `IdentitySnapshot`.

### Toolchain floor

- Flutter `>= 3.24.0`
- Dart SDK `^3.6.0`
- iOS `13.0+` (transitively `14.0+` from `PYRXSynapse`)
- Android `minSdk 24` (transitively from `synapse-core`)

### Out of scope (deferred to future phases)

- Flutter Web (use `@pyrx/synapse-browser` via JS interop instead)
- Flutter Desktop (no native SDK exists yet)
- In-app messages (Phase 10 per ADR-0002 D5)
- BLoC / Riverpod / `flutter_hooks` companion packages (planned for
  later minor if demand emerges)

### Documentation

- [Umbrella README](./README.md) — install + quickstart
- [`docs/API.md`](./docs/API.md) — full `Synapse.*` reference
- [`docs/STREAMS.md`](./docs/STREAMS.md) — Stream consumption patterns
- [`docs/EVENTS.md`](./docs/EVENTS.md) — per-event payload reference
- [`docs/INSTALL-IOS.md`](./docs/INSTALL-IOS.md) — iOS Apple Developer
  / APNs setup
- [`docs/INSTALL-ANDROID.md`](./docs/INSTALL-ANDROID.md) — Android
  Firebase / FCM setup
- [`docs/MIGRATING-FROM-NATIVE.md`](./docs/MIGRATING-FROM-NATIVE.md)
  — moving from a direct Swift/Kotlin integration
- [`examples/synapse_flutter_demo/`](./examples/synapse_flutter_demo/)
  — fully-working Flutter app demonstrating every public surface

### Provenance

This release is the culmination of the Phase 9.3 plan:
[`docs/plans/phase-9.3-flutter-sdk-plan-2026-06-27.md`](https://github.com/PYRX-Tech/pyrx-synapse/blob/master/docs/plans/phase-9.3-flutter-sdk-plan-2026-06-27.md)
in the upstream `pyrx.synapse` monorepo.

Shipped in three coordinated PRs:

- PR-1 (#1) — federated 4-package skeleton + Pigeon spec + iOS Swift
  bridge + Android Kotlin bridge + smoke tests + CI scaffold
- PR-2 (#2) — `Synapse` namespace + `Stream<PyrxEvent>` merge +
  sealed `PyrxEvent` hierarchy + `PyrxAttributeValue` typed sum +
  121 unit tests
- PR-3 (#3) — sample app at `examples/synapse_flutter_demo/` +
  customer documentation + pub.dev publish prep

Followed by an upstream monorepo close PR linking
`ARCHITECTURE.md §28.7` to this SDK row.
