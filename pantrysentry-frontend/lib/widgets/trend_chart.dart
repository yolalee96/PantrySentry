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

    // Gridlines sit on whole numbers at an even step (1, 2, 5, 10, ...),
    // and the axis top is rounded up to a multiple of that step. Before,
    // gridlines were drawn at 0% / 50% / 100% of the max and the label
    // was rounded — with a max of 3 the middle line sat at 1.5 but was
    // labelled "2", so 1-item bars looked far too short against it.
    final step = _niceStep(maxVal);
    final axisMax = ((maxVal + step - 1) ~/ step) * step;
    for (var value = 0; value <= axisMax; value += step) {
      final y = chartHeight - chartHeight * value / axisMax;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
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

    double heightFor(int value) => chartHeight * value / axisMax;

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
      final labelEvery = (points.length / 10).ceil().clamp(1, points.length);
      if (i % labelEvery == 0) {
        final label = points.length <= 10 ? weekdayShort[points[i].date.weekday - 1] : '${points[i].date.day}';
        final tp = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(slotLeft + slotWidth / 2 - tp.width / 2, chartHeight + 4));
      }
    }
  }

  /// Smallest "nice" step (1, 2, 5, 10, 20, 50, ...) that keeps the
  /// chart to about 5 gridlines or fewer. Small counts (max 5 or less)
  /// get a line at every whole number.
  static int _niceStep(int maxVal) {
    for (var magnitude = 1; ; magnitude *= 10) {
      for (final m in const [1, 2, 5]) {
        final step = m * magnitude;
        if (maxVal / step <= 5) return step;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendBarPainter oldDelegate) => oldDelegate.points != points;
}