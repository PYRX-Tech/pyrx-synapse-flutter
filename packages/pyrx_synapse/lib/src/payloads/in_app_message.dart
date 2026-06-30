// InAppMessage / InAppCta — typed Dart wrappers for the Pigeon-generated
// InAppMessageDto / InAppCtaDto.
//
// Phase 10 PR-2b. Mirrors the cross-SDK symmetric in-app payload shape
// per ADR-0009 D5: same semantic fields with the same names across
// browser / iOS / Android / RN / Flutter.
//
// The native side hands us already-rendered NLT text — `title`, `body`,
// `imageUrl`, `label`, `actionPayload` are all ready to draw verbatim.
// The host app NEVER renders unresolved templates; the SDK does NOT
// render UI.
//
// CTA action types
// ----------------
// Wire form is lowercase snake_case (`deep_link`, `dismiss`, `webview`,
// `callback`); we expose a typed [InAppCtaActionType] enum so consumers
// can pattern-match exhaustively. Unknown action types (none expected
// without a native-SDK release) parse to [InAppCtaActionType.unknown]
// so future tolerance is preserved.

import 'package:meta/meta.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

import '../pyrx_attribute_value.dart';

/// How the host app should handle a CTA tap. Symmetric with the
/// browser, iOS, Android, and RN SDKs per ADR-0009 D5.
enum InAppCtaActionType {
  /// Open the URL via the host app's deep-link router. `actionPayload`
  /// carries the URL.
  deepLink,

  /// Treat as a dismissal — the host app should call
  /// [Synapse.inApp.dismiss] (commonly with `reason: "cta_dismissed"`).
  /// `actionPayload` is typically null.
  dismiss,

  /// Open the URL inside an in-app webview surface. `actionPayload`
  /// carries the URL.
  webview,

  /// Opaque callback — the host app interprets the `actionPayload` per
  /// its own routing convention. The SDK does not parse it.
  callback,

  /// Unknown action type — a future native SDK has emitted a case this
  /// Dart enum doesn't model yet. Forward-compatibility safety net:
  /// parsing never throws, the host app sees this enum value and
  /// chooses how to handle the unknown payload (most apps will treat
  /// it as a no-op or open the raw payload as a deep link).
  unknown;

  /// Parse the wire-shaped string the Pigeon DTO carries.
  static InAppCtaActionType fromWire(String value) {
    switch (value) {
      case 'deep_link':
        return InAppCtaActionType.deepLink;
      case 'dismiss':
        return InAppCtaActionType.dismiss;
      case 'webview':
        return InAppCtaActionType.webview;
      case 'callback':
        return InAppCtaActionType.callback;
      default:
        return InAppCtaActionType.unknown;
    }
  }
}

/// One call-to-action on an [InAppMessage]. NLT source has been
/// resolved against the current contact at fetch time — [label] and
/// [actionPayload] are ready to render verbatim.
///
/// Order inside [InAppMessage.ctas] is server-controlled and meaningful
/// for the host's button row layout.
@immutable
class InAppCta {
  const InAppCta({
    required this.id,
    required this.label,
    required this.actionType,
    required this.actionPayload,
  });

  /// Stable identifier passed back via [Synapse.inApp.markInteracted]
  /// on tap.
  final String id;

  /// NLT-rendered label text.
  final String label;

  /// How the host app should handle the tap.
  final InAppCtaActionType actionType;

  /// NLT-rendered action payload — URL string for [InAppCtaActionType.deepLink]
  /// / [InAppCtaActionType.webview]; opaque string for
  /// [InAppCtaActionType.callback]; null for [InAppCtaActionType.dismiss].
  final String? actionPayload;

  /// Wrap a Pigeon-generated [InAppCtaDto].
  factory InAppCta.fromDto(InAppCtaDto dto) => InAppCta(
        id: dto.id,
        label: dto.label,
        actionType: InAppCtaActionType.fromWire(dto.actionType),
        actionPayload: dto.actionPayload,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InAppCta &&
        other.id == id &&
        other.label == label &&
        other.actionType == actionType &&
        other.actionPayload == actionPayload;
  }

  @override
  int get hashCode => Object.hash(id, label, actionType, actionPayload);

  @override
  String toString() => 'InAppCta('
      'id: $id, label: $label, actionType: $actionType, '
      'actionPayload: $actionPayload'
      ')';
}

