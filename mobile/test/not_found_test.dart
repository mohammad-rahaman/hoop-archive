import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/api_client.dart';
import 'package:hoop_archive/core/api/models.dart';
import 'package:hoop_archive/core/router.dart';
import 'package:hoop_archive/features/not_found_screen.dart';

class _MetaApi extends ApiClient {
  _MetaApi() : super(Dio());

  @override
  Future<MetaInfo> fetchMeta() async => const MetaInfo(
    players: 0,
    teams: 0,
    seasons: 0,
    playerSeasonStats: 0,
    seasonYearRange: null,
    sportradarConfigured: false,
    lastSync: null,
  );
}

void main() {
  testWidgets('unknown routes land on the not-found page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_MetaApi())],
        child: MaterialApp.router(routerConfig: appRouter),
      ),
    );
    await tester.pumpAndSettle();

    appRouter.go('/totally/unknown/path');
    await tester.pumpAndSettle();

    expect(find.byType(NotFoundScreen), findsOneWidget);
    expect(find.text("This page doesn't exist"), findsOneWidget);
    expect(find.text('Go home'), findsOneWidget);

    // Returning home works.
    await tester.tap(find.text('Go home'));
    await tester.pumpAndSettle();
    expect(find.byType(NotFoundScreen), findsNothing);
  });
}
