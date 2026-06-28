## 0.1.0 - 2026-06-28

First public release of the PYRX Synapse Flutter SDK on pub.dev. Wraps the
native iOS (`PYRXSynapse 0.1.2+`) and Android
(`tech.pyrx.synapse:synapse-{core,push} 0.1.4+`) SDKs through a federated
plugin and exposes a typed Dart surface plus a `Stream<PyrxEvent>` for push,
identity, and queue lifecycle events.

### Public API (umbrella package — `package:pyrx_synapse/pyrx_synapse.dart`)

- `Synapse` static namespace — 12 imperative methods, all returning
  `Future`:
  - Lifecycle: `initialize(PyrxConfig)`, `setLogLevel(PyrxLogLevel)`,
    `debugInfo()`
  - Identity: `identify(externalId, traits: ...)`, `alias(newExternalId)`,
    `logout()`
  - Events: `track(eventName, properties: ...)`,
    `screen(screenName, properties: ...)`
  - Push: `requestPushPermission({alert, sound, badge})`,
    `registerForPushNotifications()`
  - Privacy: `setTrackingEnabled(bool)`, `deleteUser()`
- `Synapse.events` — broadcast `Stream<PyrxEvent>` carrying the
  5-event observer surface fixed in Phase 9.2.1 (ADR-0005):
  - `PushReceived` — foreground push
  - `PushClicked` — warm-start tap
  - `PushReceivedColdStart` — cold-start tap (mutually exclusive with
    `PushClicked` for the same tap; native-side dedup over a 5-second
    `push_log_id` window)
  - `QueueDrained` — internal event queue flushed a non-empty batch
  - `IdentityChanged` — `identify`/`alias`/`logout` resolved a new
    identity, carrying typed `before`/`after` `IdentitySnapshot`s
- Sealed `PyrxAttributeValue` typed sum (`PyrxAttributeStr`,
  `PyrxAttributeInt64`, `PyrxAttributeDbl`, `PyrxAttributeBool`,
  `PyrxAttributeNull`, `PyrxAttributeArr`, `PyrxAttributeObj`) — mirrors
  the native typed attribute value used in push payloads.
- Typed config + result classes: `PyrxConfig`, `PyrxEnvironment`,
  `PyrxLogLevel`, `PushPermissionStatus`, `IdentityResult`, `DebugInfo`,
  and the event payload data classes `PushReceivedEvent`,
  `PushClickedEvent`, `IdentitySnapshot`.

### Federated structure

The package is published as four pub.dev packages in lockstep:

- `pyrx_synapse` — the app-facing umbrella (this one)
- `pyrx_synapse_platform_interface` — the Pigeon-codegen'd contract
- `pyrx_synapse_ios` — iOS Swift bridge
- `pyrx_synapse_android` — Android Kotlin bridge

Consumers add only `pyrx_synapse` to their `pubspec.yaml`; the other
three resolve transitively.

### Toolchain floor

- Flutter `>= 3.24.0`
- Dart SDK `^3.6.0`
- iOS `13.0+` (transitively `14.0+` from `PYRXSynapse`)
- Android `minSdk 24` (transitively from `synapse-core`)

### Notes

- This is a `0.x` release per
  [ADR-0004 D4](https://github.com/PYRX-Tech/pyrx-synapse/blob/master/docs/adr/ADR-0004-phase-8-ga-ready-declaration-and-activation-backlog.md#d4-phase-9-unblocks-on-ga-ready-not-ga-shipped-for-sdk-extension-work).
  A `1.0.0` release follows when the underlying native SDKs reach 1.0
  (gated on Phase 8 GA-Shipped).
- See the [sample app](https://github.com/PYRX-Tech/pyrx-synapse-flutter/tree/main/examples/synapse_flutter_demo)
  for an end-to-end walkthrough of every public surface.
