import 'package:flutter/foundation.dart';

/// Runtime configuration. The API base URL can be overridden at build/run time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
///
/// Defaults are chosen so the app talks to a backend running on the dev machine:
///   * Android emulator reaches the host loopback via 10.0.2.2
///   * iOS simulator can use localhost directly
class Env {
  const Env._();

  static const String _override = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }
}
