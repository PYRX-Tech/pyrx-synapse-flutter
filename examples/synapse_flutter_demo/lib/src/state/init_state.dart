// Tiny global singleton that tracks "has the SDK been initialised yet?"
// + the most recent config used. Screens listen to it so they can disable
// their buttons until init completes.
//
// Why not Provider/Riverpod: the sample is intentionally framework-light
// so the SDK call sites are obvious. ChangeNotifier + a top-level
// instance keeps the wiring readable.

import 'package:flutter/foundation.dart';
import 'package:pyrx_synapse/pyrx_synapse.dart';

class InitState extends ChangeNotifier {
  InitState._();
  static final InitState instance = InitState._();

  bool _initialized = false;
  String? _lastError;
  PyrxConfig? _lastConfig;

  bool get initialized => _initialized;
  String? get lastError => _lastError;
  PyrxConfig? get lastConfig => _lastConfig;

  void markInitializing() {
    _lastError = null;
    notifyListeners();
  }

  void markInitialized(PyrxConfig config) {
    _initialized = true;
    _lastConfig = config;
    _lastError = null;
    notifyListeners();
  }

  void markFailed(Object error) {
    _initialized = false;
    _lastError = error.toString();
    notifyListeners();
  }
}
