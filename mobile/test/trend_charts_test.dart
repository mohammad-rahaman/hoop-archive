import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/models.dart';
import 'package:hoop_archive/features/players/career.dart';
import 'package:hoop_archive/features/players/widgets/trend_charts.dart';

SeasonStatRow _row(
  String season,
  int yearStart, {
  String team = 'CHI',
  double? pts,
  double? fgPct,
  double? fg3Pct,
  double? ftPct,
}) => SeasonStatRow(
  season: season,
  yearStart: yearStart,
  seasonType: 'regular',
  team: team,
  statMode: 'per_game',
  pts: pts,
  fgPct: fgPct,
  fg3Pct: fg3Pct,
  ftPct: ftPct,
);

void main() {
  group('career helpers', () {
    test('seasonLine collapses multi-team seasons, preferring TOT', () {
      final line = seasonLine([
        _row('2015-16', 2015, team: 'NYK', pts: 22),
        _row('2014-15', 2014, pts: 15),
        _row('2015-16', 2015, team: 'TOT', pts: 20),
        _row('2015-16', 2015, team: 'LAL', pts: 18),
      ]);
      expect(line.map((r) => r.season), ['2014-15', '2015-16']);
      expect(line.last.team, 'TOT');
      expect(line.last.pts, 20);
    });

    test('availableMetrics drops a stat with no recorded values', () {
      final line = seasonLine([
        _row('1980-81', 1980, pts: 20, fgPct: 0.5, ftPct: 0.75),
        _row('1981-82', 1981, pts: 24, fgPct: 0.52, ftPct: 0.78),
      ]);
      final keys = availableMetrics(line).map((m) => m.short).toList();
      expect(keys, containsAll(['PTS', 'FG%', 'FT%']));
      expect(keys, isNot(contains('3P%')));
    });

    test('peakIndex skips missing values instead of treating them as zero', () {
      final line = seasonLine([
        _row('1990-91', 1990, pts: 12),
        _row('1991-92', 1991),
        _row('1992-93', 1992, pts: 19),
      ]);
      expect(peakIndex(line, metricByKey('pts')), 2);
      expect(peakIndex(line, metricByKey('fg3_pct')), isNull);
    });

    test('percent metrics display on a 0–100 scale; missing reads "—"', () {
      final m = metricByKey('fg_pct');
      final r = _row('1997-98', 1997, fgPct: 0.476);
      expect(m.format(m.displayValue(r)), '47.6');
      expect(m.format(m.displayValue(_row('1997-98', 1997))), '—');
    });
  });

  group('CareerChart', () {
    final line = seasonLine([
      _row('1995-96', 1995, pts: 18),
      _row('1996-97', 1996), // not recorded: a gap, not a zero
      _row('1997-98', 1997, pts: 25),
    ]);

    Future<List<int>> pump(WidgetTester tester) async {
      final picks = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder: (context, setState) => CareerChart(
                    line: line,
                    metric: metricByKey('pts'),
                    selected: picks.isEmpty ? 0 : picks.last,
                    onSelect: (i) => setState(() => picks.add(i)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return picks;
    }

    testWidgets('tapping near the right edge selects the latest season', (
      tester,
    ) async {
      final picks = await pump(tester);
      final box = tester.getRect(find.byType(CareerChart));
      await tester.tapAt(Offset(box.right - 4, box.center.dy));
      await tester.pumpAndSettle();
      expect(picks, [2]);
    });

    testWidgets('dragging scrubs through every season in order', (
      tester,
    ) async {
      final picks = await pump(tester);
      final box = tester.getRect(find.byType(CareerChart));
      final g = await tester.startGesture(Offset(box.left + 4, box.center.dy));
      await g.moveTo(Offset(box.center.dx, box.center.dy));
      await tester.pump();
      await g.moveTo(Offset(box.right - 4, box.center.dy));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(picks, [1, 2]);
    });

    testWidgets('exposes the selected season to screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      expect(
        find.bySemanticsLabel(RegExp(r'Points by season\. 1995-96: 18\.0')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