/// One in-app message delivered to a render callback registered via
/// [Synapse.inApp.show].
///
/// **The SDK does NOT render this message.** It hands the typed object
/// to the host app's callback; the host draws the UI in whatever style
/// fits its design system. The SDK owns: fetch, in-memory cache,
/// dismissal/impression telemetry, expiry. The SDK does NOT own:
/// pixels, animation, layout, accessibility. PYRX UI Kit is deferred
/// to Phase 10.x.
///
/// Field-for-field mirror of the iOS `InAppMessage` struct + Android
/// `InAppMessage` data class per ADR-0009 D5 / ADR-0008 D2.
@immutable
class InAppMessage {
  const InAppMessage({
    required this.id,
    required this.messageId,
    required this.placement,
    required this.title,
    required this.body,
    required this.imageUrl,
    required this.ctas,
    required this.customData,
    required this.expiresAt,
    required this.priority,
  });

  /// Server-issued assignment id. Pass back via [Synapse.inApp.markInteracted]
  /// / [Synapse.inApp.dismiss] / observer events to identify the message.
  final String id;

  /// The `in_app_messages.id` — stable across assignments. Use for
  /// host-side dedupe when the same template can be re-assigned.
  final String messageId;

  /// Placement key the host app maps to a UI surface (e.g.
  /// `"home_banner"`, `"settings_modal"`).
  final String placement;

  /// NLT-rendered title.
  final String title;

  /// NLT-rendered body.
  final String body;

  /// NLT-rendered image URL, or `null` when the message carries no
  /// image.
  final String? imageUrl;

  /// 0–2 CTAs (Phase 10 v1 scope). Order is server-controlled and
  /// meaningful for the host's button row layout.
  final List<InAppCta> ctas;

  /// Host-app-driven custom JSON. Never NLT-rendered server-side; the
  /// host app uses these fields for custom analytics tags, structured
  /// product lists for host-rendered carousels, etc.
  ///
  /// Wrapped as a typed `Map<String, PyrxAttributeValue>` (same shape
  /// as `pyrxAttrs` on push payloads) so consumers can pattern-match
  /// exhaustively instead of poking at `Object?`. An empty map means
  /// "no custom data" — both null wire and empty wire round-trip to
  /// the same empty map here.
  final Map<String, PyrxAttributeValue> customData;

  /// Expiry instant. Parsed from the wire's ISO-8601 string;
  /// always UTC. `null` when the message has no expiry — the SDK
  /// does NOT auto-evict expired messages from the cache (server-
  /// authoritative recompute on next poll drops them).
  final DateTime? expiresAt;

  /// Host-app sort / queue priority. Higher = more important.
  /// [Synapse.inApp.getActive] sorts by priority desc, then expiry asc.
  final int priority;

  /// Wrap a Pigeon-generated [InAppMessageDto].
  ///
  /// `customData` is run through [PyrxAttributeValue.mapFromJson] to
  /// restore typed pattern-matching; the underlying Pigeon shape is
  /// the same `Map<String?, Object?>` used by `pyrxAttrs` on push
  /// payloads. `expiresAt` is parsed via [DateTime.parse]; parse
  /// failure throws [FormatException].
  factory InAppMessage.fromDto(InAppMessageDto dto) {
    return InAppMessage(
      id: dto.id,
      messageId: dto.messageId,
      placement: dto.placement,
      title: dto.title,
      body: dto.body,
      imageUrl: dto.imageUrl,
      ctas: List<InAppCta>.unmodifiable(
        dto.ctas.map(InAppCta.fromDto),
      ),
      customData: PyrxAttributeValue.mapFromJson(dto.customData),
      expiresAt: dto.expiresAt == null
          ? null
          : DateTime.parse(dto.expiresAt!).toUtc(),
      priority: dto.priority,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InAppMessage) return false;
    if (other.id != id) return false;
    if (other.messageId != messageId) return false;
    if (other.placement != placement) return false;
    if (other.title != title) return false;
    if (other.body != body) return false;
    if (other.imageUrl != imageUrl) return false;
    if (other.priority != priority) return false;
    if (other.expiresAt != expiresAt) return false;
    if (other.ctas.length != ctas.length) return false;
    for (var i = 0; i < ctas.length; i++) {
      if (other.ctas[i] != ctas[i]) return false;
    }
    if (other.customData.length != customData.length) return false;
    for (final entry in customData.entries) {
      if (!other.customData.containsKey(entry.key)) return false;
      if (other.customData[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        messageId,
        placement,
        title,
        body,
        imageUrl,
        priority,
        expiresAt,
        // Map / list hashes are length-based — equality runs the
        // deep compare. Real collisions are rare and acceptable
        // (the hash is just a bucket hint).
        ctas.length,
        customData.length,
      );

  @override
  String toString() => 'InAppMessage('
      'id: $id, messageId: $messageId, placement: $placement, '
      'title: $title, body: $body, imageUrl: $imageUrl, '
      'ctas: $ctas, customData: $customData, expiresAt: $expiresAt, '
      'priority: $priority'
      ')';
}
