import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/rivr_node.dart';

class NodeTile extends StatelessWidget {
  final RivrNode node;
  const NodeTile({super.key, required this.node});

  static final _ageFmt = DateFormat('HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final stale = node.isStale;

    return ListTile(
      leading: _ScoreIndicator(score: node.linkScore, stale: stale),
      title: Text(
        node.displayName,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: stale ? cs.outline : null,
        ),
      ),
      subtitle: Text(
        '${node.rssiDbm} dBm  ·  SNR ${node.snrDb > 0 ? '+' : ''}${node.snrDb} dB  ·  '
        '${node.hopCount} hop${node.hopCount != 1 ? 's' : ''}',
        style: TextStyle(color: stale ? cs.outline : null),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Loss: ${node.lossPercent}%',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            _ageFmt.format(node.lastSeen),
            style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
      onTap: () => _showDetails(context, node),
    );
  }

  void _showDetails(BuildContext context, RivrNode node) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ScoreIndicator(score: node.linkScore, stale: node.isStale),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(node.displayName,
                            style: Theme.of(ctx).textTheme.titleMedium),
                        Text(node.nodeIdHex,
                            style: Theme.of(ctx).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              _Row('RSSI', '${node.rssiDbm} dBm'),
              _Row('SNR ', '${node.snrDb > 0 ? '+' : ''}${node.snrDb} dB'),
              _Row('Hop count', '${node.hopCount}'),
              _Row('Link score', '${node.linkScore}/100'),
              _Row('Loss', '${node.lossPercent}%'),
              _Row('Last seen', _ageFmt.format(node.lastSeen)),
              if (node.isStale) ...[
                const SizedBox(height: 8),
                const Text('⚠ Stale — no recent beacon',
                    style: TextStyle(color: Colors.orange)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ScoreIndicator extends StatelessWidget {
  final int score;
  final bool stale;
  const _ScoreIndicator({required this.score, required this.stale});

  @override
  Widget build(BuildContext context) {
    final color = stale
        ? Colors.grey
        : score >= 70
            ? Colors.green.shade600
            : score >= 40
                ? Colors.orange.shade600
                : Colors.red.shade400;

    return CircleAvatar(
      radius: 22,
      backgroundColor: color.withOpacity(0.15),
      child: Text(
        '$score',
        style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13),
      ),
    );
  }
}
