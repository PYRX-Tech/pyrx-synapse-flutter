/// PYRX Synapse Flutter SDK — umbrella package.
///
/// **PR-1 scaffolding.** The full app-facing API (the `Synapse` namespace,
/// the merged `Stream<PyrxEvent>`, the `PyrxAttributeValue` typed sum) is
/// implemented in PR-2. This file re-exports the platform-interface types
/// so downstream consumers can already reference event payloads, and acts as
/// the entry point Pigeon-generated platform implementations register
/// against.
library pyrx_synapse;

// Re-export the platform-interface DTOs + abstract base class so PR-2's
// `Synapse` namespace can wrap them without an additional import on the
// customer side.
export 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';
