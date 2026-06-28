# pyrx_synapse_platform_interface

Platform-interface contract for the PYRX Synapse Flutter SDK.

> **Do not depend on this package directly.** App-facing consumers should
> depend on `pyrx_synapse`. This package is consumed by the platform
> implementations (`pyrx_synapse_ios`, `pyrx_synapse_android`) and is published
> only so independent platform implementations can satisfy the same contract.

Following Flutter's
[federated plugin guidance](https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins),
this package:

1. Defines `PyrxSynapsePlatform` — the abstract base class platform
   implementations extend.
2. Holds the [Pigeon](https://pub.dev/packages/pigeon) spec at
   `pigeons/pyrx_synapse_messages.dart`. Pigeon generates type-safe Dart
   (`lib/src/generated/pyrx_synapse_messages.g.dart`), Swift, and Kotlin code
   from this single source of truth.
3. Re-exports the data-transfer types used by the app-facing API.

## Regenerating Pigeon outputs

```bash
# From the repo root:
melos run pigeon-generate

# Or from this package directly:
cd packages/pyrx_synapse_platform_interface
dart pub global run pigeon --input pigeons/pyrx_synapse_messages.dart
```

Generated files are committed to git. CI runs `melos run pigeon-check` to
guarantee the committed outputs match the spec.
