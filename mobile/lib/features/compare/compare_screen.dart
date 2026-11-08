import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import 'player_picker_sheet.dart';

/// A player chosen for a comparison slot. Built from a search result or, on a
/// deep link, from a fetched player detail.
class PickedPlayer {
  final int id;
  final String fullName;
  final String? position;
  const PickedPlayer({required this.id, required this.fullName, this.position});

  String get initials {
    final parts =
        fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class CompareScreen extends ConsumerStatefulWidget {
  final int? initialAId;
  final int? initialBId;
  const CompareScreen({super.key, this.initialAId, this.initialBId});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  PickedPlayer? _a;
  PickedPlayer? _b;
  String _split = 'regular';

  @override
  void initState() {
    super.initState();
    if (widget.initialAId != null) _preset(widget.initialAId!, isA: true);
    if (widget.initialBId != null) _preset(widget.initialBId!, isA: false);
  }

  Future<void> _preset(int id, {required bool isA}) async {
    try {
      final d = await ref.read(apiClientProvider).fetchPlayerDetail(id);
      if (!mounted) return;
      final picked =
          PickedPlayer(id: d.id, fullName: d.fullName, position: d.position);
      setState(() => isA ? _a = picked : _b = picked);
    } catch (_) {
      // Silently ignore a bad preset id; the slot stays empty for the user.
    }
  }

  Future<void> _pick({required bool isA}) async {
    final other = isA ? _b : _a;
    final result = await PlayerPickerSheet.show(
      context,
      excludeId: other?.id,
      title: isA ? 'Pick first player' : 'Pick second player',
    );
    if (result == null) return;
    final picked = PickedPlayer(
      id: result.id,
      fullName: result.fullName,
      position: result.position,
    );
    setState(() => isA ? _a = picked : _b = picked);
  }

  void _swap() {
    setState(() {
      final tmp = _a;
      _a = _b;
      _b = tmp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final b = _b;
    final ready = a != null && b != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare'),
        actions: [
          if (_a != null || _b != null)
            IconButton(
              tooltip: 'Swap sides',
              onPressed: _swap,
              icon: const Icon(Icons.swap_horiz_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: _SlotCard(
                  player: a,
                  accent: Theme.of(context).colorScheme.primary,
                  onTap: () => _pick(isA: true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Center(child: _VsBadge()),
              ),
              Expanded(
                child: _SlotCard(
                  player: b,
                  accent: const Color(0xFFE08A2B),
                  onTap: () => _pick(isA: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (!ready)
            const _CompareHint()
          else ...[
            Center(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'regular', label: Text('Regular')),
                  ButtonSegment(value: 'playoff', label: Text('Playoffs')),
                ],
                selected: {_split},
                onSelectionChanged: (s) => setState(() => _split = s.first),
              ),
            ),
            const SizedBox(height: 18),
            _Result(args: CompareArgs(a.id, b.id, _split)),
          ],
        ],
      ),
    );
  }
}

class _VsBadge extends StatelessWidget {
  const _VsBadge();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Text('vs',
        style: t.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: t.colorScheme.onSurfaceVariant,
        ));
  }
}

class _SlotCard extends StatelessWidget {
  final PickedPlayer? player;
  final Color accent;
  final VoidCallback onTap;
  const _SlotCard(
      {required this.player, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = player;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: p == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline_rounded, color: accent, size: 30),
                  const SizedBox(height: 8),
                  Text('Add player',
                      style: t.textTheme.labelLarge
                          ?.copyWith(color: accent, fontWeight: FontWeight.w700)),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: accent.withValues(alpha: 0.18),
                    child: Text(p.initials,
                        style: t.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900, color: accent)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    p.fullName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (p.position != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(p.position!,
                          style: t.textTheme.labelSmall?.copyWith(
                              color: t.colorScheme.onSurfaceVariant)),
                    ),
                  const SizedBox(height: 4),
                  Text('Tap to change',
                      style: t.textTheme.labelSmall?.copyWith(
                          color: t.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8))),
                ],
              ),
      ),
    );
  }
}

