import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/offline_banner.dart';
import '../../core/widgets/player_avatar.dart';
import '../../core/widgets/ui.dart';
import 'career.dart';
import 'widgets/trend_charts.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final int playerId;

  /// Season to open on (e.g. "2015-16"), as when arriving from a
  /// season-filtered list. Falls back to the latest season if absent.
  final String? initialSeason;
  const ProfileScreen({super.key, required this.playerId, this.initialSeason});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _playoffs = false;
  String _metric = 'pts';

  /// Selected season label within the current split; null = latest.
  late String? _season = widget.initialSeason;

  /// Row (season + team) whose full stat line is expanded.
  String? _expanded;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(playerDetailProvider(widget.playerId));
    final d = detail.valueOrNull;

    return Scaffold(
      appBar: CupertinoNavigationBar(
        middle: Text(d?.fullName ?? 'Player'),
        previousPageTitle: 'Players',
        backgroundColor: Hue.ground,
        border: const Border(bottom: BorderSide(color: Hue.hairline)),
        transitionBetweenRoutes: false,
        trailing: d == null
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                // Carries the season you're looking at into Compare, so a
                // single-season line is compared rather than the career.
                onPressed: () => context.go(
                  _season == null
                      ? '/compare?a=${widget.playerId}'
                      : '/compare?a=${widget.playerId}&as=$_season',
                ),
                child: const Icon(
                  CupertinoIcons.arrow_right_arrow_left,
                  size: 22,
                  semanticLabel: 'Compare with another player',
                ),
              ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: detail.when(
              loading: () => const Loading(),
              error: (e, _) {
                final notFound =
                    e is DioException && e.response?.statusCode == 404;
                return MessageState(
                  icon: notFound
                      ? CupertinoIcons.person_crop_circle_badge_xmark
                      : CupertinoIcons.wifi_slash,
                  title: notFound
                      ? 'Player not found'
                      : "Couldn't load this player",
                  message: notFound
                      ? 'This player is no longer in the archive.'
                      : 'Check your connection and try again.',
                  actionLabel: notFound ? null : 'Retry',
                  onAction: notFound
                      ? null
                      : () => ref.invalidate(
                          playerDetailProvider(widget.playerId),
                        ),
                );
              },
              data: _body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(PlayerDetail d) {
    final outcome = ref
        .read(apiClientProvider)
        .cache
        ?.outcomeFor(ApiClient.playerKey(widget.playerId));
    final cachedAt = (outcome?.fromCache ?? false) ? outcome!.cachedAt : null;

    final rows = d.seasons.where((s) => s.isPlayoff == _playoffs).toList();
    final line = seasonLine(rows);
    final metrics = availableMetrics(line);
    final metric = metrics.any((m) => m.key == _metric)
        ? metricByKey(_metric)
        : (metrics.isNotEmpty ? metrics.first : metricByKey('pts'));
    var selected = line.indexWhere((r) => r.season == _season);
    if (selected < 0) selected = line.isEmpty ? 0 : line.length - 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
      children: [
        if (cachedAt != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: CachedCopyNote(cachedAt: cachedAt),
          ),
          const SizedBox(height: 16),
        ],
        _Header(detail: d),
        const SizedBox(height: 20),
        if (d.hasPlayoffs) ...[
          SplitControl(
            playoffs: _playoffs,
            onChanged: (v) => setState(() {
              _playoffs = v;
              _season = null;
              _expanded = null;
            }),
          ),
          const SizedBox(height: 14),
        ],
        if (line.isEmpty)
          Panel(
            child: MessageState(
              icon: CupertinoIcons.chart_bar,
              title: _playoffs ? 'No playoff record' : 'No stats recorded',
              message: 'Nothing is recorded for this split.',
            ),
          )
        else ...[
          _HeroPanel(
            line: line,
            metrics: metrics,
            metric: metric,
            selected: selected,
            playoffs: _playoffs,
            onMetric: (m) => setState(() => _metric = m.key),
            onSeason: (i) => setState(() => _season = line[i].season),
          ),
          const SizedBox(height: 14),
          _ShootingPanel(
            row: line[selected],
            metric: metric,
            onMetric: (m) => setState(() => _metric = m.key),
          ),
          const SizedBox(height: 32),
          SectionHeading(
            'Seasons',
            note: rows.first.statMode == 'per_game'
                ? 'Per-game averages'
                : 'Season totals',
          ),
          _SeasonTable(
            rows: rows,
            selectedSeason: line[selected].season,
            expanded: _expanded,
            onTap: (r) => setState(() {
              _season = r.season;
              final key = '${r.season}|${r.team}';
              _expanded = _expanded == key ? null : key;
            }),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '"—" means the stat was not recorded for that season. It is '
              'never counted as zero.',
              style: Txt.caption.copyWith(color: Hue.textLo),
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final PlayerDetail detail;
  const _Header({required this.detail});

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (detail.position != null) detail.position!,
      if (detail.jerseyNumber != null) '#${detail.jerseyNumber}',
      detail.careerSpan,
      '${detail.seasonCount} season${detail.seasonCount == 1 ? '' : 's'}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PlayerAvatar(
              imageUrl: detail.imageUrl,
              initials: detail.initials,
              radius: 34,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detail.fullName, style: Txt.title),
                  const SizedBox(height: 5),
                  Text(meta, style: Txt.caption),
                ],
              ),
            ),
          ],
        ),
        if (detail.teams.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in detail.teams) StatusPill(t)],
          ),
        ],
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  final List<SeasonStatRow> line;
  final List<Metric> metrics;
  final Metric metric;
  final int selected;
  final bool playoffs;
  final ValueChanged<Metric> onMetric;
  final ValueChanged<int> onSeason;

  const _HeroPanel({
    required this.line,
    required this.metrics,
    required this.metric,
    required this.selected,
    required this.playoffs,
    required this.onMetric,
    required this.onSeason,
  });

  /// "points per game", "field goal percentage", or a season total.
  String _unit(SeasonStatRow row) {
    if (metric.percent) return '${metric.long.toLowerCase()} percentage';
    final noun = metric.long.toLowerCase();
    return row.statMode == 'per_game'
        ? '$noun per game'
        : '$noun, season total';
  }

  @override
  Widget build(BuildContext context) {
    final row = line[selected];
    final v = metric.displayValue(row);
    final team = row.team == 'TOT' ? 'Split across teams' : row.team;
    final peak = peakIndex(line, metric);

    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final m in metrics)
                  _MetricTab(
                    metric: m,
                    active: m.key == metric.key,
                    onTap: () => onMetric(m),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // The number, with its meaning set beside it rather than under it.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      text: metric.format(v),
                      children: [
                        if (metric.percent && v != null)
                          TextSpan(
                            text: '%',
                            style: Txt.numeralM.copyWith(color: Hue.textMid),
                          ),
                      ],
                    ),
                    style: Txt.numeralXL.copyWith(
                      color: v == null ? Hue.textLo : Hue.textHi,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v == null ? 'not recorded' : _unit(row),
                      maxLines: 2,
                      style: Txt.body.copyWith(
                        color: Hue.textMid,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${row.season} · $team',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Txt.caption.copyWith(color: Hue.textHi),
                    ),
                    if (row.gp != null)
                      Text('${row.gp} games', style: Txt.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (line.length >= 2)
            CareerChart(
              line: line,
              metric: metric,
              selected: selected,
              onSelect: onSeason,
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'One ${playoffs ? 'playoff run' : 'season'} on record. A '
                'trend needs at least two.',
                style: Txt.caption,
              ),
            ),
          if (peak != null && line.length >= 2) ...[
            const SizedBox(height: 10),
            const Divider(),
            _HighLine(
              row: line[peak],
              metric: metric,
              onTap: () => onSeason(peak),
            ),
          ],
        ],
      ),
    );
  }
}

