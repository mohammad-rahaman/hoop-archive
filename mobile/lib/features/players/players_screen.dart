import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/widgets/offline_banner.dart';
import '../../core/widgets/player_avatar.dart';
import 'players_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playersControllerProvider);
    final controller = ref.read(playersControllerProvider.notifier);
    final filters = ref.watch(filterOptionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Players'),
        actions: [
          IconButton(
            tooltip: 'Compare players',
            onPressed: () => context.push('/compare'),
            icon: const Icon(Icons.compare_arrows_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                _SearchField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  onClear: () {
                    _searchCtrl.clear();
                    controller.setQuery('');
                  },
                ),
                const SizedBox(height: 10),
                _FilterBar(
                  options: filters.valueOrNull ?? FilterOptions.empty,
                  team: state.team,
                  position: state.position,
                  onTeam: controller.setTeam,
                  onPosition: controller.setPosition,
                  onClear: state.hasActiveFilters
                      ? controller.clearFilters
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          if (state.fromCache && state.cachedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: CachedCopyNote(cachedAt: state.cachedAt!),
              ),
            ),
          Expanded(
            child: _Body(
              state: state,
              scroll: _scroll,
              onRetry: controller.refresh,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search players',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        filled: true,
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(icon: const Icon(Icons.close), onPressed: onClear),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final FilterOptions options;
  final String? team;
  final String? position;
  final ValueChanged<String?> onTeam;
  final ValueChanged<String?> onPosition;
  final VoidCallback? onClear;

  const _FilterBar({
    required this.options,
    required this.team,
    required this.position,
    required this.onTeam,
    required this.onPosition,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: _FilterDropdown(
              icon: Icons.groups_rounded,
              label: 'Team',
              value: team,
              options: options.teams,
              onChanged: onTeam,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FilterDropdown(
              icon: Icons.sports_basketball_rounded,
              label: 'Position',
              value: position,
              options: options.positions,
              onChanged: onPosition,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Clear filters',
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          hint: Row(
            children: [
              Icon(icon, size: 16, color: t.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label, style: t.textTheme.labelLarge),
            ],
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('All ${label.toLowerCase()}s'),
            ),
            ...options.map(
              (o) => DropdownMenuItem<String?>(value: o, child: Text(o)),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final PlayersState state;
  final ScrollController scroll;
  final Future<void> Function() onRetry;
  const _Body({
    required this.state,
    required this.scroll,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return _ErrorState(onRetry: onRetry);
    }
    if (state.isEmpty) {
      return const _EmptyState();
    }
    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView.separated(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: state.items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == state.items.length) {
            return _Footer(state: state);
          }
          return _PlayerCard(player: state.items[i]);
        },
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final PlayersState state;
  const _Footer({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        child: Text(
          '${state.total} player${state.total == 1 ? '' : 's'}',
          style: t.textTheme.labelMedium?.copyWith(
            color: t.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final PlayerListItem player;
  const _PlayerCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/players/${player.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              PlayerAvatar(
                imageUrl: player.imageUrl,
                initials: player.initials,
                radius: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.fullName,
                      style: t.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (player.position != null)
                          _Pill(text: player.position!),
                        if (player.latestTeam != null)
                          _Pill(text: player.latestTeam!, subtle: true),
                        Text(
                          '${player.careerSpan} · ${player.seasonCount} season${player.seasonCount == 1 ? '' : 's'}',
                          style: t.textTheme.bodySmall?.copyWith(
                            color: t.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: t.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool subtle;
  const _Pill({required this.text, this.subtle = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bg = subtle
        ? t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7)
        : t.colorScheme.primary.withValues(alpha: 0.14);
    final fg = subtle ? t.colorScheme.onSurfaceVariant : t.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: t.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 44,
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No players match',
                    style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Try a different name or clear your filters.',
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _ErrorState({required this.onRetry});

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
              Icons.wifi_off_rounded,
              size: 44,
              color: t.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load players",
              style: t.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