class _CompareHint extends StatelessWidget {
  const _CompareHint();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Icon(Icons.compare_arrows_rounded,
              size: 46, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('Pick two players to compare',
              style:
                  t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Career averages are compared metric by metric. Regular season and '
            'playoffs are kept separate.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodySmall
                ?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Result extends ConsumerWidget {
  final CompareArgs args;
  const _Result({required this.args});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(comparisonProvider(args));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) {
        final notFound =
            e is DioException && e.response?.statusCode == 404;
        return _ResultError(
          message: notFound
              ? 'One of these players could no longer be found.'
              : "Couldn't load the comparison.",
          onRetry: () => ref.invalidate(comparisonProvider(args)),
        );
      },
      data: (c) => _ComparisonView(comparison: c),
    );
  }
}

class _ResultError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ResultError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 40, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

const _accentB = Color(0xFFE08A2B);

class _ComparisonView extends StatelessWidget {
  final PlayerComparison comparison;
  const _ComparisonView({required this.comparison});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final accentA = cs.primary;
    final available = comparison.metrics.where((m) => m.available).toList();
    final unavailable = comparison.metrics.where((m) => !m.available).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TallyBanner(comparison: comparison, accentA: accentA, accentB: _accentB),
        const SizedBox(height: 16),
        if (available.isEmpty)
          _NoOverlapNote(seasonType: comparison.seasonType)
        else
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < available.length; i++)
                  _MetricRow(
                    metric: available[i],
                    accentA: accentA,
                    accentB: _accentB,
                    first: i == 0,
                  ),
              ],
            ),
          ),
        if (unavailable.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Not compared (missing for one or both): '
            '${unavailable.map((m) => m.label).join(', ')}.',
            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Career ${comparison.seasonType == 'playoff' ? 'playoff' : 'regular-season'} '
          'averages, games-played weighted. Missing stats are never counted as zero.',
          style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _TallyBanner extends StatelessWidget {
  final PlayerComparison comparison;
  final Color accentA;
  final Color accentB;
  const _TallyBanner(
      {required this.comparison,
      required this.accentA,
      required this.accentB});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = comparison;
    final String headline;
    final Color color;
    if (c.comparedCount == 0) {
      headline = 'No shared metrics to compare';
      color = t.colorScheme.onSurfaceVariant;
    } else if (c.aWins > c.bWins) {
      headline = '${c.a.fullName} leads ${c.aWins}–${c.bWins}';
      color = accentA;
    } else if (c.bWins > c.aWins) {
      headline = '${c.b.fullName} leads ${c.bWins}–${c.aWins}';
      color = accentB;
    } else {
      headline = 'Even at ${c.aWins}–${c.bWins}';
      color = t.colorScheme.onSurface;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(headline,
              textAlign: TextAlign.center,
              style: t.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: color)),
          if (c.ties > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('${c.ties} tied',
                  style: t.textTheme.labelSmall
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final MetricComparisonRow metric;
  final Color accentA;
  final Color accentB;
  final bool first;
  const _MetricRow({
    required this.metric,
    required this.accentA,
    required this.accentB,
    required this.first,
  });

  String _withUnit(String display) =>
      metric.percent ? '$display%' : display;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final aLeads = metric.leader == 'a';
    final bLeads = metric.leader == 'b';

    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _ValueCell(
              text: _withUnit(metric.aDisplay),
              leads: aLeads,
              accent: accentA,
              alignEnd: true,
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              metric.label,
              textAlign: TextAlign.center,
              style: t.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: _ValueCell(
              text: _withUnit(metric.bDisplay),
              leads: bLeads,
              accent: accentB,
              alignEnd: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  final String text;
  final bool leads;
  final Color accent;
  final bool alignEnd;
  const _ValueCell({
    required this.text,
    required this.leads,
    required this.accent,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final style = t.textTheme.titleSmall?.copyWith(
      fontWeight: leads ? FontWeight.w900 : FontWeight.w500,
      color: leads ? accent : t.colorScheme.onSurface,
    );
    final child = Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leads && alignEnd) ...[
          Icon(Icons.arrow_drop_up_rounded, color: accent, size: 20),
          const SizedBox(width: 2),
        ],
        Flexible(child: Text(text, style: style)),
        if (leads && !alignEnd) ...[
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_up_rounded, color: accent, size: 20),
        ],
      ],
    );
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
  }
}

class _NoOverlapNote extends StatelessWidget {
  final String seasonType;
  const _NoOverlapNote({required this.seasonType});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Icons.info_outline_rounded,
              color: t.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            seasonType == 'playoff'
                ? 'No overlapping playoff stats to compare. One of these players '
                    'may have no playoff record.'
                : 'No overlapping stats available to compare for this split.',
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium
                ?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
