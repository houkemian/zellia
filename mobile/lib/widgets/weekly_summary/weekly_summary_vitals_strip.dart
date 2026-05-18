import 'package:flutter/material.dart';

class WeeklySummaryVitalsStrip extends StatelessWidget {
  const WeeklySummaryVitalsStrip({
    super.key,
    required this.label,
    required this.valueText,
    this.subtitle,
    this.accentColor = const Color(0xFF5BCFB0),
  });

  final String label;
  final String valueText;
  final String? subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF5B6B88),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valueText,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF1D2B45),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6F7F99),
                fontSize: 15,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
