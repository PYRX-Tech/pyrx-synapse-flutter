/// Platform-interface contract for the PYRX Synapse Flutter SDK.
///
/// This library exposes:
///
///   - [PyrxSynapsePlatform] — the abstract base class that platform
///     implementations (`pyrx_synapse_ios`, `pyrx_synapse_android`) extend.
///   - [MethodChannelPyrxSynapse] — the default implementation that routes
///     calls through the Pigeon-generated `PyrxSynapseHostApi` proxy and
///     receives events through the Pigeon-generated `PyrxSynapseEventApi`
///     stream channel.
///   - The Pigeon-generated DTO types (`PyrxInitArgs`, `PyrxIdentityResult`,
///     `PyrxDebugInfo`, `PyrxPushPermissionResult`, `PyrxEventEnvelope`,
///     `PushReceivedEventDto`, `PushClickedEventDto`, `IdentitySnapshotDto`,
///     `QueueDrainedEventDto`, `IdentityChangedEventDto`, `PyrxEventKind`).
///
/// **Customers do not import this package directly** — they import
/// `package:pyrx_synapse/pyrx_synapse.dart`, which re-exports everything
/// you need and (in PR-2) layers a Dart-idiomatic `Synapse` namespace on
/// top.
library pyrx_synapse_platform_interface;

export 'src/platform_interface.dart';
export 'src/method_channel.dart';
// Re-export Pigeon-generated wire types so platform impls (and PR-2's
// umbrella) can reference them without an additional import.
export 'src/generated/pyrx_synapse_messages.g.dart'
    show
        IdentityChangedEventDto,
        IdentitySnapshotDto,
        PushClickedEventDto,
        PushReceivedEventDto,
        PyrxDebugInfo,
        PyrxEventEnvelope,
        PyrxEventKind,
        PyrxIdentityResult,
        PyrxInitArgs,
        PyrxPushPermissionResult,
        QueueDrainedEventDto;
