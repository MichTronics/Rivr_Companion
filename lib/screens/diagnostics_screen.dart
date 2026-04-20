import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/app_settings.dart';
import '../models/metrics.dart';
import '../models/telemetry_reading.dart';
import '../protocol/rivr_protocol.dart';
import '../providers/app_providers.dart';
import '../providers/settings_provider.dart';
import '../widgets/metric_card.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(metricsProvider);
    final latest = ref.watch(latestMetricsProvider);
    final settings = ref.watch(settingsProvider);
    final isConnected = ref.watch(connectionStateProvider).maybeWhen(
          data: (s) => s.isConnected,
          orElse: () => false,
        );
    final canRequestMetrics =
        isConnected && settings.lastConnectionType == ConnectionType.usb;

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Charts'),
            Tab(text: 'Sensors'),
            Tab(text: 'Raw Log'),
          ]),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(
                  latest: latest,
                  isConnected: isConnected,
                  canRequestMetrics: canRequestMetrics,
                ),
                _ChartsTab(history: history),
                const _SensorsTab(),
                const _RawLogTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Overview tab ──────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  final RivrMetrics latest;
  final bool isConnected;
  final bool canRequestMetrics;

  const _OverviewTab({
    required this.latest,
    required this.isConnected,
    required this.canRequestMetrics,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: canRequestMetrics
          ? const AlwaysScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Node & connection
            const _SectionHeader('Node'),
            _InfoRow('Node ID',
                latest.nodeId != 0
                    ? '0x${latest.nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}'
                    : '—'),
            _InfoRow('Collected',
                latest.collectedAt.millisecondsSinceEpoch == 0
                    ? '—'
                    : DateFormat('HH:mm:ss').format(latest.collectedAt)),
            const SizedBox(height: 16),

            // Radio health
            const _SectionHeader('Radio'),
            Row(children: [
              Expanded(
                child: MetricCard(
                  label: 'Duty Cycle',
                  value: '${latest.dcPct}%',
                  icon: Icons.timer_outlined,
                  severity: latest.dcPct > 80
                      ? MetricSeverity.critical
                      : latest.dcPct > 50
                          ? MetricSeverity.warning
                          : MetricSeverity.ok,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                  label: 'TX Queue',
                  value: '${latest.qDepth}',
                  icon: Icons.queue_outlined,
                  severity: latest.qDepth > 6
                      ? MetricSeverity.warning
                      : MetricSeverity.ok,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                  label: 'Best RSSI',
                  value: '${latest.lnkRssi} dBm',
                  icon: Icons.signal_cellular_alt,
                  severity: latest.lnkRssi < -110
                      ? MetricSeverity.critical
                      : latest.lnkRssi < -95
                          ? MetricSeverity.warning
                          : MetricSeverity.ok,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: MetricCard(
                  label: 'Neighbors',
                  value: '${latest.lnkCnt}',
                  icon: Icons.people_outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                  label: 'Link Score',
                  value: '${latest.lnkBest}/100',
                  icon: Icons.star_outline,
                  severity: latest.lnkBest < 30
                      ? MetricSeverity.warning
                      : MetricSeverity.ok,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                  label: 'Avg Loss',
                  value: '${latest.lnkLoss}%',
                  icon: Icons.signal_wifi_bad_outlined,
                  severity: latest.lnkLoss > 30
                      ? MetricSeverity.critical
                      : latest.lnkLoss > 15
                          ? MetricSeverity.warning
                          : MetricSeverity.ok,
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // Relay pipeline
            const _SectionHeader('Relay pipeline'),
            Row(children: [
              Expanded(
                child: MetricCard(
                    label: 'Forwarded',
                    value: '${latest.relayFwd}',
                    icon: Icons.forward_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                    label: 'Skipped',
                    value: '${latest.relaySkip}',
                    icon: Icons.skip_next_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                    label: 'Density',
                    value: '${latest.relayDensity}',
                    icon: Icons.grain_outlined),
              ),
            ]),
            const SizedBox(height: 16),

            // Packet stats
            const _SectionHeader('Packet stats'),
            _InfoRow('TX total',        '${latest.txTotal}'),
            _InfoRow('RX total',        '${latest.rxTotal}'),
            _InfoRow('Route cache',     '${latest.routeCache} entries'),
            _InfoRow('Cache hit / miss','${latest.routeCacheHit} / ${latest.routeCacheMiss}'),
            const SizedBox(height: 12),

            const _SectionHeader('Drop counters'),
            _InfoRow('Decode fail',     '${latest.rxDecodeFail}'),
            _InfoRow('Dedupe drop',     '${latest.rxDedupeDrop}'),
            _InfoRow('TTL drop',        '${latest.rxTtlDrop}'),
            _InfoRow('Bad type',        '${latest.rxBadType}'),
            _InfoRow('Bad hop',         '${latest.rxBadHop}'),
            _InfoRow('No route',        '${latest.noRoute}'),
            _InfoRow('TX queue full',   '${latest.txQueueFull}'),
            _InfoRow('Duty blocked',    '${latest.dutyBlocked}'),
            _InfoRow('Loop detect',     '${latest.loopDetectDrop}'),
            const SizedBox(height: 12),

            const _SectionHeader('Radio hardware'),
            _InfoRow('Hard resets',     '${latest.radioHardReset}'),
            _InfoRow('TX failures',     '${latest.radioTxFail}'),
            _InfoRow('CRC errors',      '${latest.radioCrcFail}'),
            const SizedBox(height: 12),

            const _SectionHeader('ACK / Retry'),
            _InfoRow('ACK TX / RX',    '${latest.ackTx} / ${latest.ackRx}'),
            _InfoRow('Retry attempts',  '${latest.retryAttempt}'),
            _InfoRow('Retry OK / fail', '${latest.retrySuccess} / ${latest.retryFail}'),
            const SizedBox(height: 16),

            // BLE-specific counters (§11: ble_conn, ble_rx, ble_tx, ble_err)
            const _SectionHeader('BLE transport'),
            Row(children: [
              Expanded(
                child: MetricCard(
                  label: 'Connections',
                  value: '${latest.bleConn}',
                  icon: Icons.bluetooth_connected,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                  label: 'RX from phone',
                  value: '${latest.bleRx}',
                  icon: Icons.arrow_downward,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricCard(
                  label: 'TX to phone',
                  value: '${latest.bleTx}',
                  icon: Icons.arrow_upward,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            _InfoRow('BLE stack errors', '${latest.bleErr}'),
            const SizedBox(height: 16),

            if (canRequestMetrics)
              Center(
                child: FilledButton.tonal(
                  onPressed: () => ref
                      .read(connectionManagerProvider)
                      .send(RivrProtocol.cmdMetrics),
                  child: const Text('Refresh metrics now'),
                ),
              ),
            if (isConnected && !canRequestMetrics)
              Text(
                'Manual metrics refresh is only available over USB serial.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
        ],
      ),
    );

    if (!canRequestMetrics) return content;

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(connectionManagerProvider).send(RivrProtocol.cmdMetrics),
      child: content,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Charts tab ────────────────────────────────────────────────────────────

class _ChartsTab extends StatelessWidget {
  final List<RivrMetrics> history;
  const _ChartsTab({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) {
      return const Center(
        child: Text('Waiting for metric samples…',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChartCard(
            title: 'Duty Cycle %',
            spots: _toSpots(history, (m) => m.dcPct.toDouble()),
            maxY: 100,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Best Link Score',
            spots: _toSpots(history, (m) => m.lnkBest.toDouble()),
            maxY: 100,
            color: Colors.green.shade600,
          ),
          const SizedBox(height: 16),
          _ChartCard(
            title: 'Relay Density (viable neighbors)',
            spots: _toSpots(history, (m) => m.relayDensity.toDouble()),
            maxY: 16,
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ],
      ),
    );
  }

  List<FlSpot> _toSpots(
          List<RivrMetrics> hist, double Function(RivrMetrics) fn) =>
      hist.asMap().entries.map((e) => FlSpot(e.key.toDouble(), fn(e.value))).toList();
}

class _ChartCard extends StatelessWidget {
  final String title;
  final List<FlSpot> spots;
  final double maxY;
  final Color color;

  const _ChartCard({
    required this.title,
    required this.spots,
    required this.maxY,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            SizedBox(
              height: 120,
              child: LineChart(LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 32,
                        getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                            style: const TextStyle(fontSize: 9))),
                  ),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
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
      ),
    );
  }
}

// ── Sensors tab ───────────────────────────────────────────────────────────

class _SensorsTab extends ConsumerWidget {
  const _SensorsTab();

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
                // Node header
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
                // Latest value tiles
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sensors.values
                      .map((r) => _SensorTile(reading: r))
                      .toList(),
                ),
                // Chart per sensor
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
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
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

class _SensorChart extends StatelessWidget {
  final String              label;
  final String              unitSuffix;
  final bool                isTemperature;
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

    // Use seconds since first point as X so spacing is proportional to real time
    final t0Sec = points.first.receivedAt.millisecondsSinceEpoch / 1000.0;
    final spots = points.map((r) {
      final x = r.receivedAt.millisecondsSinceEpoch / 1000.0 - t0Sec;
      return FlSpot(x, r.value);
    }).toList();

    final totalSec = spots.last.x;

    // Pick ~4 evenly-spaced x-axis label positions
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
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
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
              gridData: const FlGridData(
                show: true,
                drawVerticalLine: false,
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (touchedSpots) =>
                      touchedSpots.map((s) {
                    final absMs = ((t0Sec + s.x) * 1000).round();
                    final t = DateTime.fromMillisecondsSinceEpoch(absMs);
                    return LineTooltipItem(
                      '${fmtFull.format(t)}\n${s.y.toStringAsFixed(2)} $unitSuffix',
                      TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
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
                      final t = DateTime.fromMillisecondsSinceEpoch(absMs);
                      return Text(fmt.format(t), style: const TextStyle(fontSize: 9));
                    },
                  ),
                ),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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

// ── Raw log tab ───────────────────────────────────────────────────────────

class _RawLogTab extends ConsumerStatefulWidget {
  const _RawLogTab();

  @override
  ConsumerState<_RawLogTab> createState() => _RawLogTabState();
}

class _RawLogTabState extends ConsumerState<_RawLogTab> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients &&
        _scrollController.position.hasContentDimensions) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Color _lineColor(String line) {
    // Skip the "HH:MM:SS " timestamp prefix added by LogNotifier.
    final c = line.length > 9 ? line.substring(9) : line;
    // BLE frame descriptions: "RX BLE_CHAT ...", "TX BLE_CHAT ..."
    // USB text lines:          "@CHT {...}", "@BCN {...}", "@MET {...}"
    if (c.contains('BLE_CHAT') || c.startsWith('@CHT')) return Colors.cyanAccent;
    if (c.contains('BLE_BEACON') || c.startsWith('@BCN') ||
        c.contains('BEACON src=')) return Colors.lightBlueAccent;
    if (c.contains('BLE_METRICS') || c.startsWith('@MET')) return Colors.yellowAccent;
    if (c.contains('BLE_TELEMETRY') || c.startsWith('@TEL')) return Colors.orangeAccent;
    if (c.contains('BLE_CP:device') || c.contains('Node ID')) return Colors.purpleAccent;
    if (c.startsWith('error') || c.contains('invalid') || c.contains('ERR')) {
      return Colors.redAccent;
    }
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(logProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                const SizedBox(width: 4),
                Text(
                  '${lines.length} / ${LogNotifier.maxLines} lines',
                  style: const TextStyle(
                      color: Colors.green, fontFamily: 'monospace', fontSize: 11),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => ref.read(logProvider.notifier).clear(),
                ),
              ],
            ),
          ),
          Expanded(
            child: Card(
              color: Colors.black87,
              child: lines.isEmpty
                  ? const Center(
                      child: Text('No log data.',
                          style: TextStyle(
                              color: Colors.green, fontFamily: 'monospace')))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: lines.length,
                      itemBuilder: (ctx, i) => Text(
                        lines[i],
                        style: TextStyle(
                            color: _lineColor(lines[i]),
                            fontFamily: 'monospace',
                            fontSize: 11),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
