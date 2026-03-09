import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/metrics.dart';
import '../protocol/rivr_protocol.dart';
import '../providers/app_providers.dart';
import '../widgets/metric_card.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(metricsProvider);
    final latest = ref.watch(latestMetricsProvider);
    final log = ref.watch(logProvider);
    final isConnected = ref.watch(connectionStateProvider).maybeWhen(
          data: (s) => s.isConnected,
          orElse: () => false,
        );

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'Charts'),
            Tab(text: 'Raw Log'),
          ]),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(latest: latest, isConnected: isConnected, ref: ref),
                _ChartsTab(history: history),
                _RawLogTab(lines: log),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Overview tab ──────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final RivrMetrics latest;
  final bool isConnected;
  final WidgetRef ref;

  const _OverviewTab({
    required this.latest,
    required this.isConnected,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(connectionManagerProvider).send(RivrProtocol.cmdMetrics),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Node & connection
            _SectionHeader('Node'),
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
            _SectionHeader('Radio'),
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
            _SectionHeader('Relay pipeline'),
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
            _SectionHeader('Packet stats'),
            _InfoRow('TX total',        '${latest.txTotal}'),
            _InfoRow('RX total',        '${latest.rxTotal}'),
            _InfoRow('Route cache',     '${latest.routeCache} entries'),
            _InfoRow('Cache hit / miss','${latest.routeCacheHit} / ${latest.routeCacheMiss}'),
            const SizedBox(height: 12),

            _SectionHeader('Drop counters'),
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

            _SectionHeader('Radio hardware'),
            _InfoRow('Hard resets',     '${latest.radioHardReset}'),
            _InfoRow('TX failures',     '${latest.radioTxFail}'),
            _InfoRow('CRC errors',      '${latest.radioCrcFail}'),
            const SizedBox(height: 12),

            _SectionHeader('ACK / Retry'),
            _InfoRow('ACK TX / RX',    '${latest.ackTx} / ${latest.ackRx}'),
            _InfoRow('Retry attempts',  '${latest.retryAttempt}'),
            _InfoRow('Retry OK / fail', '${latest.retrySuccess} / ${latest.retryFail}'),
            const SizedBox(height: 16),

            if (isConnected)
              Center(
                child: FilledButton.tonal(
                  onPressed: () => ref
                      .read(connectionManagerProvider)
                      .send(RivrProtocol.cmdMetrics),
                  child: const Text('Refresh metrics now'),
                ),
              ),
          ],
        ),
      ),
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
                      color: color.withOpacity(0.12),
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

// ── Raw log tab ───────────────────────────────────────────────────────────

class _RawLogTab extends StatelessWidget {
  final List<String> lines;
  const _RawLogTab({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Card(
        color: Colors.black87,
        child: lines.isEmpty
            ? const Center(
                child: Text('No log data.',
                    style: TextStyle(color: Colors.green, fontFamily: 'monospace')))
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: lines.length,
                itemBuilder: (ctx, i) => Text(
                  lines[i],
                  style: const TextStyle(
                      color: Colors.green, fontFamily: 'monospace', fontSize: 11),
                ),
              ),
      ),
    );
  }
}
