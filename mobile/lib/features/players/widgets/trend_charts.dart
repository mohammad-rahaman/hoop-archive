import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api/models.dart';
import '../../../core/theme.dart';
import '../career.dart';

/// A career as season columns: one bar per season for one metric.
///
/// Seasons are discrete, so each gets its own column rather than a line that
/// implies something happened between them. The selected season is volt with
/// its value above it; the career high is marked "high". Tap or drag across
/// the chart to move through seasons, with a selection haptic per season.
/// A season without a recorded value shows a dash at the baseline: a gap,
/// never a zero-height bar pretending to be data.
class CareerChart extends StatefulWidget {
  /// One row per season, oldest → newest (see [seasonLine]).
  final List<SeasonStatRow> line;
  final Metric metric;
  final int selected;
  final ValueChanged<int> onSelect;
  final double height;

  const CareerChart({
    super.key,
    required this.line,
    required this.metric,
    required this.selected,
    required this.onSelect,
    this.height = 196,
  });

  @override
  State<CareerChart> createState() => _CareerChartState();
}

class _CareerChartState extends State<CareerChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _grow;
  List<double?> _from = const [];
  List<double?> _to = const [];

  @override
  void initState() {
    super.initState();
    _to = _fractions();
    _from = _to;
    _grow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(CareerChart old) {
    super.didUpdateWidget(old);
    final sameLine = _sameLine(old.line, widget.line);
    if (old.metric.key == widget.metric.key && sameLine) return;
    final next = _fractions();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || !sameLine) {
      // A different split is a different chart: no morph between them.
      _from = next;
      _to = next;
      _grow.value = 1;
    } else {
      // Same seasons, new metric: bars grow from where they stand now.
      _from = _current();
      _to = next;
      _grow.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
  }

  static bool _sameLine(List<SeasonStatRow> a, List<SeasonStatRow> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].season != b[i].season ||
          a[i].seasonType != b[i].seasonType ||
          a[i].team != b[i].team) {
        return false;
      }
    }
    return true;
  }

  /// Each season's value as a fraction of the chart height (null = missing).
  List<double?> _fractions() {
    final values = [for (final r in widget.line) widget.metric.displayValue(r)];
    final maxV = values.whereType<double>().fold<double>(0, math.max);
    final top = maxV <= 0 ? 1.0 : maxV * 1.08;
    return [for (final v in values) v == null ? null : v / top];
  }

  List<double?> _current() {
    final t = Curves.easeOutCubic.transform(_grow.value);
    return [
      for (var i = 0; i < _to.length; i++)
        _to[i] == null
            ? null
            : ui.lerpDouble(i < _from.length ? (_from[i] ?? 0) : 0, _to[i]!, t),
    ];
  }

  void _pick(Offset local, double width) {
    final n = widget.line.length;
    if (n < 2) return;
    final i = (local.dx / (width / n)).floor().clamp(0, n - 1);
    if (i != widget.selected) {
      HapticFeedback.selectionClick();
      widget.onSelect(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metric;
    final sel = widget.line[widget.selected];
    final v = m.displayValue(sel);
    final label =
        '${m.long} by season. ${sel.season}: '
        '${v == null ? 'not recorded' : '${m.format(v)}${m.percent ? ' percent' : ''}'}.';

    return Semantics(
      label: label,
      hint: 'Drag to move through seasons',
      child: LayoutBuilder(
        builder: (context, c) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _pick(d.localPosition, c.maxWidth),
          onHorizontalDragStart: (d) => _pick(d.localPosition, c.maxWidth),
          onHorizontalDragUpdate: (d) => _pick(d.localPosition, c.maxWidth),
          child: AnimatedBuilder(
            animation: _grow,
            builder: (context, _) => CustomPaint(
              size: Size(c.maxWidth, widget.height),
              painter: _ColumnsPainter(
                line: widget.line,
                metric: m,
                fractions: _current(),
                selected: widget.selected,
                peak: peakIndex(widget.line, m),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColumnsPainter extends CustomPainter {
  final List<SeasonStatRow> line;
  final Metric metric;
  final List<double?> fractions;
  final int selected;
  final int? peak;

  _ColumnsPainter({
    required this.line,
    required this.metric,
    required this.fractions,
    required this.selected,
    required this.peak,
  });

  static const _labelTop = 22.0;
  static const _labelBand = 26.0;
  static const _graphite = Color(0xFF3A3A37);

  @override
  void paint(Canvas canvas, Size size) {
    final n = line.length;
    if (n == 0) return;
    final base = size.height - _labelBand;
    final plotH = base - _labelTop;
    final slot = size.width / n;
    final gap = (slot * 0.3).clamp(2.0, 10.0);
    final barW = math.max(2.0, slot - gap);
    final radius = Radius.circular(math.min(3.0, barW / 2));
    double left(int i) => i * slot + gap / 2;
    double top(int i) => base - plotH * fractions[i]!.clamp(0.0, 1.0);

    canvas.drawLine(
      Offset(0, base + 0.5),
      Offset(size.width, base + 0.5),
      Paint()
        ..color = Hue.hairlineStrong
        ..strokeWidth = 1,
    );

    for (var i = 0; i < n; i++) {
      final isSel = i == selected;
      if (fractions[i] == null) {
        // Not recorded: a short dash on the baseline.
        final w = math.min(barW, 8.0);
        final cx = left(i) + barW / 2;
        canvas.drawLine(
          Offset(cx - w / 2, base - 3),
          Offset(cx + w / 2, base - 3),
          Paint()
            ..color = isSel ? Hue.volt : Hue.textLo
            ..strokeWidth = 1.5,
        );
        continue;
      }
      final y = math.min(top(i), base - 2);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(left(i), y, left(i) + barW, base),
          topLeft: radius,
          topRight: radius,
        ),
        Paint()..color = isSel ? Hue.volt : _graphite,
      );
    }

    // Value over the selected column; "high" over the career high.
    final selV = metric.displayValue(line[selected]);
    if (selV != null && fractions[selected] != null) {
      _centered(
        canvas,
        '${metric.format(selV)}${metric.percent ? '%' : ''}',
        left(selected) + barW / 2,
        top(selected) - 18,
        size.width,
        Hue.textHi,
        12,
        FontWeight.w700,
      );
    }
    final p = peak;
    if (p != null && p != selected && fractions[p] != null) {
      _centered(
        canvas,
        'high',
        left(p) + barW / 2,
        top(p) - 16,
        size.width,
        Hue.textLo,
        10.5,
        FontWeight.w500,
      );
    }

    // Season labels: first, last, and the selected one (in volt).
    final selTp = _layout(line[selected].season, Hue.volt, 11, FontWeight.w600);
    final selLeft = (left(selected) + barW / 2 - selTp.width / 2).clamp(
      0.0,
      size.width - selTp.width,
    );
    final selRect = Rect.fromLTWH(selLeft - 6, 0, selTp.width + 12, 1);
    for (final i in {0, n - 1}) {
      if (i == selected) continue;
      final tp = _layout(line[i].season, Hue.textLo, 11, FontWeight.w500);
      final x = i == 0 ? 0.0 : size.width - tp.width;
      if (Rect.fromLTWH(x, 0, tp.width, 1).overlaps(selRect)) continue;
      tp.paint(canvas, Offset(x, base + 8));
    }
    selTp.paint(canvas, Offset(selLeft, base + 8));
  }

  TextPainter _layout(String t, Color c, double s, FontWeight w) => TextPainter(
    text: TextSpan(
      text: t,
      style: TextStyle(
        color: c,
        fontSize: s,
        fontWeight: w,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  void _centered(
    Canvas canvas,
    String t,
    double cx,
    double y,
    double width,
    Color c,
    double s,
    FontWeight w,
  ) {
    final tp = _layout(t, c, s, w);
    final x = (cx - tp.width / 2).clamp(0.0, width - tp.width);
    tp.paint(canvas, Offset(x, math.max(0.0, y)));
  }

  @override
  bool shouldRepaint(_ColumnsPainter old) {
    if (old.selected != selected ||
        old.metric.key != metric.key ||
        old.peak != peak ||
        old.fractions.length != fractions.length) {
      return true;
    }
    for (var i = 0; i < fractions.length; i++) {
      if (old.fractions[i] != fractions[i]) return true;
    }
    return false;
  }
}
