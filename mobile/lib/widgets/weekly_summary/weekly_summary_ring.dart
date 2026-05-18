import 'package:flutter/material.dart';

/// Minimal circular adherence indicator (no chart package).
class WeeklySummaryRing extends StatelessWidget {
  const WeeklySummaryRing({
    super.key,
    required this.percent,
    this.size = 140,
  });

  final double percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = percent.clamp(0.0, 100.0) / 100.0;
    final color = percent >= 95
        ? const Color(0xFF5BCFB0)
        : percent >= 70
        ? const Color(0xFFFFB74D)
        : theme.colorScheme.error;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: clamped,
              strokeWidth: 12,
              backgroundColor: color.withValues(alpha: 0.18),
              color: color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${percent.toStringAsFixed(0)}%',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: const Color(0xFF1D2B45),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
