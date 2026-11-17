import 'package:flutter/material.dart';

import '../theme.dart';

/// A circular avatar that renders a player's official headshot when available,
/// falling back to initials on a flat panel disc whenever the image is
/// missing, loading, or offline.
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
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Hue.raised;
    final fg = foregroundColor ?? Hue.textMid;
    final size = radius * 2;

    Widget fallbackAvatar() => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.66,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: -0.3,
        ),
      ),
    );

    final hasUrl = imageUrl != null && imageUrl!.trim().isNotEmpty;

    final Widget content = !hasUrl
        ? fallbackAvatar()
        : ClipOval(
            child: Container(
              width: size,
              height: size,
              color: bg,
              child: Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) => fallbackAvatar(),
                // Initials stay up until the first real frame paints, so a
                // slow or offline image never leaves an empty disc.
                frameBuilder: (context, child, frame, sync) =>
                    frame == null && !sync ? fallbackAvatar() : child,
              ),
            ),
          );

    final ring = borderColor ?? Hue.hairlineStrong;
    return Container(
      padding: EdgeInsets.all(borderWidth),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: borderWidth),
      ),
      child: content,
    );
  }
}
