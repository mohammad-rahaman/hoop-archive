import '../../core/api/models.dart';

/// A stat the profile can chart. Percentages are stored 0–1 and shown ×100.
class Metric {
  final String key;
  final String short;
  final String long;
  final bool percent;
  final double? Function(SeasonStatRow r) read;

  const Metric(
    this.key,
    this.short,
    this.long,
    this.read, {
    this.percent = false,
  });

  /// Value on the display scale (percent metrics ×100), or null if missing.
  double? displayValue(SeasonStatRow r) {
    final v = read(r);
    if (v == null) return null;
    return percent ? v * 100 : v;
  }

  /// "25.1" / "47.6", or "—" when the stat was not recorded.
  String format(double? displayed) =>
      displayed == null ? '—' : displayed.toStringAsFixed(1);
}

final List<Metric> profileMetrics = [
  Metric('pts', 'PTS', 'Points', (r) => r.pts),
  Metric('reb', 'REB', 'Rebounds', (r) => r.reb),
  Metric('ast', 'AST', 'Assists', (r) => r.ast),
  Metric('fg_pct', 'FG%', 'Field goal', (r) => r.fgPct, percent: true),
  Metric('fg3_pct', '3P%', 'Three-point', (r) => r.fg3Pct, percent: true),
  Metric('ft_pct', 'FT%', 'Free throw', (r) => r.ftPct, percent: true),
];

Metric metricByKey(String key) => profileMetrics.firstWhere(
  (m) => m.key == key,
  orElse: () => profileMetrics.first,
);

/// One representative row per season, oldest → newest. When a player changed
/// teams mid-season the league "TOT" aggregate represents that season.
List<SeasonStatRow> seasonLine(List<SeasonStatRow> rows) {
  final bySeason = <String, SeasonStatRow>{};
  for (final r in rows) {
    final existing = bySeason[r.season];
    if (existing == null || (r.team == 'TOT' && existing.team != 'TOT')) {
      bySeason[r.season] = r;
    }
  }
  return bySeason.values.toList()
    ..sort((a, b) => a.yearStart.compareTo(b.yearStart));
}

/// Metrics with at least one recorded value in [line]. Never offers a metric
/// that would chart nothing.
List<Metric> availableMetrics(List<SeasonStatRow> line) =>
    profileMetrics.where((m) => line.any((r) => m.read(r) != null)).toList();

/// Index of the season with the highest recorded value, or null.
int? peakIndex(List<SeasonStatRow> line, Metric m) {
  int? best;
  double? bestV;
  for (var i = 0; i < line.length; i++) {
    final v = m.read(line[i]);
    if (v != null && (bestV == null || v > bestV)) {
      best = i;
      bestV = v;
    }
  }
  return best;
}
