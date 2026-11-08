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

void main() {
  testWidgets('Profile shows header, regular stats, and toggles playoffs',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_FakeApi())],
        child: const MaterialApp(home: ProfileScreen(playerId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Marcus Vale'), findsWidgets); // app bar + header
    expect(find.textContaining('3 seasons'), findsOneWidget); // career span line
    // Regular-season PTS shown; percentage scaled to 47.6.
    expect(find.text('25.1'), findsOneWidget);
    expect(find.text('47.6'), findsOneWidget);
    expect(find.text('28.7'), findsNothing); // playoff row hidden initially

    await tester.tap(find.text('Playoffs'));
    await tester.pumpAndSettle();
    expect(find.text('28.7'), findsOneWidget);
    expect(find.text('25.1'), findsNothing);
  });
}