/// The career high for the current metric, as a quiet line under the chart.
/// Tapping it jumps the chart to that season.
class _HighLine extends StatelessWidget {
  final SeasonStatRow row;
  final Metric metric;
  final VoidCallback onTap;
  const _HighLine({
    required this.row,
    required this.metric,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final v = metric.displayValue(row);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Text('Career high', style: Txt.caption),
            const SizedBox(width: 12),
            // Shrinks (and ellipsizes) rather than overflowing at large
            // Dynamic Type sizes.
            Expanded(
              child: Text.rich(
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${metric.format(v)}${metric.percent ? '%' : ''}',
                      style: Txt.numeralS.copyWith(fontSize: 15),
                    ),
                    TextSpan(
                      text: '  in ${row.season}',
                      style: Txt.caption.copyWith(color: Hue.textMid),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 13,
              color: Hue.textLo,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTab extends StatelessWidget {
  final Metric metric;
  final bool active;
  final VoidCallback onTap;
  const _MetricTab({
    required this.metric,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: metric.long,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(right: 18),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                metric.short,
                style: Txt.label.copyWith(
                  fontSize: 12,
                  color: active ? Hue.volt : Hue.textLo,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 2,
                width: active ? 18 : 0,
                color: Hue.volt,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShootingPanel extends StatelessWidget {
  final SeasonStatRow row;
  final Metric metric;
  final ValueChanged<Metric> onMetric;
  const _ShootingPanel({
    required this.row,
    required this.metric,
    required this.onMetric,
  });

  @override
  Widget build(BuildContext context) {
    final shooting = profileMetrics.where((m) => m.percent).toList();
    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Shooting', style: Txt.headline)),
              Text(row.season, style: Txt.caption),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < shooting.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(
                  child: _ShotGauge(
                    metric: shooting[i],
                    row: row,
                    active: shooting[i].key == metric.key,
                    onTap: () => onMetric(shooting[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One shooting split: the rate, then a 10-cell gauge (each cell is 10%).
/// A missing rate leaves every cell empty and reads "—".
class _ShotGauge extends StatelessWidget {
  final Metric metric;
  final SeasonStatRow row;
  final bool active;
  final VoidCallback onTap;
  const _ShotGauge({
    required this.metric,
    required this.row,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final f = metric.read(row);
    final shown = f == null
        ? '—'
        : '${metric.format(metric.displayValue(row))}%';
    final filled = f == null ? 0 : (f.clamp(0.0, 1.0) * 10).round();
    final on = active ? Hue.volt : const Color(0xFF8A8A86);
    return Semantics(
      button: true,
      selected: active,
      label: '${metric.long} $shown',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              metric.short,
              style: Txt.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Hue.volt : Hue.textMid,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                shown,
                style: Txt.numeralM.copyWith(
                  fontSize: 24,
                  color: f == null ? Hue.textLo : Hue.textHi,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var c = 0; c < 10; c++)
                  Expanded(
                    child: Container(
                      height: 9,
                      margin: EdgeInsets.only(right: c == 9 ? 0 : 2),
                      decoration: BoxDecoration(
                        color: c < filled ? on : Hue.track,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Seasons as a table, newest first. The selected season's row is lifted;
/// tapping a row selects that season and opens its full stat line.
class _SeasonTable extends StatelessWidget {
  final List<SeasonStatRow> rows;
  final String selectedSeason;
  final String? expanded;
  final ValueChanged<SeasonStatRow> onTap;

  const _SeasonTable({
    required this.rows,
    required this.selectedSeason,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(
              children: [
                Expanded(child: TrackedLabel('Season', color: Hue.textLo)),
                _Col(child: TrackedLabel('PTS', color: Hue.textLo)),
                _Col(child: TrackedLabel('REB', color: Hue.textLo)),
                _Col(child: TrackedLabel('AST', color: Hue.textLo)),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i == 0 || rows[i - 1].season != rows[i].season) const Divider(),
            _SeasonRow(
              row: rows[i],
              firstOfSeason: i == 0 || rows[i - 1].season != rows[i].season,
              selected: rows[i].season == selectedSeason,
              expanded: expanded == '${rows[i].season}|${rows[i].team}',
              onTap: () => onTap(rows[i]),
            ),
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _Col extends StatelessWidget {
  final Widget child;
  const _Col({required this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    child: Align(alignment: Alignment.centerRight, child: child),
  );
}

String _num(double? v) => v == null ? '—' : v.toStringAsFixed(1);
String _pct(double? v) => v == null ? '—' : (v * 100).toStringAsFixed(1);

class _SeasonRow extends StatelessWidget {
  final SeasonStatRow row;
  final bool firstOfSeason;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _SeasonRow({
    required this.row,
    required this.firstOfSeason,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTot = row.team == 'TOT';
    final numStyle = Txt.numeralS.copyWith(
      fontSize: 15,
      color: selected ? Hue.textHi : Hue.textMid,
    );
    return Material(
      color: selected ? Hue.raised : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (firstOfSeason)
                          Text(
                            row.season,
                            style: Txt.numeralS.copyWith(
                              fontSize: 15,
                              color: selected ? Hue.volt : Hue.textHi,
                            ),
                          ),
                        Text(
                          isTot ? 'TOT · all teams' : row.team,
                          style: Txt.caption.copyWith(
                            fontSize: 12,
                            color: isTot ? Hue.textHi : Hue.textLo,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Col(child: Text(_num(row.pts), style: numStyle)),
                  _Col(child: Text(_num(row.reb), style: numStyle)),
                  _Col(child: Text(_num(row.ast), style: numStyle)),
                ],
              ),
              AnimatedSize(
                duration: MediaQuery.of(context).disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 4),
                        child: _FullLine(row: row),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullLine extends StatelessWidget {
  final SeasonStatRow row;
  const _FullLine({required this.row});

  @override
  Widget build(BuildContext context) {
    final cells = <(String, String)>[
      ('GP', row.gp?.toString() ?? '—'),
      ('MIN', _num(row.min)),
      ('STL', _num(row.stl)),
      ('BLK', _num(row.blk)),
      ('TOV', _num(row.tov)),
      ('FG%', _pct(row.fgPct)),
      ('3P%', _pct(row.fg3Pct)),
      ('FT%', _pct(row.ftPct)),
    ];
    return Wrap(
      spacing: 0,
      runSpacing: 12,
      children: [
        for (final (k, v) in cells)
          SizedBox(
            width: 70,
            child: Figure(
              value: v,
              label: k,
              style: Txt.numeralS.copyWith(
                fontSize: 16,
                color: v == '—' ? Hue.textLo : Hue.textHi,
              ),
              labelColor: Hue.textLo,
            ),
          ),
      ],
    );
  }
}
