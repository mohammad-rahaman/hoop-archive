import 'package:flutter/material.dart';

/// A circular avatar that renders a player's official headshot when available,
/// with an automatic, graceful fallback to player initials on a styled gradient
/// background whenever the image is missing, loading, or offline.
class PlayerAvatar extends StatelessWidget {
  final String? imageUrl;
  final String initials;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final double borderWidth;

  const PlayerAvatar({
    super.key,
    required this.initials,
    this.imageUrl,
    this.radius = 24,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.borderWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.primary.withValues(alpha: 0.15);
    final fg = foregroundColor ?? theme.colorScheme.primary;
    final size = radius * 2;

    Widget fallbackAvatar() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: TextStyle(
              fontSize: radius * 0.72,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: -0.5,
            ),
          ),
        );

    final hasUrl = imageUrl != null && imageUrl!.trim().isNotEmpty;

    Widget content;
    if (!hasUrl) {
      content = fallbackAvatar();
    } else {
      content = ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => fallbackAvatar(),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return fallbackAvatar();
            },
          ),
        ),
      );
    }

    if (borderColor != null) {
      return Container(
        padding: EdgeInsets.all(borderWidth),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor!, width: borderWidth),
        ),
        child: content,
      );
    }

    return content;
  }
}
