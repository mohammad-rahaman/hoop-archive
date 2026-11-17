import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connectivity.dart';
import '../theme.dart';
import '../time_ago.dart';

/// A slim strip shown while the device is offline. Collapses to nothing when
/// connectivity is present (or still unknown), so it's safe to place at the
/// top of any screen body.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(isOfflineProvider);
    if (!offline) return const SizedBox.shrink();

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Hue.panel,
          border: Border(bottom: BorderSide(color: Hue.hairline)),
        ),
        child: Row(
          children: [
            const Icon(CupertinoIcons.wifi_slash, size: 16, color: Hue.volt),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "You're offline. Showing saved data where available.",
                style: Txt.caption.copyWith(color: Hue.textHi),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An inline note telling the user the content below was replayed from the
/// local cache, with its age. Shown when a load fell back to a saved copy.
class CachedCopyNote extends StatelessWidget {
  final DateTime cachedAt;
  const CachedCopyNote({super.key, required this.cachedAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Hue.hairlineStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.clock, size: 14, color: Hue.textMid),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'Saved copy · updated ${relativeSince(cachedAt)}',
              style: Txt.caption.copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
