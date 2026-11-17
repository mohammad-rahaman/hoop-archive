import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/offline_banner.dart';
import '../../core/widgets/player_avatar.dart';
import '../../core/widgets/ui.dart';
import 'players_controller.dart';

final _count = NumberFormat.decimalPattern('en_US');

class PlayersScreen extends ConsumerStatefulWidget {
  const PlayersScreen({super.key});

  @override
  ConsumerState<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends ConsumerState<PlayersScreen> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
      ref.read(playersControllerProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(playersControllerProvider.notifier).setQuery(value.trim());
    });
  }

  void _clearAll() {
    _debounce?.cancel();
    _searchCtrl.clear();
    ref.read(playersControllerProvider.notifier).clearFilters();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playersControllerProvider);
    final controller = ref.read(playersControllerProvider.notifier);
    final filters =
        ref.watch(filterOptionsProvider).valueOrNull ?? FilterOptions.empty;

    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Players'),
            backgroundColor: Hue.ground,
            border: null,
            transitionBetweenRoutes: false,
            // Clear lives in the bar so it never scrolls off with the pills.
            trailing: state.hasActiveFilters
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    onPressed: _clearAll,
                    child: const Text('Clear'),
                  )
                : null,
          ),
          CupertinoSliverRefreshControl(onRefresh: controller.refresh),
          const SliverToBoxAdapter(child: OfflineBanner()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CupertinoSearchTextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    onSuffixTap: () {
                      _searchCtrl.clear();
                      _debounce?.cancel();
                      controller.setQuery('');
                    },
                    placeholder: 'Search players',
                    backgroundColor: Hue.panel,
                    itemColor: Hue.textMid,
                    style: Txt.body.copyWith(fontSize: 17),
                    placeholderStyle: Txt.body.copyWith(
                      fontSize: 17,
                      color: Hue.textLo,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
                  ),
                  const SizedBox(height: 6),
                  // Scrolls sideways so three active filters never overflow.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        _FilterPill(
                          label: 'Season',
                          value: state.season,
                          options: filters.seasons,
                          onChanged: controller.setSeason,
                        ),
                        const SizedBox(width: 8),
                        _FilterPill(
                          label: 'Team',
                          value: state.team,
                          options: filters.teams,
                          onChanged: controller.setTeam,
                        ),
                        const SizedBox(width: 8),
                        _FilterPill(
                          label: 'Position',
                          value: state.position,
                          options: filters.positions,
                          onChanged: controller.setPosition,
                        ),
                      ],
                    ),
                  ),
                  if (state.fromCache && state.cachedAt != null) ...[
                    const SizedBox(height: 8),
                    CachedCopyNote(cachedAt: state.cachedAt!),
                  ],
                ],
              ),
            ),
          ),
          ..._body(state, controller),
        ],
      ),
    );
  }

  List<Widget> _body(PlayersState state, PlayersController controller) {
    if (state.loading && state.items.isEmpty) {
      return const [SliverToBoxAdapter(child: Loading())];
    }
    if (state.error != null && state.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MessageState(
            icon: CupertinoIcons.wifi_slash,
            title: "Couldn't load players",
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: controller.refresh,
          ),
        ),
      ];
    }
    if (state.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: MessageState(
            icon: CupertinoIcons.search,
            title: 'No players match',
            message: 'Try a different name or clear your filters.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.only(top: 6),
        sliver: SliverList.separated(
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const Divider(indent: 78),
          itemBuilder: (context, i) =>
              _PlayerRow(player: state.items[i], season: state.season),
        ),
      ),
      SliverToBoxAdapter(child: _Footer(state: state)),
    ];
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _FilterPill({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<_Choice>(
      context: context,
      // Sheets cover the tab bar, as on iOS.
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) =>
          _OptionSheet(title: label, options: options, selected: value),
    );
    if (picked != null) onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final active = value != null;
    return StatusPill(
      active ? '$label · $value' : label,
      icon: CupertinoIcons.chevron_down,
      active: active,
      onTap: options.isEmpty ? null : () => _open(context),
    );
  }
}

/// Wraps a sheet result so "All" (null) is distinguishable from a dismissal.
class _Choice {
  final String? value;
  const _Choice(this.value);
}

class _OptionSheet extends StatelessWidget {
  final String title;
  final List<String> options;
  final String? selected;
  const _OptionSheet({
    required this.title,
    required this.options,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final entries = <String?>[null, ...options];
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.62,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: Txt.title.copyWith(fontSize: 22)),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(indent: 20),
              itemBuilder: (context, i) {
                final v = entries[i];
                final isSel = v == selected;
                return InkWell(
                  onTap: () => Navigator.of(context).pop(_Choice(v)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            v ?? 'All ${title.toLowerCase()}s',
                            style: Txt.body.copyWith(
                              fontSize: 17,
                              color: isSel ? Hue.volt : Hue.textHi,
                              fontWeight: isSel
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (isSel)
                          const Icon(
                            CupertinoIcons.checkmark_alt,
                            size: 20,
                            color: Hue.volt,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final PlayerListItem player;

  /// The active season filter: the profile opens on that season.
  final String? season;
  const _PlayerRow({required this.player, this.season});

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (player.position != null) player.position!,
      if (player.latestTeam != null) player.latestTeam!,
      player.careerSpan,
    ].join(' · ');
    return InkWell(
      onTap: () => context.push(
        season == null
            ? '/players/${player.id}'
            : '/players/${player.id}?season=$season',
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 18, 12),
        child: Row(
          children: [
            PlayerAvatar(
              imageUrl: player.imageUrl,
              initials: player.initials,
              radius: 23,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.headline,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Txt.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${player.seasonCount}',
                  style: Txt.numeralM.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 2),
                Text(
                  player.seasonCount == 1 ? 'season' : 'seasons',
                  style: Txt.caption.copyWith(color: Hue.textLo, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final PlayersState state;
  const _Footer({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.loadingMore) return const Loading(padding: 20);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
      child: Center(
        child: Text(
          '${_count.format(state.total)} player${state.total == 1 ? '' : 's'}',
          style: Txt.caption.copyWith(color: Hue.textLo),
        ),
      ),
    );
  }
}
