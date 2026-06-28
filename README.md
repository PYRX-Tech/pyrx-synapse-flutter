# PYRX Synapse — Flutter SDK

Official Flutter SDK for the [PYRX Synapse](https://synapse.pyrx.tech) customer
communications platform. Wraps the published native SDKs
(`PYRXSynapse` on iOS, `tech.pyrx.synapse:synapse-core` + `:synapse-push` on
Android) and surfaces a single typed Dart API plus a `Stream<PyrxEvent>` for
push, identity, and queue lifecycle events.

> **Status — PR-2 (Dart API surface).** PR-1 shipped the federated plugin
> skeleton, the Pigeon-generated bridge contract, and the iOS + Android native
> bridges. PR-2 (this commit) adds the app-facing Dart API: the `Synapse`
> namespace (12 imperative methods), the merged `Stream<PyrxEvent>`, the sealed
> event hierarchy, the typed `PyrxAttributeValue` sum, and 115 unit tests. The
> sample app + customer-facing docs + pub.dev publish land in PR-3.

## Usage (preview)

```dart
import 'package:pyrx_synapse/pyrx_synapse.dart';

await Synapse.initialize(const PyrxConfig(
  workspaceId: '...',
  apiKey: 'psk_test_...',
  environment: PyrxEnvironment.sandbox,
));

// Subscribe early so cold-start events are caught.
Synapse.events.listen((event) {
  switch (event) {
    case PushReceived(:final event):
      print('foreground push: ${event.title}');
    case PushClicked(:final event):
      print('tap: ${event.deepLink}');
    case PushReceivedColdStart(:final event):
      print('cold-start: ${event.title}');
    case QueueDrained(:final count):
      print('flushed $count events');
    case IdentityChanged(:final before, :final after):
      print('identity: ${before?.externalId} → ${after.externalId}');
  }
});

await Synapse.identify('user_123', traits: {'plan': 'pro'});
await Synapse.track('order_placed', properties: {'order_id': '42'});
await Synapse.requestPushPermission();
```

The full sample app + integration guide ship in PR-3.

## Workspace layout

This repository is a federated Flutter plugin organised as a
[Melos](https://melos.invertase.dev/) workspace:

```
pyrx-synapse-flutter/
├── melos.yaml                   # Workspace scripts (analyze, test, pigeon-*)
├── pubspec.yaml                 # Workspace root (no shippable code)
└── packages/
    ├── pyrx_synapse/                       # App-facing umbrella (PR-2)
    ├── pyrx_synapse_platform_interface/    # Pigeon contract + default impl
    ├── pyrx_synapse_ios/                   # iOS Swift bridge → PYRXSynapse
    └── pyrx_synapse_android/               # Android Kotlin bridge → synapse-core + push
```

Federated structure follows
[Flutter's plugin recommendations](https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins)
and mirrors `firebase_core` / `firebase_messaging`.

## Native SDK dependencies

| Platform | Package                                            | Floor    |
|----------|----------------------------------------------------|----------|
| iOS      | `PYRXSynapse` (CocoaPods + SPM)                    | `0.1.2+` |
| Android  | `tech.pyrx.synapse:synapse-core` (Maven Central)   | `0.1.4+` |
| Android  | `tech.pyrx.synapse:synapse-push` (Maven Central)   | `0.1.4+` |

These versions are the Phase 9.2.1 native-callback-observer release: the
five-event observer surface (`PushReceived`, `PushClicked`,
`PushReceivedColdStart`, `QueueDrained`, `IdentityChanged`) the Flutter SDK
collects from. See
[ADR-0005](https://github.com/PYRX-Tech/pyrx-synapse/blob/master/docs/adr/ADR-0005-native-callback-observer-surface.md)
in the upstream `pyrx.synapse` monorepo for the design.

## Toolchain floor

- Flutter `>= 3.24.0`
- Dart SDK `^3.6.0`
- iOS 14+ (transitively from PYRXSynapse)
- Android `minSdk 24` (transitively from `synapse-core`)
- JDK 17 for the Android Gradle build (`JAVA_HOME=/path/to/jdk-17`)

> **Note on the Dart SDK floor.** Plan D2 targeted Flutter 3.16 / Dart
> 3.2 for the consumer floor. Migrating the workspace to
> [Dart pub workspaces](https://dart.dev/tools/pub/workspaces) (required
> by Melos 8) raised the per-package floor to Dart 3.6, which
> translates to Flutter 3.24+ for SDK consumers. This is documented as
> a deliberate widening: Flutter 3.24 shipped Aug 2024 and is over two
> years old at the time of this writing, so the trade — strictly better
> monorepo tooling against a marginally narrower consumer window —
> favours the workspace setup. Apps still on Flutter 3.16-3.23 can
> integrate the `PYRXSynapse` iOS Pod and the Android Maven artifacts
> directly without this Flutter wrapper.

## Developer setup

```bash
# 1. Install Pigeon (codegen runs from a dev_dependency in the
#    platform-interface package; this global install is for the CLI shim).
dart pub global activate pigeon

# 2. Install Melos.
dart pub global activate melos

# 3. Bootstrap the workspace (resolves all four packages with path overrides).
melos bootstrap

# 4. Quality gates.
melos run analyze
melos run format          # check-only; format-fix to apply
melos run test
melos run pigeon-check    # CI guard: regenerate + diff
```

## Roadmap

The Flutter SDK ships in four PRs against this repo:

| PR | Scope |
|----|-------|
| PR-1 | Repo bootstrap, Pigeon spec, iOS + Android native bridges, smoke tests, CI workflow |
| **PR-2** (this) | App-facing Dart `Synapse` namespace, `Stream<PyrxEvent>` merger via envelope unpacking, sealed `PyrxEvent` hierarchy, typed `PyrxAttributeValue`, 115 unit tests |
| PR-3 | Sample app (`examples/synapse_flutter_demo/`), customer-facing docs, pub.dev publish |
| PR-4 | Upstream monorepo close: `ARCHITECTURE.md §28.7` SDK matrix update + cross-link |

The plan is tracked in the upstream `pyrx.synapse` repo at
[`docs/plans/phase-9.3-flutter-sdk-plan-2026-06-27.md`](https://github.com/PYRX-Tech/pyrx-synapse/blob/master/docs/plans/phase-9.3-flutter-sdk-plan-2026-06-27.md).

## License

MIT — see [LICENSE](./LICENSE).
