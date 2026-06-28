// Barrel for the typed event payload data classes.
//
// These are hand-rolled immutable value classes (per PR-2 Q4 — no
// Freezed) that wrap the Pigeon-generated DTOs in
// `pyrx_synapse_platform_interface`. The wrappers add:
//
//   - Parsed [DateTime]s instead of ISO-8601 strings
//   - Typed `PyrxAttributeValue` maps instead of `Map<String?, Object?>`
//   - Value equality + informative `toString()`
//
// Each payload type is consumed by one (or two, for cold-start) of the
// sealed `PyrxEvent` subtypes in `lib/src/pyrx_event.dart`.

export 'identity_snapshot.dart';
export 'push_clicked_event.dart';
export 'push_received_event.dart';
