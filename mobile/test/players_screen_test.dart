import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/api_client.dart';
import 'package:hoop_archive/core/api/models.dart';
import 'package:hoop_archive/features/players/players_screen.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  @override
  Future<PlayersPage> fetchPlayers({
    String? q,
    String? team,
    String? position,
    int page = 1,
    int pageSize = 25,
  }) async {
    final all = const [
      PlayerListItem(
        id: 1,
        fullName: 'Marcus Vale',
        position: 'SG',
        latestTeam: 'NYK',
        teams: ['CHI', 'NYK'],
        seasonCount: 3,
        firstYear: 1996,
        lastYear: 1998,
        latestSeason: '1998-99',
      ),
      PlayerListItem(
        id: 2,
        fullName: 'Dante Rook',
        position: 'C',
        latestTeam: 'LAL',
        teams: ['LAL'],
        seasonCount: 2,
        firstYear: 1996,
        lastYear: 1997,
        latestSeason: '1997-98',
      ),
    ];
    final items = (q == null || q.isEmpty)
        ? all
        : all
            .where((p) => p.fullName.toLowerCase().contains(q.toLowerCase()))
            .toList();
    return PlayersPage(
      items: items,
      total: items.length,
      page: page,
      pageSize: pageSize,
      hasMore: false,
    );
  }

  @override
  Future<FilterOptions> fetchFilters() async =>
      const FilterOptions(teams: ['CHI', 'LAL', 'NYK'], positions: ['C', 'SG']);
}

void main() {
  testWidgets('Players screen lists players and filters by search',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_FakeApi())],
        child: const MaterialApp(home: PlayersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Marcus Vale'), findsOneWidget);
    expect(find.text('Dante Rook'), findsOneWidget);
    expect(find.text('2 players'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'marcus');
    await tester.pump(const Duration(milliseconds: 400)); // debounce
    await tester.pumpAndSettle();

    expect(find.text('Marcus Vale'), findsOneWidget);
    expect(find.text('Dante Rook'), findsNothing);
  });
}
