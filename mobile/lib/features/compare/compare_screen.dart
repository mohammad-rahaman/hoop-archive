import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/offline_banner.dart';
import '../../core/widgets/player_avatar.dart';
import '../../core/widgets/ui.dart';
import '../players/career.dart';
import 'player_picker_sheet.dart';

/// A player chosen for a comparison slot, plus which line of theirs to use:
/// the career ([season] null) or one season (e.g. "2015-16").
class PickedPlayer {
  final int id;
  final String fullName;
  final String? position;
  final String? imageUrl;
  final String? season;
  final String? seasonTeam;

  const PickedPlayer({
    required this.id,
    required this.fullName,
    this.position,
    this.imageUrl,
    this.season,
    this.seasonTeam,
  });

  PickedPlayer withSeason(String? season, String? team) => PickedPlayer(
    id: id,
    fullName: fullName,
    position: position,
    imageUrl: imageUrl,
    season: season,
    seasonTeam: season == null ? null : team,
  );

  String get lineLabel => season == null
      ? 'Career'
      : (seasonTeam == null ? season! : '$season · $seasonTeam');

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class CompareScreen extends ConsumerStatefulWidget {
  final int? initialAId;
  final int? initialBId;

  /// Optional season per side from a deep link, e.g. "2015-16".
  final String? initialASeason;
  final String? initialBSeason;

  const CompareScreen({
    super.key,
    this.initialAId,
    this.initialBId,
    this.initialASeason,
    this.initialBSeason,
  });

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  PickedPlayer? _a;
  PickedPlayer? _b;
  bool _playoffs = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAId != null) {
      _preset(widget.initialAId!, isA: true, season: widget.initialASeason);
    }
    if (widget.initialBId != null) {
      _preset(widget.initialBId!, isA: false, season: widget.initialBSeason);
    }
  }

  @override
  void didUpdateWidget(CompareScreen old) {
    super.didUpdateWidget(old);
    // The tab stays alive, so a later deep link (e.g. "Compare with…" from a
    // profile) arrives as new widget arguments rather than a fresh screen.
    final a = widget.initialAId;
    final b = widget.initialBId;
    if (a != null &&
        (a != old.initialAId || widget.initialASeason != old.initialASeason)) {
      _preset(a, isA: true, season: widget.initialASeason);
    }
    if (b != null &&
        (b != old.initialBId || widget.initialBSeason != old.initialBSeason)) {
      _preset(b, isA: false, season: widget.initialBSeason);
    }
  }

  Future<void> _preset(int id, {required bool isA, String? season}) async {
    try {
      final d = await ref.read(playerDetailProvider(id).future);
      if (!mounted) return;
      final played = season != null && d.seasons.any((s) => s.season == season);
      final picked = PickedPlayer(
        id: d.id,
        fullName: d.fullName,
        position: d.position,
        imageUrl: d.imageUrl,
        season: played ? season : null,
        seasonTeam: played ? _teamFor(d, season) : null,
      );
      setState(() => isA ? _a = picked : _b = picked);
    } catch (_) {
      // A bad preset id leaves the slot empty for the user to fill.
    }
  }

  Future<void> _pickPlayer({required bool isA}) async {
    final result = await PlayerPickerSheet.show(
      context,
      title: isA ? 'First player' : 'Second player',
    );
    if (result == null || !mounted) return;
    final picked = PickedPlayer(
      id: result.id,
      fullName: result.fullName,
      position: result.position,
      imageUrl: result.imageUrl,
    );
    setState(() => isA ? _a = picked : _b = picked);
    // Comparing seasons? Then this side needs a season too: ask right away.
    final other = isA ? _b : _a;
    if (other?.season != null) await _pickSeason(isA: isA);
  }

  Future<void> _pickSeason({required bool isA}) async {
    final p = isA ? _a : _b;
    if (p == null) return;
    final choice = await SeasonSheet.show(
      context,
      playerId: p.id,
      playerName: p.fullName,
      selected: p.season,
    );
    if (choice == null || !mounted) return;
    setState(() {
      final updated = p.withSeason(choice.season, choice.team);
      if (isA) {
        _a = updated;
      } else {
        _b = updated;
      }
    });
  }

  void _swap() => setState(() {
    final tmp = _a;
    _a = _b;
    _b = tmp;
  });

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final b = _b;
    final ready = a != null && b != null;
    final sameLine = ready && a.id == b.id && a.season == b.season;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('Compare'),
            backgroundColor: Hue.ground,
            border: null,
            transitionBetweenRoutes: false,
          ),
          const SliverToBoxAdapter(child: OfflineBanner()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            sliver: SliverList.list(
              children: [
                SizedBox(
                  height: 214,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Slot(
                          player: a,
                          onPickPlayer: () => _pickPlayer(isA: true),
                          onPickSeason: () => _pickSeason(isA: true),
                        ),
                      ),
                      _SwapButton(
                        onPressed: (a != null || b != null) ? _swap : null,
                      ),
                      Expanded(
                        child: _Slot(
                          player: b,
                          onPickPlayer: () => _pickPlayer(isA: false),
                          onPickSeason: () => _pickSeason(isA: false),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (!ready)
                  const _CompareHint()
                else if (sameLine)
                  const Panel(
                    child: Text(
                      'Same line on both sides. Pick a different season for '
                      'one of them to compare a player with their own past.',
                      style: Txt.body,
                    ),
                  )
                else ...[
                  SplitControl(
                    playoffs: _playoffs,
                    onChanged: (v) => setState(() => _playoffs = v),
                  ),
                  const SizedBox(height: 14),
                  _Result(
                    args: CompareArgs(
                      a.id,
                      b.id,
                      _playoffs ? 'playoff' : 'regular',
                      aSeason: a.season,
                      bSeason: b.season,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Team for one season: "TOT" when the player was traded mid-season.
String? _teamFor(PlayerDetail d, String season) {
  final teams = d.seasons
      .where((s) => s.season == season)
      .map((s) => s.team)
      .toSet();
  if (teams.isEmpty) return null;
  return teams.contains('TOT') ? 'TOT' : teams.first;
}

class _SwapButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _SwapButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: 'Swap sides',
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 44,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Hue.ground,
              shape: BoxShape.circle,
              border: Border.all(color: Hue.hairlineStrong),
            ),
            child: Icon(
              CupertinoIcons.arrow_right_arrow_left,
              size: 18,
              color: onPressed == null ? Hue.textLo : Hue.textHi,
            ),
          ),
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  final PickedPlayer? player;
  final VoidCallback onPickPlayer;
  final VoidCallback onPickSeason;
  const _Slot({
    required this.player,
    required this.onPickPlayer,
    required this.onPickSeason,
  });

  @override
  Widget build(BuildContext context) {
    final p = player;
    if (p == null) {
      return Panel(
        onTap: onPickPlayer,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Hue.hairlineStrong),
              ),
              child: const Icon(CupertinoIcons.add, size: 22, color: Hue.volt),
            ),
            const SizedBox(height: 12),
            Text('Add player', style: Txt.headline.copyWith(fontSize: 15)),
          ],
        ),
      );
    }
    return Panel(
      onTap: onPickPlayer,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      semanticLabel: '${p.fullName}, ${p.lineLabel}. Tap to change player',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PlayerAvatar(imageUrl: p.imageUrl, initials: p.initials, radius: 26),
          const SizedBox(height: 9),
          Text(
            p.fullName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Txt.headline.copyWith(fontSize: 15, height: 1.2),
          ),
          // Position, plus the team for the chosen season ("TOT" if traded).
          if (p.position != null || p.seasonTeam != null) ...[
            const SizedBox(height: 2),
            Text(
              [?p.position, ?p.seasonTeam].join(' · '),
              style: Txt.caption.copyWith(fontSize: 12),
            ),
          ],
          const Spacer(),
          // Which line of this player is compared: career or one season.
          Semantics(
            button: true,
            label: 'Line: ${p.lineLabel}. Change season',
            excludeSemantics: true,
            child: StatusPill(
              p.season ?? 'Career',
              icon: CupertinoIcons.calendar,
              active: p.season != null,
              onTap: onPickSeason,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareHint extends StatelessWidget {
  const _CompareHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 22, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick two players to compare',
            style: Txt.title.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 8),
          Text(
            'Compare whole careers, or tap a player\'s line to pick one season '
            'each, like one MVP year against another. Regular season and '
            'playoffs stay separate, and a stat missing for either side is '
            'left out rather than counted as zero.',
            style: Txt.caption.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// A season (or the career) picked for one side.
class SeasonChoice {
  final String? season;
  final String? team;
  const SeasonChoice(this.season, this.team);
}

/// Lists the career plus every season the player actually played, newest
/// first, with that season's team and scoring so the big years stand out.
class SeasonSheet extends ConsumerWidget {
  final int playerId;
  final String playerName;
  final String? selected;
  const SeasonSheet({
    super.key,
    required this.playerId,
    required this.playerName,
    required this.selected,
  });

  static Future<SeasonChoice?> show(
    BuildContext context, {
    required int playerId,
    required String playerName,
    required String? selected,
  }) {
    return showModalBottomSheet<SeasonChoice>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SeasonSheet(
        playerId: playerId,
        playerName: playerName,
        selected: selected,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(playerDetailProvider(playerId));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(playerName, style: Txt.title.copyWith(fontSize: 22)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              'Compare the whole career or one season.',
              style: Txt.caption,
            ),
          ),
          Expanded(
            child: detail.when(
              loading: () => const Loading(),
              error: (_, _) => const MessageState(
                icon: CupertinoIcons.wifi_slash,
                title: "Couldn't load seasons",
                message: 'Check your connection and try again.',
              ),
              data: (d) => _SeasonList(detail: d, selected: selected),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonList extends StatelessWidget {
  final PlayerDetail detail;
  final String? selected;
  const _SeasonList({required this.detail, required this.selected});

  @override
  Widget build(BuildContext context) {
    // One regular-season line per season (TOT for traded seasons), newest
    // first; seasons with only playoff rows still appear.
    final regular = {
      for (final r in seasonLine(
        detail.seasons.where((s) => !s.isPlayoff).toList(),
      ))
        r.season: r,
    };
    final labels = detail.seasons.map((s) => s.season).toSet().toList()
      ..sort((x, y) => y.compareTo(x));

    final rows = <Widget>[
      _SeasonOption(
        title: 'Career',
        detail: '${detail.careerSpan} · ${detail.seasonCount} seasons',
        value: null,
        selected: selected == null,
        onTap: () => Navigator.of(context).pop(const SeasonChoice(null, null)),
      ),
      for (final label in labels)
        _SeasonOption(
          title: label,
          detail: _detailFor(label, regular[label]),
          value: regular[label]?.pts,
          selected: selected == label,
          onTap: () =>
              Navigator.of(context)
                  .pop(SeasonChoice(label, _teamFor(detail, label))),
        ),
    ];
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 28),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(indent: 20),
      itemBuilder: (_, i) => rows[i],
    );
  }

  String _detailFor(String label, SeasonStatRow? r) {
    if (r == null) return '${_teamFor(detail, label) ?? '—'} · playoffs only';
    final team = r.team == 'TOT' ? 'Split across teams' : r.team;
    return r.gp == null ? team : '$team · ${r.gp} games';
  }
}

class _SeasonOption extends StatelessWidget {
  final String title;
  final String detail;
  final double? value;
  final bool selected;
  final VoidCallback onTap;
  const _SeasonOption({
    required this.title,
    required this.detail,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Txt.numeralS.copyWith(
                      color: selected ? Hue.volt : Hue.textHi,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: Txt.caption.copyWith(fontSize: 12.5)),
                ],
              ),
            ),
            if (value != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value!.toStringAsFixed(1),
                    style: Txt.numeralS.copyWith(fontSize: 20),
                  ),
                  const TrackedLabel('PTS', color: Hue.textLo),
                ],
              ),
            if (selected) ...[
              const SizedBox(width: 14),
              const Icon(
                CupertinoIcons.checkmark_alt,
                size: 20,
                color: Hue.volt,
              ),
            ],
          ],
        ),
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
      loading: () => const Loading(),
      error: (e, _) {
        final notFound = e is DioException && e.response?.statusCode == 404;
        return MessageState(
          icon: notFound
              ? CupertinoIcons.person_crop_circle_badge_xmark
              : CupertinoIcons.wifi_slash,
          title: notFound
              ? 'One of these players could no longer be found.'
              : "Couldn't load the comparison.",
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(comparisonProvider(args)),
        );
      },
      data: (c) => _ComparisonView(comparison: c),
    );
  }
}

class _ComparisonView extends StatelessWidget {
  final PlayerComparison comparison;
  const _ComparisonView({required this.comparison});

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final available = c.metrics.where((m) => m.available).toList();
    final unavailable = c.metrics.where((m) => !m.available).toList();
    final split = c.seasonType == 'playoff' ? 'playoff' : 'regular-season';
    final anySeason = c.a.season != null || c.b.season != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Verdict(comparison: c),
        const SizedBox(height: 14),
        if (available.isEmpty)
          Panel(
            child: Text(
              c.seasonType == 'playoff'
                  ? 'No overlapping playoff stats to compare. One of these '
                        'lines may have no playoff record.'
                  : 'No overlapping stats available to compare for this split.',
              style: Txt.body.copyWith(color: Hue.textMid),
            ),
          )
        else
          Panel(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
            child: Column(
              children: [
                for (var i = 0; i < available.length; i++) ...[
                  if (i > 0) const Divider(),
                  _MetricDuel(metric: available[i]),
                ],
              ],
            ),
          ),
        if (unavailable.isNotEmpty) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Not compared, missing for one or both: '
              '${unavailable.map((m) => m.label).join(', ')}.',
              style: Txt.caption,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            anySeason
                ? 'A single season is that season\'s $split per-game line '
                      '(a traded season uses the combined TOT line). A career '
                      'is weighted by games played. Missing stats are never '
                      'counted as zero.'
                : 'Career $split averages, weighted by games played. Missing '
                      'stats are never counted as zero.',
            style: Txt.caption.copyWith(color: Hue.textLo),
          ),
        ),
      ],
    );
  }
}

