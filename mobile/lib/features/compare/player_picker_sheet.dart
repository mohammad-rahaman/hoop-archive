import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/theme.dart';
import '../../core/widgets/player_avatar.dart';
import '../../core/widgets/ui.dart';

/// Search sheet for choosing a player for one comparison slot.
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
      // Sheets cover the tab bar, as on iOS.
      useRootNavigator: true,
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
    final page = await ref
        .read(apiClientProvider)
        .fetchPlayers(q: q, pageSize: 30);
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
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                widget.title,
                style: Txt.title.copyWith(fontSize: 22),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoSearchTextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onChanged,
                placeholder: 'Search players',
                backgroundColor: Hue.ground,
                itemColor: Hue.textMid,
                style: Txt.body.copyWith(fontSize: 17),
                placeholderStyle: Txt.body.copyWith(
                  fontSize: 17,
                  color: Hue.textLo,
                ),
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<PlayerListItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Loading();
                  }
                  if (snap.hasError) {
                    return const MessageState(
                      icon: CupertinoIcons.wifi_slash,
                      title: "Couldn't search players",
                      message: 'Check your connection and try again.',
                    );
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return MessageState(
                      icon: CupertinoIcons.search,
                      title: _query.isEmpty
                          ? 'No players available'
                          : 'No players match "$_query"',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(indent: 76),
                    itemBuilder: (context, i) {
                      final p = items[i];
                      final meta = [
                        if (p.position != null) p.position!,
                        if (p.latestTeam != null) p.latestTeam!,
                        p.careerSpan,
                      ].join(' · ');
                      return InkWell(
                        onTap: () => Navigator.of(context).pop(p),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          child: Row(
                            children: [
                              PlayerAvatar(
                                imageUrl: p.imageUrl,
                                initials: p.initials,
                                radius: 22,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.fullName, style: Txt.headline),
                                    const SizedBox(height: 2),
                                    Text(meta, style: Txt.caption),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
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
