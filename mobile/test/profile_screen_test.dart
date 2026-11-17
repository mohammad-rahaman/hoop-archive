import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/api_client.dart';
import 'package:hoop_archive/core/api/models.dart';
import 'package:hoop_archive/features/players/profile_screen.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  @override
  Future<PlayerDetail> fetchPlayerDetail(int id) async {
    return const PlayerDetail(
      id: 1,
      fullName: 'Marcus Vale',
      position: 'SG',
      jerseyNumber: '7',
      teams: ['CHI', 'NYK'],
      firstYear: 1996,
      lastYear: 1998,
      seasonCount: 3,
      hasPlayoffs: true,
      seasons: [
        SeasonStatRow(
          season: '1997-98',
          yearStart: 1997,
          seasonType: 'regular',
          team: 'CHI',
          statMode: 'per_game',
          gp: 80,
          pts: 25.1,
          fgPct: 0.476,
        ),
        SeasonStatRow(
          season: '1996-97',
          yearStart: 1996,
          seasonType: 'regular',
          team: 'CHI',
          statMode: 'per_game',
          gp: 74,
          pts: 19.4,
          fgPct: 0.451,
        ),
        SeasonStatRow(
          season: '1997-98',
          yearStart: 1997,
          seasonType: 'playoff',
          team: 'CHI',
          statMode: 'per_game',
          gp: 21,
          pts: 28.7,
          fgPct: 0.477,
        ),
      ],
    );
  }
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(_FakeApi())],
      child: const MaterialApp(home: ProfileScreen(playerId: 1)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Profile shows header and the latest regular season', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Marcus Vale'), findsWidgets); // nav bar + header
    expect(find.textContaining('3 seasons'), findsOneWidget);
    // Hero numeral and the season rail both show the latest PTS.
    expect(find.text('25.1'), findsWidgets);
    // Shooting meter scales the stored fraction to a percentage.
    expect(find.text('47.6%'), findsOneWidget);
    // A stat with no value reads "—", never 0.
    expect(find.text('—'), findsWidgets);
    expect(find.text('0.0%'), findsNothing);
    // Playoff numbers stay out of the regular-season view.
    expect(find.text('28.7'), findsNothing);
  });

  testWidgets('Selecting an older season in the rail updates the hero', (
    tester,
  ) async {
    await _pump(tester);
    await tester.scrollUntilVisible(
      find.text('1996-97'),
      200,
      scrollable: find
          .ancestor(
            of: find.text('Shooting'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('1996-97'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1996-97'));
    await tester.pumpAndSettle();

    expect(find.text('GP'), findsOneWidget); // full stat line expanded
    // Scroll back up: shooting now follows the selected season.
    await tester.scrollUntilVisible(
      find.text('45.1%'),
      -200,
      scrollable: find
          .ancestor(of: find.text('GP'), matching: find.byType(Scrollable))
          .first,
    );
    expect(find.text('45.1%'), findsOneWidget);
  });

  testWidgets('Playoffs toggle swaps to the playoff split only', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Playoffs'));
    await tester.pumpAndSettle();

    expect(find.text('28.7'), findsWidgets);
    expect(find.text('25.1'), findsNothing);
    expect(find.textContaining('One playoff run on record'), findsOneWidget);
  });

  testWidgets('Opens on a requested season (from a season-filtered list)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_FakeApi())],
        child: const MaterialApp(
          home: ProfileScreen(playerId: 1, initialSeason: '1996-97'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('19.4'), findsWidgets); // 1996-97 PTS in the hero
    expect(find.text('45.1%'), findsOneWidget); // and its shooting
  });
}
