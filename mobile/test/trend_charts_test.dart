import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/models.dart';
import 'package:hoop_archive/features/players/widgets/trend_charts.dart';

SeasonStatRow _row(
  String season,
  int yearStart, {
  String team = 'CHI',
  double? pts,
  double? reb,
  double? ast,
  double? fgPct,
  double? fg3Pct,
  double? ftPct,
}) =>
    SeasonStatRow(
      season: season,
      yearStart: yearStart,
      seasonType: 'regular',
      team: team,
      statMode: 'per_game',
      pts: pts,
      reb: reb,
      ast: ast,
      fgPct: fgPct,
      fg3Pct: fg3Pct,
      ftPct: ftPct,
    );

Future<void> _pump(WidgetTester tester, List<SeasonStatRow> rows) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: SingleChildScrollView(child: PerformanceTrends(rows: rows)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders both charts and legends with multiple seasons',
      (tester) async {
    await _pump(tester, [
      _row('1995-96', 1995, pts: 18.0, reb: 5.0, ast: 4.0, fgPct: 0.44, fg3Pct: 0.33, ftPct: 0.80),
      _row('1996-97', 1996, pts: 22.0, reb: 6.0, ast: 5.0, fgPct: 0.46, fg3Pct: 0.36, ftPct: 0.82),
      _row('1997-98', 1997, pts: 25.0, reb: 7.0, ast: 6.0, fgPct: 0.48, fg3Pct: 0.38, ftPct: 0.85),
    ]);

    expect(find.text('Performance trends'), findsOneWidget);
    expect(find.text('Scoring & production'), findsOneWidget);
    expect(find.text('Shooting splits'), findsOneWidget);
    // Legend entries for every active series.
    for (final label in ['PTS', 'REB', 'AST', 'FG%', '3P%', 'FT%']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('hides entirely with a single season', (tester) async {
    await _pump(tester, [_row('1997-98', 1997, pts: 25.0)]);
    expect(find.text('Performance trends'), findsNothing);
  });

  testWidgets('drops a series that has no recorded values', (tester) async {
    // No 3P% anywhere (older eras) — the 3P% line must not appear.
    await _pump(tester, [
      _row('1980-81', 1980, pts: 20.0, fgPct: 0.50, ftPct: 0.75),
      _row('1981-82', 1981, pts: 24.0, fgPct: 0.52, ftPct: 0.78),
    ]);

    expect(find.text('FG%'), findsOneWidget);
    expect(find.text('FT%'), findsOneWidget);
    expect(find.text('3P%'), findsNothing);
  });

  testWidgets('collapses multi-team seasons to one point (prefers TOT)',
      (tester) async {
    // 1 real season across two teams + a TOT row → still one season, so with a
    // second distinct season the chart renders.
    await _pump(tester, [
      _row('2014-15', 2014, team: 'CHI', pts: 15.0),
      _row('2015-16', 2015, team: 'TOT', pts: 20.0),
      _row('2015-16', 2015, team: 'NYK', pts: 22.0),
      _row('2015-16', 2015, team: 'LAL', pts: 18.0),
    ]);
    // Two distinct seasons → trend renders.
    expect(find.text('Performance trends'), findsOneWidget);
  });
}
