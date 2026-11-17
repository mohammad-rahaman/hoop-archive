import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/offline_banner.dart';
import '../../core/widgets/ui.dart';

final _count = NumberFormat.decimalPattern('en_US');

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = ref.watch(metaProvider);
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('Hoop Archive'),
            backgroundColor: Hue.ground,
            border: null,
            transitionBetweenRoutes: false,
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () => ref.refresh(metaProvider.future),
          ),
          const SliverToBoxAdapter(child: OfflineBanner()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList.list(
              children: [
                meta.when(
                  loading: () => const Panel(child: Loading(padding: 72)),
                  error: (_, _) => Panel(
                    child: MessageState(
                      icon: CupertinoIcons.wifi_slash,
                      title: "Can't reach the server",
                      message:
                          'Start the backend (uvicorn app.main:app) and make '
                          'sure the API URL is reachable from this device.',
                      actionLabel: 'Retry',
                      onAction: () => ref.invalidate(metaProvider),
                    ),
                  ),
                  data: (m) => _Overview(meta: m),
                ),
                const SizedBox(height: 14),
                _EntryRows(playerCount: meta.valueOrNull?.players),
                const SizedBox(height: 32),
                if (meta.valueOrNull != null) _Sources(meta: meta.value!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  final MetaInfo meta;
  const _Overview({required this.meta});

  @override
  Widget build(BuildContext context) {
    final range = meta.seasonYearRange;
    final hasRange = range != null && range.length == 2;
    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Reads as a phrase: "3,275 players".
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_count.format(meta.players), style: Txt.numeralXL),
                const SizedBox(width: 10),
                Text(
                  'players',
                  style: Txt.title.copyWith(
                    color: Hue.textMid,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (hasRange) ...[
            const SizedBox(height: 26),
            _SeasonRuler(first: range[0], last: range[1]),
          ],
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Figure(
                value: _count.format(meta.seasons),
                label: 'seasons',
                tracked: false,
              ),
              Figure(
                value: _count.format(meta.playerSeasonStats),
                label: 'stat lines',
                tracked: false,
              ),
              Figure(
                value: _count.format(meta.teams),
                label: 'teams',
                tracked: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One tick per season in the archive, decades marked taller: the span of
/// the data, drawn at its true length.
class _SeasonRuler extends StatelessWidget {
  final int first;
  final int last;
  const _SeasonRuler({required this.first, required this.last});

  @override
  Widget build(BuildContext context) {
    final n = last - first + 1;
    return Semantics(
      label: '$n seasons, $first to ${last + 1}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 18,
              child: CustomPaint(
                painter: _RulerPainter(first: first, count: n),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$first', style: Txt.caption.copyWith(fontSize: 12)),
                Text('${last + 1}', style: Txt.caption.copyWith(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final int first;
  final int count;
  _RulerPainter({required this.first, required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    if (count < 1) return;
    final minor = Paint()
      ..color = Hue.line
      ..strokeWidth = 1;
    final major = Paint()
      ..color = Hue.textHi
      ..strokeWidth = 1.5;
    final edge = Paint()
      ..color = Hue.volt
      ..strokeWidth = 2;
    final step = count == 1 ? 0.0 : (size.width - 2) / (count - 1);
    for (var i = 0; i < count; i++) {
      final x = 1 + step * i;
      final year = first + i;
      final isEdge = i == 0 || i == count - 1;
      final isDecade = year % 10 == 0;
      final h = isEdge
          ? size.height
          : isDecade
          ? size.height * 0.72
          : size.height * 0.4;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - h),
        isEdge ? edge : (isDecade ? major : minor),
      );
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.first != first || old.count != count;
}

class _EntryRows extends StatelessWidget {
  final int? playerCount;
  const _EntryRows({required this.playerCount});

  @override
  Widget build(BuildContext context) {
    final search = playerCount == null
        ? 'Search players'
        : 'Search ${_count.format(playerCount)} players';
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _EntryRow(
            icon: CupertinoIcons.search,
            title: search,
            subtitle: 'By name, team, or position',
            onTap: () => context.go('/players'),
          ),
          const Divider(indent: 64),
          _EntryRow(
            icon: CupertinoIcons.arrow_right_arrow_left,
            title: 'Compare two players',
            subtitle: 'Career lines, metric by metric',
            onTap: () => context.go('/compare'),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _EntryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            SizedBox(width: 30, child: Icon(icon, size: 21, color: Hue.textHi)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Txt.headline),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Txt.caption),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: Hue.textLo,
            ),
          ],
        ),
      ),
    );
  }
}

class _Sources extends StatelessWidget {
  final MetaInfo meta;
  const _Sources({required this.meta});

  @override
  Widget build(BuildContext context) {
    final sync = meta.lastSync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading('Data sources'),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SourceRow(
                live: sync != null,
                title: sync?.providerLabel ?? 'No data yet',
                detail:
                    sync?.updatedLabel ??
                    (sync == null ? 'Run an ingest' : '—'),
              ),
              const Divider(indent: 44),
              _SourceRow(
                live: meta.sportradarConfigured,
                title: 'Current season',
                detail: meta.sportradarConfigured
                    ? 'Sportradar'
                    : 'Not configured',
              ),
            ],
          ),
        ),
        if (!meta.sportradarConfigured) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Showing historical data. Add a Sportradar key on the backend '
              'to enable current-season sync.',
              style: Txt.caption.copyWith(color: Hue.textLo),
            ),
          ),
        ],
      ],
    );
  }
}

/// A source line. Live sources get a filled volt dot, inactive ones a hollow
/// ring, and the detail text says the same thing in words.
class _SourceRow extends StatelessWidget {
  final bool live;
  final String title;
  final String detail;
  const _SourceRow({
    required this.live,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live ? Hue.volt : null,
              border: live ? null : Border.all(color: Hue.textLo, width: 1.5),
            ),
          ),
          const SizedBox(width: 17),
          Expanded(child: Text(title, style: Txt.body)),
          Text(detail, style: Txt.caption),
        ],
      ),
    );
  }
}
