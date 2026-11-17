import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/widgets/player_avatar.dart';

/// Modal search sheet for choosing a player for one comparison slot.
///
/// Returns the chosen [PlayerListItem] via `Navigator.pop`. [excludeId] hides a
/// player already selected in the other slot so the two can't match.
class PlayerPickerSheet extends ConsumerStatefulWidget {
  final int? excludeId;
  final String title;
  const PlayerPickerSheet({super.key, this.excludeId, required this.title});

  static Future<PlayerListItem?> show(
    BuildContext context, {
    int? excludeId,
    required String title,
  }) {
    return showModalBottomSheet<PlayerListItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PlayerPickerSheet(excludeId: excludeId, title: title),
    );
  }

  @override
  ConsumerState<PlayerPickerSheet> createState() => _PlayerPickerSheetState();
}

class _PlayerPickerSheetState extends ConsumerState<PlayerPickerSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<List<PlayerListItem>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<List<PlayerListItem>> _load(String q) async {
    final page = await ref.read(apiClientProvider).fetchPlayers(
          q: q,
          pageSize: 30,
        );
    return page.items.where((p) => p.id != widget.excludeId).toList();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _query = value.trim();
        _future = _load(_query);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.title,
                    style: t.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search players',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<PlayerListItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _PickerMessage(
                      icon: Icons.wifi_off_rounded,
                      text: "Couldn't search players",
                    );
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return _PickerMessage(
                      icon: Icons.search_off_rounded,
                      text: _query.isEmpty
                          ? 'No players available'
                          : 'No players match "$_query"',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, i) {
                      final p = items[i];
                      return ListTile(
                        leading: PlayerAvatar(
                          imageUrl: p.imageUrl,
                          initials: p.initials,
                          radius: 20,
                        ),
                        title: Text(p.fullName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${[
                            if (p.position != null) p.position,
                            if (p.latestTeam != null) p.latestTeam,
                          ].join(' · ')} · ${p.careerSpan}',
                        ),
                        onTap: () => Navigator.of(context).pop(p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PickerMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(text,
              style: t.textTheme.bodyMedium
                  ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
