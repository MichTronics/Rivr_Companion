import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/telemetry_reading.dart';
import '../providers/app_providers.dart';

/// Full-screen sensor telemetry view shown when the user opens the Sensor channel.
class SensorChannelScreen extends ConsumerWidget {
  const SensorChannelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sensor')),
      body: const _SensorBody(),
    );
  }
}

class _SensorBody extends ConsumerWidget {
  const _SensorBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(telemetryProvider);
    final history   = ref.watch(telemetryHistoryProvider);

    if (telemetry.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sensors_off_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No telemetry received yet.\nSensor data arrives every TX interval.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: telemetry.entries.map((nodeEntry) {
        final nodeId      = nodeEntry.key;
        final sensors     = nodeEntry.value;
        final nodeHex     = '0x${nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
        final nodes       = ref.watch(nodesProvider);
        final node        = nodes[nodeId];
        final nodeLabel   = (node != null && node.callsign.isNotEmpty)
            ? '${node.callsign} ($nodeHex)'
            : nodeHex;
        final nodeHistory = history[nodeId] ?? {};

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.sensors, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      nodeLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const Divider(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sensors.values
                      .map((r) => _SensorTile(reading: r))
                      .toList(),
                ),
                ...sensors.keys.map((sensorId) {
                  final pts = nodeHistory[sensorId] ?? [];
                  if (pts.length < 2) return const SizedBox.shrink();
                  final reading = sensors[sensorId]!;
                  return _SensorChart(
                    label: reading.sensorLabel,
                    unitSuffix: reading.unitSuffix,
                    isTemperature: reading.isTemperature,
                    points: pts,
                  );
                }),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Sensor tile ───────────────────────────────────────────────────────────

class _SensorTile extends StatelessWidget {
  final TelemetryReading reading;
  const _SensorTile({required this.reading});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isTemp = reading.isTemperature;
    final color  = isTemp ? cs.tertiary : Colors.blue.shade600;
    final bg     = isTemp
        ? cs.tertiaryContainer.withValues(alpha: 0.4)
        : Colors.blue.shade50;
    final icon   = isTemp ? Icons.thermostat_outlined : Icons.water_drop_outlined;
    final age    = DateTime.now().difference(reading.receivedAt);
    final ageStr = age.inSeconds < 60
        ? '${age.inSeconds}s ago'
        : '${age.inMinutes}m ago';

    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                reading.sensorLabel,
                style:
                    Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            reading.formatted,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            ageStr,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Sensor chart ──────────────────────────────────────────────────────────

class _SensorChart extends StatelessWidget {
  final String                 label;
  final String                 unitSuffix;
  final bool                   isTemperature;
  final List<TelemetryReading> points;

  const _SensorChart({
    required this.label,
    required this.unitSuffix,
    required this.isTemperature,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final color = isTemperature ? cs.tertiary : Colors.blue.shade600;

    final values = points.map((r) => r.value).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final pad    = (maxVal - minVal) < 1.0 ? 1.0 : (maxVal - minVal) * 0.1;
    final minY   = minVal - pad;
    final maxY   = maxVal + pad;

    final t0Sec = points.first.receivedAt.millisecondsSinceEpoch / 1000.0;
    final spots = points.map((r) {
      final x = r.receivedAt.millisecondsSinceEpoch / 1000.0 - t0Sec;
      return FlSpot(x, r.value);
    }).toList();

    final totalSec     = spots.last.x;
    final labelInterval = totalSec > 0 ? (totalSec / 4.0) : 1.0;

    final fmt     = DateFormat('HH:mm');
    final fmtFull = DateFormat('HH:mm:ss');

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: color),
            ),
            const SizedBox(width: 4),
            Text(
              '(${points.length} samples)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 120,
            child: LineChart(LineChartData(
              minY: minY,
              maxY: maxY,
              clipData: const FlClipData.all(),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (touchedSpots) =>
                      touchedSpots.map((s) {
                    final absMs = ((t0Sec + s.x) * 1000).round();
                    final t     = DateTime.fromMillisecondsSinceEpoch(absMs);
                    return LineTooltipItem(
                      '${fmtFull.format(t)}\n${s.y.toStringAsFixed(2)} $unitSuffix',
                      TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.w600),
                    );
                  }).toList(),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toStringAsFixed(1)}$unitSuffix',
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 18,
                    interval: labelInterval,
                    getTitlesWidget: (v, _) {
                      final absMs = ((t0Sec + v) * 1000).round();
                      final t     = DateTime.fromMillisecondsSinceEpoch(absMs);
                      return Text(fmt.format(t),
                          style: const TextStyle(fontSize: 9));
                    },
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: color,
                  barWidth: 2,
                  dotData: FlDotData(
                    show: points.length <= 30,
                    getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                      radius: 2.5,
                      color: color,
                      strokeWidth: 0,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withValues(alpha: 0.12),
                  ),
                ),
              ],
            )),
          ),
        ],
      ),
    );
  }
}
