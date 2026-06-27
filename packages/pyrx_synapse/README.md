# pyrx_synapse

Official Flutter SDK for the [PYRX Synapse](https://synapse.pyrx.tech)
customer communications platform — push notifications, identity, and event
tracking on iOS and Android.

> **Status — PR-1 scaffolding.** This package is the federated-plugin
> umbrella. The app-facing Dart API (`Synapse` namespace,
> `Stream<PyrxEvent>` merger, `PyrxAttributeValue` typed sum) lands in PR-2.
> The native bridges in `pyrx_synapse_ios` + `pyrx_synapse_android` are wired
> through the platform-interface package in PR-1.

## Install (preview)

```yaml
dependencies:
  pyrx_synapse: ^0.1.0
```

```bash
flutter pub get
```

The umbrella package transitively pulls in `pyrx_synapse_platform_interface`,
`pyrx_synapse_ios`, and `pyrx_synapse_android`. Flutter's federated-plugin
resolver wires the right implementation per platform; you do **not** add the
platform packages to your `pubspec.yaml` manually.

## Roadmap

See the repo-level
[README](https://github.com/PYRX-Tech/pyrx-synapse-flutter#roadmap) for the
4-PR ship plan.
