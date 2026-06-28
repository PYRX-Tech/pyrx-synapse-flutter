// IdentitySnapshot — typed Dart wrapper for the Pigeon-generated
// IdentitySnapshotDto.
//
// The wire DTO carries [snapshotAt] as an ISO-8601 string because the
// Pigeon standard codec doesn't ship a portable [DateTime] type that
// round-trips across iOS / Android with consistent zone handling. The
// native sides format with ISO8601DateFormatter (iOS) and
// DateTimeFormatter.ISO_INSTANT (Android), both producing UTC
// "...Z"-suffixed instants. This wrapper parses them into Dart
// [DateTime]s in UTC.
//
// Why parse here, not at the platform-interface seam: ISO-8601 parsing
// is app-facing semantics (a DateTime is what consumers want); the
// wire layer (Pigeon) treats this purely as bytes. Keeping the parse
// here lets a future `pyrx_synapse_web` package mint its own
// IdentitySnapshot from a different upstream shape without breaking
// the typed wrapper contract.

import 'package:meta/meta.dart';
import 'package:pyrx_synapse_platform_interface/pyrx_synapse_platform_interface.dart';

/// A point-in-time view of the SDK's resolved identity.
///
/// Carried by [IdentityChanged] events as both `before` and `after`
/// snapshots. The shape mirrors native iOS `IdentitySnapshot` and
/// Android `IdentitySnapshot` exactly:
///
/// - **Anonymous-only session**: `anonymousId` set, `externalId` null
/// - **Known user**: both `anonymousId` and `externalId` set
/// - **After logout**: returns to anonymous-only shape with a freshly-
///   rolled `anonymousId`
///
/// Identity transitions can be detected from a `before`/`after` pair:
///
/// - **Login**:  `before?.externalId == null && after.externalId != null`
/// - **Logout**: `before?.externalId != null && after.externalId == null`
/// - **Switch**: both non-null AND `before.externalId != after.externalId`
@immutable
class IdentitySnapshot {
  const IdentitySnapshot({
    required this.anonymousId,
    required this.externalId,
    required this.snapshotAt,
  });

  /// The SDK-minted anonymous device identifier (UUIDv4, persisted at
  /// first launch). Survives identify/alias/logout — does not change
  /// over the SDK's lifetime on a given install. May be `null`
  /// transiently for the very first snapshot of a fresh install before
  /// storage is seeded.
  final String? anonymousId;

  /// The canonical user identifier passed to [Synapse.identify], or
  /// `null` for anonymous-only sessions / after [Synapse.logout].
  final String? externalId;

  /// Wall-clock instant the snapshot was captured. Always UTC.
  final DateTime snapshotAt;

  /// Wrap a Pigeon-generated [IdentitySnapshotDto]. The
  /// `snapshotAt` ISO-8601 string is parsed to a UTC [DateTime];
  /// parse failure throws [FormatException] (loud-fail on wire drift).
  factory IdentitySnapshot.fromDto(IdentitySnapshotDto dto) {
    return IdentitySnapshot(
      anonymousId: dto.anonymousId,
      externalId: dto.externalId,
      snapshotAt: DateTime.parse(dto.snapshotAt).toUtc(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IdentitySnapshot &&
        other.anonymousId == anonymousId &&
        other.externalId == externalId &&
        other.snapshotAt == snapshotAt;
  }

  @override
  int get hashCode => Object.hash(anonymousId, externalId, snapshotAt);

  @override
  String toString() {
    return 'IdentitySnapshot('
        'anonymousId: $anonymousId, '
        'externalId: $externalId, '
        'snapshotAt: $snapshotAt'
        ')';
  }
}
