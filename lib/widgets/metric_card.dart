import 'package:flutter/material.dart';

enum MetricSeverity { ok, warning, critical }

/// Compact metric tile used in the Diagnostics overview.
class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final MetricSeverity severity;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.severity = MetricSeverity.ok,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color iconColor;
    final Color bgColor;

    switch (severity) {
      case MetricSeverity.critical:
        iconColor = cs.error;
        bgColor = cs.errorContainer;
      case MetricSeverity.warning:
        iconColor = Colors.orange.shade700;
        bgColor = Colors.orange.shade50;
      case MetricSeverity.ok:
        iconColor = cs.primary;
        bgColor = cs.primaryContainer;
    }

    return Card(
      color: bgColor,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.6),
                  ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
