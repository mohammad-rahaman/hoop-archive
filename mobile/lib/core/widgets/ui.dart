import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// A raised instrument panel: flat fill, 1px hairline, generous radius.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color borderColor;
  final Color color;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderColor = Hue.hairline,
    this.color = Hue.panel,
    this.onTap,
    this.semanticLabel,
  });

  static const radius = BorderRadius.all(Radius.circular(22));

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? body : InkWell(onTap: onTap, child: body),
      ),
    );
  }
}

/// Small tracked caps used to name a figure, never as a kicker over a heading.
class TrackedLabel extends StatelessWidget {
  final String text;
  final Color color;
  const TrackedLabel(this.text, {super.key, this.color = Hue.textMid});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Txt.label.copyWith(color: color),
    );
  }
}

/// A number with its tracked label underneath.
class Figure extends StatelessWidget {
  final String value;
  final String label;
  final TextStyle style;
  final Color labelColor;
  final CrossAxisAlignment align;

  /// Tracked caps for stat abbreviations (GP, FG%); plain sentence case for
  /// words ("stat lines").
  final bool tracked;

  const Figure({
    super.key,
    required this.value,
    required this.label,
    this.style = Txt.numeralM,
    this.labelColor = Hue.textMid,
    this.align = CrossAxisAlignment.start,
    this.tracked = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Big numbers shrink rather than clip when space runs out.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: align == CrossAxisAlignment.end
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(value, style: style, maxLines: 1),
        ),
        SizedBox(height: tracked ? 6 : 2),
        if (tracked)
          TrackedLabel(label, color: labelColor)
        else
          Text(label, style: Txt.caption.copyWith(color: labelColor)),
      ],
    );
  }
}

/// A hairline capsule for compact status ("1979 – 2021", "Offline").
class StatusPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool active;
  final VoidCallback? onTap;

  const StatusPill(
    this.text, {
    super.key,
    this.icon,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? Hue.volt : Hue.textHi;
    final pill = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Hue.ground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? Hue.volt.withValues(alpha: 0.7) : Hue.hairlineStrong,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: active ? Hue.volt : Hue.textMid),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(widthFactor: 1, child: pill),
      ),
    );
  }
}

/// Regular season / playoffs switch. The platform's sliding segmented
/// control, themed to the panel palette.
class SplitControl extends StatelessWidget {
  final bool playoffs;
  final ValueChanged<bool> onChanged;
  const SplitControl({
    super.key,
    required this.playoffs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget seg(String text, bool selected) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: -0.2,
          color: selected ? Hue.textHi : Hue.textMid,
        ),
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<bool>(
        groupValue: playoffs,
        backgroundColor: Hue.panel,
        thumbColor: Hue.hairlineStrong,
        padding: const EdgeInsets.all(3),
        children: {
          false: seg('Regular season', !playoffs),
          true: seg('Playoffs', playoffs),
        },
        onValueChanged: (v) {
          if (v != null && v != playoffs) onChanged(v);
        },
      ),
    );
  }
}

/// A section heading with an optional trailing note.
class SectionHeading extends StatelessWidget {
  final String title;
  final String? note;
  const SectionHeading(this.title, {super.key, this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: Txt.headline.copyWith(fontSize: 20)),
          if (note != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                note!,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Txt.caption.copyWith(color: Hue.textLo),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Centered empty / error message with an optional action.
class MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const MessageState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Hue.hairlineStrong),
              ),
              child: Icon(icon, size: 24, color: Hue.textMid),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Txt.headline.copyWith(fontSize: 19),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: Txt.caption),
            ],
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 22),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Platform activity indicator, centered.
class Loading extends StatelessWidget {
  final double padding;
  const Loading({super.key, this.padding = 48});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: padding),
      child: const Center(
        child: CupertinoActivityIndicator(color: Hue.textMid, radius: 11),
      ),
    );
  }
}
