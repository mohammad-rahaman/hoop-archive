import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/api_client.dart';
import 'package:hoop_archive/core/api/models.dart';
import 'package:hoop_archive/main.dart';

void main() {
  testWidgets('Home renders brand and overview from meta', (tester) async {
    const fakeMeta = MetaInfo(
      players: 42,
      teams: 7,
      seasons: 9,
      playerSeasonStats: 123,
      seasonYearRange: [1980, 2020],
      sportradarConfigured: false,
      lastSync: null,
    );

    tester.view.physicalSize = const Size(1179, 2556); // iPhone, 3x
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [metaProvider.overrideWith((ref) async => fakeMeta)],
        child: const HoopArchiveApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hoop Archive'), findsWidgets); // large + collapsed title
    expect(find.text('42'), findsOneWidget); // players figure
    expect(find.text('Search 42 players'), findsOneWidget);
    expect(find.text('Not configured'), findsOneWidget); // live data honest
    expect(find.text('1980'), findsOneWidget); // season ruler ends
    expect(find.text('2021'), findsOneWidget);
  });
}
