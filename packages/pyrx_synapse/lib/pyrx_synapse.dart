/// PYRX Synapse Flutter SDK — umbrella package.
///
/// This is the single entry point customers import:
///
/// ```dart
/// import 'package:pyrx_synapse/pyrx_synapse.dart';
///
/// await Synapse.initialize(const PyrxConfig(
///   workspaceId: '...',
///   apiKey: 'psk_test_...',
///   environment: PyrxEnvironment.sandbox,
/// ));
///
/// final sub = Synapse.events.listen((event) {
///   switch (event) {
///     case PushReceived(:final event):
///       print('foreground push: ${event.title}');
///     case PushClicked(:final event):
///       print('tap: ${event.deepLink}');
///     case PushReceivedColdStart(:final event):
///       print('cold-start: ${event.title}');
///     case QueueDrained(:final count):
///       print('flushed $count events');
///     case IdentityChanged(:final before, :final after):
///       print('identity: ${before?.externalId} → ${after.externalId}');
///   }
/// });
/// ```
///
/// What this package exposes:
///
/// - [Synapse] — the static namespace for every imperative API method
///   (initialize / identify / alias / logout / track / screen /
///   requestPushPermission / registerForPushNotifications /
///   setTrackingEnabled / deleteUser / setLogLevel / debugInfo) plus
///   the merged [Synapse.events] `Stream<PyrxEvent>`.
/// - [PyrxConfig], [PyrxEnvironment], [PyrxLogLevel] — typed config
///   surface for [Synapse.initialize].
/// - [PushPermissionStatus], [IdentityResult], [DebugInfo] — typed
///   return shapes.
/// - [PyrxEvent] (sealed) + its 5 leaves: [PushReceived],
///   [PushClicked], [PushReceivedColdStart], [QueueDrained],
///   [IdentityChanged]. Pattern-match exhaustively in `switch`.
/// - [PushReceivedEvent], [PushClickedEvent], [IdentitySnapshot] —
///   typed payload data classes carried by the sealed events.
/// - [PyrxAttributeValue] (sealed) + leaves — typed wrapper around
///   the `pyrx_attrs` map carried by push events.
///
/// Federation re-exports:
///
/// - [PyrxSynapsePlatform] — the abstract platform interface.
///   Customers won't typically reference this directly; it's exposed
///   for advanced test scenarios (e.g. faking the entire platform
///   layer).
library pyrx_synapse;

export 'src/in_app.dart' show InAppRenderCallback, ShowToken, SynapseInApp;
export 'src/payloads/payloads.dart';
export 'src/pyrx_attribute_value.dart';
export 'src/pyrx_event.dart';
export 'src/synapse.dart';

// Re-export the platform-interface surface so consumers don't need an
// extra dependency import to reach [PyrxSynapsePlatform] for advanced
// scenarios. The Pigeon-generated wire DTOs are also re-exported via
// this barrel — they're the seam tests / custom platforms use.
export 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';
