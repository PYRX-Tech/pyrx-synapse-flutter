// EventLog — an in-app rolling log of every event published on
// `Synapse.events`. Subscribed exactly once for the lifetime of the
// app so cold-start replay events from the native SDKs are caught.
//
// Exposes:
//   - `entries`              — current buffered list (ChangeNotifier)
//   - `pushReceivedCount`    — count of PushReceived events seen
//   - `pushClickedCount`     — count of PushClicked events seen
//   - `coldStartCount`       — count of PushReceivedColdStart events seen
//   - `queueDrainCount`      — count of QueueDrained events seen
//   - `identityChangeCount`  — count of IdentityChanged events seen
//
// The screens consume this via `ListenableBuilder` (or by reading the
// counters directly inside their own StreamBuilder/setState patterns).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

/// One observed event + the wall-clock instant the demo received it.
/// `event` is either a real [PyrxEvent] (the common case) or a string
/// describing a stream error (rare — wire-drift only). The two-shape
/// union keeps the observer screen's list simple.
sealed class EventLogEntry {
  EventLogEntry() : observedAt = DateTime.now();
  final DateTime observedAt;

  /// Short single-line description for the observer UI list.
  String get summary;
}

final class ObservedEventEntry extends EventLogEntry {
  ObservedEventEntry(this.event);
  final PyrxEvent event;

  @override
  String get summary {
    final t = observedAt.toIso8601String().substring(11, 19);
    return switch (event) {
      PushReceived(:final event) => '[$t] PushReceived "${event.title}"',
      PushClicked(:final event) =>
        '[$t] PushClicked ${event.deepLink ?? "<no deep link>"}',
      PushReceivedColdStart(:final event) =>
        '[$t] PushReceivedColdStart "${event.title}"',
      QueueDrained(:final count) => '[$t] QueueDrained flushed=$count',
      IdentityChanged(:final before, :final after) =>
        '[$t] IdentityChanged ${before?.externalId ?? "(none)"} → ${after.externalId ?? "(anon)"}',
    };
  }
}

final class StreamErrorEntry extends EventLogEntry {
  StreamErrorEntry(this.message);
  final String message;

  @override
  String get summary {
    final t = observedAt.toIso8601String().substring(11, 19);
    return '[$t] STREAM ERROR: $message';
  }
}

class EventLog extends ChangeNotifier {
  EventLog() {
    _subscription = Synapse.events.listen(
      _onEvent,
      onError: (Object error, StackTrace stackTrace) {
        _entries.insert(0, StreamErrorEntry(error.toString()));
        notifyListeners();
      },
    );
  }

  StreamSubscription<PyrxEvent>? _subscription;

  final List<EventLogEntry> _entries = [];
  List<EventLogEntry> get entries => List.unmodifiable(_entries);

  int _pushReceivedCount = 0;
  int _pushClickedCount = 0;
  int _coldStartCount = 0;
  int _queueDrainCount = 0;
  int _identityChangeCount = 0;

  int get pushReceivedCount => _pushReceivedCount;
  int get pushClickedCount => _pushClickedCount;
  int get coldStartCount => _coldStartCount;
  int get queueDrainCount => _queueDrainCount;
  int get identityChangeCount => _identityChangeCount;

  IdentitySnapshot? _lastIdentitySnapshot;
  IdentitySnapshot? get lastIdentitySnapshot => _lastIdentitySnapshot;

  /// Bump on each observed event + cache a few highlights for screens
  /// that want to pin a single panel ("last identity", etc).
  void _onEvent(PyrxEvent event) {
    switch (event) {
      case PushReceived():
        _pushReceivedCount += 1;
      case PushClicked():
        _pushClickedCount += 1;
      case PushReceivedColdStart():
        _coldStartCount += 1;
      case QueueDrained():
        _queueDrainCount += 1;
      case IdentityChanged(:final after):
        _identityChangeCount += 1;
        _lastIdentitySnapshot = after;
    }
    _entries.insert(0, ObservedEventEntry(event));
    // Cap the log at 200 entries so the observer screen stays snappy.
    if (_entries.length > 200) {
      _entries.removeRange(200, _entries.length);
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
