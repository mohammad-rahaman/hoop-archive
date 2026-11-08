import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/api/models.dart';

/// Performance trend charts for a player's career.
///
/// Renders one line per metric over the player's seasons (oldest → newest).
/// Missing values are never plotted as zero — a season without a value is
/// simply omitted from that line, so the chart reflects only recorded data.
class PerformanceTrends extends StatelessWidget {
  /// Rows for the currently selected split (regular OR playoffs), in any order.
  final List<SeasonStatRow> rows;

  const PerformanceTrends({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final points = _collapseToSeasons(rows);
    if (points.length < 2) {
      // A single season is not a trend; the table already shows it.
      return const SizedBox.shrink();
    }

    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance trends',
          style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Per-season progression. Seasons without a recorded value are skipped, '
          'never counted as zero.',
          style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _TrendCard(
          title: 'Scoring & production',
          points: points,
          series: [
            _Series('PTS', cs.primary, (p) => p.pts),
            _Series('REB', const Color(0xFF2E9E6B), (p) => p.reb),
            _Series('AST', const Color(0xFFE08A2B), (p) => p.ast),
          ],
          isPercent: false,
        ),
        const SizedBox(height: 20),
        _TrendCard(
          title: 'Shooting splits',
          points: points,
          series: [
            _Series('FG%', cs.primary, (p) => _asPct(p.fgPct)),
            _Series('3P%', const Color(0xFF8E5BD0), (p) => _asPct(p.fg3Pct)),
            _Series('FT%', const Color(0xFFE08A2B), (p) => _asPct(p.ftPct)),
          ],
          isPercent: true,
        ),
      ],
    );
  }
}

double? _asPct(double? v) => v == null ? null : v * 100;

/// Collapse the split's rows to one representative row per season, preferring
/// the multi-team "TOT" aggregate when a player changed teams mid-season.
/// Returns points sorted oldest → newest.
List<_SeasonPoint> _collapseToSeasons(List<SeasonStatRow> rows) {
  final bySeason = <String, SeasonStatRow>{};
  for (final r in rows) {
    final existing = bySeason[r.season];
    if (existing == null) {
      bySeason[r.season] = r;
    } else if (r.team == 'TOT' && existing.team != 'TOT') {
      bySeason[r.season] = r;
    }
  }
  final list = bySeason.values.map(_SeasonPoint.fromRow).toList()
    ..sort((a, b) => a.yearStart.compareTo(b.yearStart));
  return list;
}

class _SeasonPoint {
  final String season;
  final int yearStart;
  final double? pts;
  final double? reb;
  final double? ast;
  final double? fgPct;
  final double? fg3Pct;
  final double? ftPct;

  const _SeasonPoint({
    required this.season,
    required this.yearStart,
    this.pts,
    this.reb,
    this.ast,
    this.fgPct,
    this.fg3Pct,
    this.ftPct,
  });

  factory _SeasonPoint.fromRow(SeasonStatRow r) => _SeasonPoint(
    season: r.season,
    yearStart: r.yearStart,
    pts: r.pts,
    reb: r.reb,
    ast: r.ast,
    fgPct: r.fgPct,
    fg3Pct: r.fg3Pct,
    ftPct: r.ftPct,
  );

  /// Short axis label, e.g. "'98" for a 1997-98 season.
  String get shortLabel {
    final end = (yearStart + 1) % 100;
    return "'${end.toString().padLeft(2, '0')}";
  }
}

class _Series {
  final String name;
  final Color color;
  final double? Function(_SeasonPoint) value;
  const _Series(this.name, this.color, this.value);
}

class _TrendCard extends StatelessWidget {
  final String title;
  final List<_SeasonPoint> points;
  final List<_Series> series;
  final bool isPercent;

  const _TrendCard({
    required this.title,
    required this.points,
    required this.series,
    required this.isPercent,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    // Only keep series that have at least one recorded value in this split.
    final active = series
        .where((s) => points.any((p) => s.value(p) != null))
        .toList();
    if (active.isEmpty) return const SizedBox.shrink();

    final maxY = _niceMax(active);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              title,
              style: t.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: LineChart(_chartData(context, active, maxY)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [for (final s in active) _LegendDot(series: s)],
          ),
        ],
      ),
    );
  }

  double _niceMax(List<_Series> active) {
    double maxV = 0;
    for (final p in points) {
      for (final s in active) {
        final v = s.value(p);
        if (v != null && v > maxV) maxV = v;
      }
    }
    if (isPercent) return 100;
    if (maxV <= 0) return 10;
    // Round up to a tidy step so the axis breathes a little.
    final step = maxV <= 10
        ? 2
        : maxV <= 30
        ? 5
        : 10;
    return ((maxV / step).ceil() * step + step).toDouble();
  }

  LineChartData _chartData(
    BuildContext context,
    List<_Series> active,
    double maxY,
  ) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final n = points.length;
    final horizInterval = maxY / 4;
    // Show at most ~6 x labels to avoid crowding on long careers.
    final labelStep = (n / 6).ceil().clamp(1, n);

    return LineChartData(
      minX: 0,
      maxX: (n - 1).toDouble(),
      minY: 0,
      maxY: maxY,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => cs.inverseSurface,
          getTooltipItems: (spots) => spots.map((s) {
            final p = points[s.x.toInt()];
            final serie = active[s.barIndex];
            final val = isPercent
                ? '${s.y.toStringAsFixed(1)}%'
                : s.y.toStringAsFixed(1);
            return LineTooltipItem(
              '${serie.name}  $val\n',
              TextStyle(
                color: serie.color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              children: [
                TextSpan(
                  text: p.season,
                  style: TextStyle(
                    color: cs.onInverseSurface.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w400,
                    fontSize: 11,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: horizInterval <= 0 ? null : horizInterval,
        getDrawingHorizontalLine: (_) => FlLine(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            interval: horizInterval <= 0 ? null : horizInterval,
            getTitlesWidget: (value, meta) {
              if (value == meta.max) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  isPercent
                      ? value.toInt().toString()
                      : value.toStringAsFixed(0),
                  style: t.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= n) return const SizedBox.shrink();
              if (i % labelStep != 0 && i != n - 1) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  points[i].shortLabel,
                  style: t.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: [for (final s in active) _barData(s, cs)],
    );
  }

  LineChartBarData _barData(_Series s, ColorScheme cs) {
    // Build spots only where a value is recorded; null seasons are skipped so
    // missing data is never rendered as zero.
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final v = s.value(points[i]);
      if (v != null) spots.add(FlSpot(i.toDouble(), v));
    }
    final single = spots.length == 1;
    return LineChartBarData(
      spots: spots,
      color: s.color,
      barWidth: 2.5,
      isCurved: false,
      dotData: FlDotData(
        show: single || spots.length <= 12,
        getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
          radius: 3,
          color: s.color,
          strokeWidth: 1.5,
          strokeColor: cs.surface,
        ),
      ),
      belowBarData: BarAreaData(show: false),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final _Series series;
  const _LegendDot({required this.series});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: series.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          series.name,
          style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
