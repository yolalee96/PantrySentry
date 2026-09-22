import 'package:flutter/material.dart';
import '../models/insights_data.dart';

/// User Story 5.3's trend chart — grouped bars (Consumed / Wasted side by
/// side per day) rather than lines. Switched from a line chart because
/// two series with an identical value on the same day would draw exactly
/// on top of each other and one would completely hide the other — bars
/// next to each other can't do that. Days with no activity show a real,
/// visible zero-height bar; days that haven't happened yet are never
/// generated as a group at all (see InsightsService.trend / AC 5.3.7) —
/// if there's nothing to plot, this shows an empty state instead.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, this.height = 180});
  final List<TrendPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Nothing to show yet for this period', style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5)),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _TrendBarPainter(points)),
    );
  }
}

class _TrendBarPainter extends CustomPainter {
  _TrendBarPainter(this.points);
  final List<TrendPoint> points;

  static const _consumedColor = Color(0xFF2E7D4F);
  static const _wastedColor = Color(0xFFD32F2F);

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 28.0;
    const bottomPad = 20.0;
    final chartWidth = size.width - leftPad;
    final chartHeight = size.height - bottomPad;

    final maxVal = points
        .expand((p) => [p.consumed, p.wasted])
        .fold<int>(1, (m, v) => v > m ? v : m);

    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: Colors.grey.shade600, fontSize: 9);

    int? lastLabelValue;
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = chartHeight - (chartHeight * fraction);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      final value = (maxVal * fraction).round();
      // Skip a label that duplicates the one just drawn (e.g. maxVal=1
      // makes the midpoint round to 1 too, same as the top) — the
      // gridline still draws, just without a redundant repeated number.
      if (value == lastLabelValue) continue;
      lastLabelValue = value;
      final tp = TextPainter(
        text: TextSpan(text: '$value', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    // Each day gets a "slot"; two bars (consumed, wasted) sit side by
    // side within it, with a little padding between slots and between
    // the two bars in a slot.
    final slotWidth = chartWidth / points.length;
    final groupPadding = slotWidth * 0.18;
    final barGap = slotWidth * 0.06;
    final barWidth = (slotWidth - groupPadding * 2 - barGap) / 2;

    double heightFor(int value) => maxVal == 0 ? 0 : chartHeight * value / maxVal;

    final consumedPaint = Paint()..color = _consumedColor;
    final wastedPaint = Paint()..color = _wastedColor;
    const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    for (var i = 0; i < points.length; i++) {
      final slotLeft = leftPad + slotWidth * i;
      final consumedLeft = slotLeft + groupPadding;
      final wastedLeft = consumedLeft + barWidth + barGap;

      final consumedH = heightFor(points[i].consumed);
      final wastedH = heightFor(points[i].wasted);

      // Draw a minimum visible sliver even for a real zero, so a zero bar
      // still reads as "plotted" rather than looking identical to empty
      // space — a deliberate 2px floor, not a value change.
      final consumedRect = Rect.fromLTWH(consumedLeft, chartHeight - (consumedH < 1 ? 1.5 : consumedH), barWidth, consumedH < 1 ? 1.5 : consumedH);
      final wastedRect = Rect.fromLTWH(wastedLeft, chartHeight - (wastedH < 1 ? 1.5 : wastedH), barWidth, wastedH < 1 ? 1.5 : wastedH);
      canvas.drawRRect(RRect.fromRectAndCorners(consumedRect, topLeft: const Radius.circular(2), topRight: const Radius.circular(2)), consumedPaint);
      canvas.drawRRect(RRect.fromRectAndCorners(wastedRect, topLeft: const Radius.circular(2), topRight: const Radius.circular(2)), wastedPaint);

      // Day label — thin out if there are many points (monthly view).
      final step = (points.length / 10).ceil().clamp(1, points.length);
      if (i % step == 0) {
        final label = points.length <= 10 ? weekdayShort[points[i].date.weekday - 1] : '${points[i].date.day}';
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(slotLeft + slotWidth / 2 - tp.width / 2, chartHeight + 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendBarPainter oldDelegate) => oldDelegate.points != points;
}
