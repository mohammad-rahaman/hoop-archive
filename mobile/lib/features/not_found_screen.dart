import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';

/// Shown for unknown or malformed routes (e.g. a stale deep link). Gives the
/// user a clear way back rather than a raw router error page.
class NotFoundScreen extends StatelessWidget {
  final String? location;
  const NotFoundScreen({super.key, this.location});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('404', style: Txt.numeralXL.copyWith(color: Hue.textLo)),
              const SizedBox(height: 18),
              Text("This page doesn't exist", style: Txt.title),
              const SizedBox(height: 8),
              Text(
                'The link may be out of date. Everything in the archive is '
                'still a tap away.',
                style: Txt.caption.copyWith(fontSize: 15),
              ),
              if (location != null) ...[
                const SizedBox(height: 14),
                Text(
                  location!,
                  style: Txt.caption.copyWith(
                    color: Hue.textLo,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Go home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
