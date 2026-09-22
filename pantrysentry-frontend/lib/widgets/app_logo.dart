import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.markSize = 250,
    this.showWordmark = true,
    this.wordmarkFontSize = 22,
    this.direction = Axis.vertical,
  });

  /// Size (width & height) of the icon mark.
  final double markSize;

  /// Kept for API compatibility with existing call sites — the wordmark
  /// was intentionally removed, so this no longer has any effect.
  final bool showWordmark;
  final double wordmarkFontSize;
  final Axis direction;

  Widget _buildMark(BuildContext context) {
    return Image.asset('assets/images/Logo.png', width: markSize, height: markSize);
  }

  @override
  Widget build(BuildContext context) {
    return _buildMark(context);
  }
}