class _Verdict extends StatelessWidget {
  final PlayerComparison comparison;
  const _Verdict({required this.comparison});

  String _line(ComparisonPlayer p) => p.season ?? 'Career';

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    if (c.comparedCount == 0) {
      return Panel(
        child: Text('No shared metrics to compare', style: Txt.headline),
      );
    }
    final String headline;
    if (c.aWins > c.bWins) {
      headline = '${c.a.fullName} leads ${c.aWins}–${c.bWins}';
    } else if (c.bWins > c.aWins) {
      headline = '${c.b.fullName} leads ${c.bWins}–${c.aWins}';
    } else {
      headline = 'Even at ${c.aWins}–${c.bWins}';
    }
    final anySeason = c.a.season != null || c.b.season != null;
    const ink = Hue.onVolt;
    // A filled volt block, read like a scoreboard: the tally is the answer.
    return Semantics(
      container: true,
      label: '$headline. ${c.comparedCount} metrics compared.',
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        decoration: BoxDecoration(color: Hue.volt, borderRadius: Panel.radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              anySeason
                  ? '${_line(c.a)}  vs  ${_line(c.b)}'
                  : 'Career vs career',
              style: Txt.caption.copyWith(
                color: ink.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '${c.aWins}–${c.bWins}',
                  style: Txt.numeralL.copyWith(color: ink, fontSize: 60),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: Txt.headline.copyWith(
                          color: ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          '${c.comparedCount} metrics',
                          if (c.ties > 0) '${c.ties} tied',
                        ].join(' · '),
                        style: Txt.caption.copyWith(
                          color: ink.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
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

/// One metric, both players: values at the edges, bars growing outward from
/// the centre. The leader's side is volt and bold, so it reads without color.
class _MetricDuel extends StatelessWidget {
  final MetricComparisonRow metric;
  const _MetricDuel({required this.metric});

  String _withUnit(String display) =>
      metric.percent && display != '—' ? '$display%' : display;

  @override
  Widget build(BuildContext context) {
    final aLeads = metric.leader == 'a';
    final bLeads = metric.leader == 'b';
    final a = metric.aValue ?? 0;
    final b = metric.bValue ?? 0;
    final top = a > b ? a : b;
    final fa = top <= 0 || metric.aValue == null ? 0.0 : a / top;
    final fb = top <= 0 || metric.bValue == null ? 0.0 : b / top;

    TextStyle value(bool leads) => Txt.numeralS.copyWith(
      fontSize: 17,
      fontWeight: leads ? FontWeight.w800 : FontWeight.w500,
      color: leads ? Hue.textHi : Hue.textMid,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_withUnit(metric.aDisplay), style: value(aLeads)),
              ),
              Text(
                metric.label,
                style: Txt.caption.copyWith(
                  color: Hue.textMid,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Expanded(
                child: Text(
                  _withUnit(metric.bDisplay),
                  textAlign: TextAlign.right,
                  style: value(bLeads),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _HalfBar(fraction: fa, leads: aLeads, rightToLeft: true),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _HalfBar(
                  fraction: fb,
                  leads: bLeads,
                  rightToLeft: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HalfBar extends StatelessWidget {
  final double fraction;
  final bool leads;
  final bool rightToLeft;
  const _HalfBar({
    required this.fraction,
    required this.leads,
    required this.rightToLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 5,
      decoration: BoxDecoration(
        color: Hue.track,
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: rightToLeft ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: leads ? Hue.volt : Hue.line,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
