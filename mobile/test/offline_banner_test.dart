import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/connectivity.dart';
import 'package:hoop_archive/core/widgets/offline_banner.dart';

Widget _wrap(Widget child, {required bool offline}) {
  return ProviderScope(
    overrides: [isOfflineProvider.overrideWithValue(offline)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('OfflineBanner is hidden when online', (tester) async {
    await tester.pumpWidget(_wrap(const OfflineBanner(), offline: false));
    expect(find.textContaining("offline"), findsNothing);
  });

  testWidgets('OfflineBanner shows a message when offline', (tester) async {
    await tester.pumpWidget(_wrap(const OfflineBanner(), offline: true));
    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('CachedCopyNote shows a saved-copy label with age', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CachedCopyNote(
            cachedAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
          ),
        ),
      ),
    );
    expect(find.textContaining('Saved copy'), findsOneWidget);
    expect(find.textContaining('3h ago'), findsOneWidget);
  });
}
