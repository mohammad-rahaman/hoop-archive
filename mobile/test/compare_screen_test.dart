import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/api_client.dart';
import 'package:hoop_archive/core/api/models.dart';
import 'package:hoop_archive/features/compare/compare_screen.dart';

ComparisonPlayer _cp(int id, String name, {String? season}) => ComparisonPlayer(
  id: id,
  fullName: name,
  position: 'SG',
  teams: const ['CHI'],
  firstYear: 1996,
  lastYear: 1999,
  seasonCount: 3,
  season: season,
);

MetricComparisonRow _m(
  String key,
  String label, {
  double? a,
  double? b,
  String? leader,
  bool percent = false,
}) => MetricComparisonRow(
  key: key,
  label: label,
  unit: percent ? '%' : 'pg',
  percent: percent,
  aValue: a,
  bValue: b,
  leader: leader,
  available: leader != null,
);

SeasonStatRow _season(String label, int year, String team, double pts) =>
    SeasonStatRow(
      season: label,
      yearStart: year,
      seasonType: 'regular',
      team: team,
      statMode: 'per_game',
      gp: 70,
      pts: pts,
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
  seasons: id == 1
      ? [
          _season('1997-98', 1997, 'CHI', 25.1),
          _season('1996-97', 1996, 'CHI', 22.4),
        ]
      : [_season('2020-21', 2020, 'DAL', 27.7)],
);

class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  /// Each comparison request, as "a:season vs b:season".
  final calls = <String>[];

  @override
  Future<PlayerDetail> fetchPlayerDetail(int id) async => _detail(id);

  @override
  Future<PlayerComparison> fetchComparison({
    required int a,
    required int b,
    String seasonType = 'regular',
    String? aSeason,
    String? bSeason,
  }) async {
    calls.add('$a:${aSeason ?? 'career'} vs $b:${bSeason ?? 'career'}');
    return PlayerComparison(
      seasonType: seasonType,
      a: _cp(a, 'Alpha', season: aSeason),
      b: _cp(b, 'Bravo', season: bSeason),
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
    String? aSeason,
    String? bSeason,
  }) async => PlayerComparison(
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
  tester.view.physicalSize = const Size(1179, 2556); // iPhone, 3x
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
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

  testWidgets('preset ids compare careers with leaders and tally', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, const CompareScreen(initialAId: 1, initialBId: 2), api);

    expect(api.calls.last, '1:career vs 2:career');
    expect(find.text('Career'), findsNWidgets(2)); // both slots' lines
    expect(find.text('Career vs career'), findsOneWidget);
    expect(find.text('Alpha leads 3–1'), findsOneWidget);

    expect(find.text('Points'), findsOneWidget);
    expect(find.text('25.0'), findsOneWidget);
    expect(find.text('22.0'), findsOneWidget);
    expect(find.text('Rebounds'), findsOneWidget);
    expect(find.text('50.0%'), findsOneWidget); // percent metric gets a suffix

    // Unavailable metric is excluded from the table but named in the note.
    expect(find.textContaining('PER'), findsOneWidget);
  });

  testWidgets('deep-linked seasons compare one season against another', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(
      tester,
      const CompareScreen(
        initialAId: 1,
        initialBId: 2,
        initialASeason: '1997-98',
        initialBSeason: '2020-21',
      ),
      api,
    );
    expect(api.calls.last, '1:1997-98 vs 2:2020-21');
    expect(find.text('1997-98'), findsOneWidget); // slot A line
    expect(find.text('2020-21'), findsOneWidget); // slot B line
    expect(find.text('SG · CHI'), findsOneWidget); // that season's team
    expect(find.text('SG · DAL'), findsOneWidget);
    expect(find.text('1997-98  vs  2020-21'), findsOneWidget); // verdict
    expect(find.text('Alpha leads 3–1'), findsOneWidget);
    expect(find.textContaining("season's regular-season"), findsOneWidget);
  });

  testWidgets('a season the player never played falls back to the career', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(
      tester,
      const CompareScreen(
        initialAId: 1,
        initialBId: 2,
        initialASeason: '1980-81',
      ),
      api,
    );
    expect(api.calls.last, '1:career vs 2:career');
    expect(find.text('Career'), findsNWidgets(2));
  });

  testWidgets('season sheet lists real seasons and switches that side', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, const CompareScreen(initialAId: 1, initialBId: 2), api);

    await tester.tap(find.text('Career').first);
    await tester.pumpAndSettle();
    expect(find.text('1997-98'), findsOneWidget);
    expect(find.text('1996-97'), findsOneWidget);
    expect(find.text('25.1'), findsOneWidget); // that season's scoring

    await tester.tap(find.text('1996-97'));
    await tester.pumpAndSettle();
    expect(api.calls.last, '1:1996-97 vs 2:career');
    expect(find.text('1996-97'), findsOneWidget); // now the slot's line
    expect(find.text('SG · CHI'), findsOneWidget);
  });

  testWidgets('same player and same line asks for a different season', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, const CompareScreen(initialAId: 1, initialBId: 1), api);
    expect(find.textContaining('Same line on both sides'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('no overlapping stats shows an informative note', (tester) async {
    await _pump(
      tester,
      const CompareScreen(initialAId: 1, initialBId: 2),
      _EmptyApi(),
    );
    expect(find.textContaining('No overlapping'), findsOneWidget);
    expect(find.text('No shared metrics to compare'), findsOneWidget);
  });
}
