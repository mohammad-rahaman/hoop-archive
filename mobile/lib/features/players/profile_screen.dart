import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/widgets/offline_banner.dart';
import 'widgets/trend_charts.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final int playerId;
  const ProfileScreen({super.key, required this.playerId});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _showPlayoffs = false;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(playerDetailProvider(widget.playerId));
    final outcome = ref
        .watch(apiClientProvider)
        .cache
        ?.outcomeFor(ApiClient.playerKey(widget.playerId));
    final cachedAt = (outcome?.fromCache ?? false) ? outcome!.cachedAt : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(detail.valueOrNull?.fullName ?? 'Player'),
        actions: [
          if (detail.hasValue)
            IconButton(
              tooltip: 'Compare with…',
              onPressed: () => context.push('/compare?a=${widget.playerId}'),
              icon: const Icon(Icons.compare_arrows_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: detail.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ProfileError(
                notFound: e is DioException && e.response?.statusCode == 404,
                onRetry: () =>
                    ref.invalidate(playerDetailProvider(widget.playerId)),
              ),
              data: (d) => _ProfileBody(
                detail: d,
                showPlayoffs: _showPlayoffs,
                onToggle: (v) => setState(() => _showPlayoffs = v),
                cachedAt: cachedAt,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  final PlayerDetail detail;
  final bool showPlayoffs;
  final ValueChanged<bool> onToggle;
  final DateTime? cachedAt;
  const _ProfileBody({
    required this.detail,
    required this.showPlayoffs,
    required this.onToggle,
    this.cachedAt,
  });

  @override
  Widget build(BuildContext context) {
    final rows = detail.seasons
        .where((s) => s.isPlayoff == showPlayoffs)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (cachedAt != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: CachedCopyNote(cachedAt: cachedAt!),
          ),
          const SizedBox(height: 14),
        ],
        _Header(detail: detail),
        const SizedBox(height: 18),
        if (detail.hasPlayoffs)
          Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Regular')),
                ButtonSegment(value: true, label: Text('Playoffs')),
              ],
              selected: {showPlayoffs},
              onSelectionChanged: (s) => onToggle(s.first),
            ),
          ),
        if (detail.hasPlayoffs) const SizedBox(height: 16),
        if (_hasTrend(rows)) ...[
          PerformanceTrends(rows: rows),
          const SizedBox(height: 22),
        ],
        _SeasonTable(rows: rows),
        const SizedBox(height: 10),
        if (rows.isNotEmpty)
          Text(
            rows.first.statMode == 'per_game'
                ? 'Values are per-game averages. "—" means the stat is not recorded for that season.'
                : 'Values are season totals. "—" means the stat is not recorded for that season.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final PlayerDetail detail;
  const _Header({required this.detail});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final chips = <String>[
      if (detail.position != null) detail.position!,
      if (detail.jerseyNumber != null) '#${detail.jerseyNumber}',
      ...detail.teams,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: t.colorScheme.primary.withValues(alpha: 0.15),
          child: Text(
            detail.initials,
            style: t.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: t.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.fullName,
                style: t.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${detail.careerSpan} · ${detail.seasonCount} season${detail.seasonCount == 1 ? '' : 's'}',
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final c in chips) _Pill(text: c)],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Trends need at least two distinct seasons in the current split. A single
/// season is shown only in the table.
bool _hasTrend(List<SeasonStatRow> rows) =>
    rows.map((r) => r.season).toSet().length >= 2;

String _num(double? v) => v == null ? '—' : v.toStringAsFixed(1);
String _pct(double? v) => v == null ? '—' : (v * 100).toStringAsFixed(1);
String _int(int? v) => v == null ? '—' : v.toString();

class _SeasonTable extends StatelessWidget {
  final List<SeasonStatRow> rows;
  const _SeasonTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(
            'No stats for this split.',
            style: t.textTheme.bodyMedium?.copyWith(
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    const cols = [
      'Season',
      'Team',
      'GP',
      'MIN',
      'PTS',
      'REB',
      'AST',
      'STL',
      'BLK',
      'TOV',
      'FG%',
      '3P%',
      'FT%',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 42,
        dataRowMaxHeight: 48,
        columnSpacing: 22,
        headingTextStyle: t.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        columns: [for (final c in cols) DataColumn(label: Text(c))],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    r.season,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DataCell(
                  Text(
                    r.team,
                    style: TextStyle(
                      fontWeight: r.team == 'TOT'
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: r.team == 'TOT' ? t.colorScheme.primary : null,
                    ),
                  ),
                ),
                DataCell(Text(_int(r.gp))),
                DataCell(Text(_num(r.min))),
                DataCell(Text(_num(r.pts))),
                DataCell(Text(_num(r.reb))),
                DataCell(Text(_num(r.ast))),
                DataCell(Text(_num(r.stl))),
                DataCell(Text(_num(r.blk))),
                DataCell(Text(_num(r.tov))),
                DataCell(Text(_pct(r.fgPct))),
                DataCell(Text(_pct(r.fg3Pct))),
                DataCell(Text(_pct(r.ftPct))),
              ],
            ),
        ],
      ),
    );
  }
}

class _ProfileError extends StatelessWidget {
  final bool notFound;
  final VoidCallback onRetry;
  const _ProfileError({required this.notFound, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              notFound ? Icons.person_off_rounded : Icons.wifi_off_rounded,
              size: 44,
              color: t.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              notFound ? 'Player not found' : "Couldn't load this player",
              style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!notFound) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
