import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/api_client.dart';
import 'package:hoop_archive/core/api/models.dart';
import 'package:hoop_archive/features/compare/compare_screen.dart';

ComparisonPlayer _cp(int id, String name) => ComparisonPlayer(
      id: id,
      fullName: name,
      position: 'SG',
      teams: const ['CHI'],
      firstYear: 1996,
      lastYear: 1999,
      seasonCount: 3,
    );

MetricComparisonRow _m(
  String key,
  String label, {
  double? a,
  double? b,
  String? leader,
  bool percent = false,
}) =>
    MetricComparisonRow(
      key: key,
      label: label,
      unit: percent ? '%' : 'pg',
      percent: percent,
      aValue: a,
      bValue: b,
      leader: leader,
      available: leader != null,
    );

PlayerDetail _detail(int id) => PlayerDetail(
      id: id,
      fullName: id == 1 ? 'Alpha' : 'Bravo',
      position: 'SG',
      jerseyNumber: null,
      teams: const ['CHI'],
      firstYear: 1996,
      lastYear: 1999,
      seasonCount: 3,
      hasPlayoffs: false,
      seasons: const [],
    );

class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  @override
  Future<PlayerDetail> fetchPlayerDetail(int id) async => _detail(id);

  @override
  Future<PlayerComparison> fetchComparison({
    required int a,
    required int b,
    String seasonType = 'regular',
  }) async =>
      PlayerComparison(
        seasonType: seasonType,
        a: _cp(a, 'Alpha'),
        b: _cp(b, 'Bravo'),
        metrics: [
          _m('pts', 'Points', a: 25.0, b: 22.0, leader: 'a'),
          _m('reb', 'Rebounds', a: 5.0, b: 8.0, leader: 'b'),
          _m('ast', 'Assists', a: 6.0, b: 4.0, leader: 'a'),
          _m('fg_pct', 'FG%', a: 0.5, b: 0.45, leader: 'a', percent: true),
          _m('per', 'PER', a: null, b: null, leader: null),
        ],
        aWins: 3,
        bWins: 1,
        ties: 0,
      );
}

/// Returns a comparison where nothing is available (e.g. a missing split).
class _EmptyApi extends ApiClient {
  _EmptyApi() : super(Dio());

  @override
  Future<PlayerDetail> fetchPlayerDetail(int id) async => _detail(id);

  @override
  Future<PlayerComparison> fetchComparison({
    required int a,
    required int b,
    String seasonType = 'regular',
  }) async =>
      PlayerComparison(
        seasonType: seasonType,
        a: _cp(a, 'Alpha'),
        b: _cp(b, 'Bravo'),
        metrics: [
          _m('pts', 'Points', a: null, b: null, leader: null),
          _m('reb', 'Rebounds', a: null, b: null, leader: null),
        ],
        aWins: 0,
        bWins: 0,
        ties: 0,
      );
}

Future<void> _pump(WidgetTester tester, Widget screen, ApiClient api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty state prompts for two players', (tester) async {
    await _pump(tester, const CompareScreen(), _FakeApi());
    expect(find.text('Pick two players to compare'), findsOneWidget);
    expect(find.text('Add player'), findsNWidgets(2));
  });

  testWidgets('preset ids render comparison with leaders and tally',
      (tester) async {
    await _pump(
        tester, const CompareScreen(initialAId: 1, initialBId: 2), _FakeApi());

    // Tally reflects 3–1 in Alpha's favour.
    expect(find.text('Alpha leads 3–1'), findsOneWidget);

    // Available metrics are shown with their values.
    expect(find.text('Points'), findsOneWidget);
    expect(find.text('25.0'), findsOneWidget);
    expect(find.text('22.0'), findsOneWidget);
    expect(find.text('Rebounds'), findsOneWidget);

    // Percent metric renders with a % suffix.
    expect(find.text('50.0%'), findsOneWidget);

    // Unavailable metric is excluded from the table but named in the note.
    expect(find.textContaining('PER'), findsOneWidget);
  });

  testWidgets('no overlapping stats shows an informative note', (tester) async {
    await _pump(
        tester, const CompareScreen(initialAId: 1, initialBId: 2), _EmptyApi());
    expect(find.textContaining('No overlapping'), findsOneWidget);
    expect(find.text('No shared metrics to compare'), findsOneWidget);
  });
}
