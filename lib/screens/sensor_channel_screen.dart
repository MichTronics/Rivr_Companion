import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/telemetry_reading.dart';
import '../providers/app_providers.dart';
import '../providers/settings_provider.dart';

// ── Period enum ───────────────────────────────────────────────────────────

enum _Period {
  h1('1u', Duration(hours: 1)),
  h6('6u', Duration(hours: 6)),
  h24('24u', Duration(hours: 24)),
  d7('7d', Duration(days: 7));

  final String label;
  final Duration window;
  const _Period(this.label, this.window);
}

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

class _SensorBody extends ConsumerStatefulWidget {
  const _SensorBody();

  @override
  ConsumerState<_SensorBody> createState() => _SensorBodyState();
}

class _SensorBodyState extends ConsumerState<_SensorBody> {
  _Period _period = _Period.h24;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final idx = ref.read(settingsProvider).defaultSensorPeriodIndex;
      if (idx >= 0 && idx < _Period.values.length) {
        setState(() => _period = _Period.values[idx]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings  = ref.watch(settingsProvider);
    final useFahrenheit = settings.useFahrenheit;
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

    final cutoff = DateTime.now().subtract(_period.window);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Period selector ─────────────────────────────────────────────
        Center(
          child: SegmentedButton<_Period>(
            segments: _Period.values
                .map((p) => ButtonSegment<_Period>(
                      value: p,
                      label: Text(p.label),
                    ))
                .toList(),
            selected: {_period},
            onSelectionChanged: (s) {
              setState(() => _period = s.first);
              ref.read(settingsNotifierProvider.notifier)
                  .setDefaultSensorPeriodIndex(_Period.values.indexOf(s.first));
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // ── Per-node cards ───────────────────────────────────────────────
        ...telemetry.entries.map((nodeEntry) {
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
                        .map((r) => _SensorTile(reading: r, useFahrenheit: useFahrenheit))
                        .toList(),
                  ),
                  ...sensors.keys.map((sensorId) {
                    final allPts = nodeHistory[sensorId] ?? [];
                    final pts = allPts
                        .where((r) => r.receivedAt.isAfter(cutoff))
                        .toList();
                    if (pts.length < 2) return const SizedBox.shrink();
                    final reading = sensors[sensorId]!;
                    final suffix = (reading.isTemperature && useFahrenheit)
                        ? '°F'
                        : reading.unitSuffix;
                    return _SensorChart(
                      label: reading.sensorLabel,
                      unitSuffix: suffix,
                      isTemperature: reading.isTemperature,
                      useFahrenheit: useFahrenheit,
                      points: pts,
                    );
                  }),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ── Sensor tile ───────────────────────────────────────────────────────────

class _SensorTile extends StatelessWidget {
  final TelemetryReading reading;
  final bool useFahrenheit;
  const _SensorTile({required this.reading, this.useFahrenheit = false});

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

    final displayValue = (isTemp && useFahrenheit)
        ? reading.value * 1.8 + 32
        : reading.value;
    final displaySuffix = (isTemp && useFahrenheit) ? '°F' : reading.unitSuffix;
    final displayStr = '${displayValue.toStringAsFixed(1)}$displaySuffix';

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
            displayStr,
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
  final bool                   useFahrenheit;
  final List<TelemetryReading> points;

  const _SensorChart({
    required this.label,
    required this.unitSuffix,
    required this.isTemperature,
    this.useFahrenheit = false,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final color = isTemperature ? cs.tertiary : Colors.blue.shade600;

    final values = points.map((r) {
      final v = r.value;
      return (isTemperature && useFahrenheit) ? v * 1.8 + 32 : v;
    }).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final pad    = (maxVal - minVal) < 1.0 ? 1.0 : (maxVal - minVal) * 0.1;
    final minY   = minVal - pad;
    final maxY   = maxVal + pad;

    final t0Sec = points.first.receivedAt.millisecondsSinceEpoch / 1000.0;
    final spots = points.map((r) {
      final x = r.receivedAt.millisecondsSinceEpoch / 1000.0 - t0Sec;
      final y = (isTemperature && useFahrenheit) ? r.value * 1.8 + 32 : r.value;
      return FlSpot(x, y);
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
