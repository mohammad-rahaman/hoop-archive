import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits whether the device currently has a network path. This is a hint for
/// UI (showing an "offline" affordance), not a gate on requests — the response
/// cache is what actually keeps the app usable, and a request is still allowed
/// to try even if this reports offline.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
});

/// True only when connectivity has been positively determined to be offline.
/// While the first reading is still pending we report online, so screens don't
/// flash an offline banner on launch.
final isOfflineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).valueOrNull == false;
});
