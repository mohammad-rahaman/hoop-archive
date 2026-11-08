import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shown for unknown or malformed routes (e.g. a stale deep link). Gives the
/// user a clear way back rather than a raw router error page.
class NotFoundScreen extends StatelessWidget {
  final String? location;
  const NotFoundScreen({super.key, this.location});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore_off_rounded,
                size: 48,
                color: t.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              Text(
                "This page doesn't exist",
                style: t.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (location != null) ...[
                const SizedBox(height: 6),
                Text(
                  location!,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.home_rounded),
                label: const Text('Go home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
