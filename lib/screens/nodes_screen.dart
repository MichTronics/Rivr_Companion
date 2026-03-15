import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rivr_node.dart';
import '../models/app_settings.dart';
import '../protocol/rivr_protocol.dart';
import '../providers/app_providers.dart';
import '../providers/settings_provider.dart';
import '../widgets/node_tile.dart';

class NodesScreen extends ConsumerWidget {
  const NodesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(nodesProvider).values.toList()
      ..sort((a, b) => b.linkScore.compareTo(a.linkScore));
    final settings = ref.watch(settingsProvider);
    final isConnected = ref.watch(connectionStateProvider).maybeWhen(
          data: (s) => s.isConnected,
          orElse: () => false,
        );
    final canRefreshNodes =
        isConnected && settings.lastConnectionType == ConnectionType.usb;

    return Scaffold(
      body: nodes.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.device_hub, size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('No nodes discovered yet.',
                      style: TextStyle(color: Colors.grey)),
                  if (canRefreshNodes) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => ref
                          .read(connectionManagerProvider)
                          .send(RivrProtocol.cmdNtable),
                      child: const Text('Refresh node table'),
                    ),
                  ] else if (isConnected) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Node table refresh is only available over USB serial.',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            )
          : canRefreshNodes
              ? RefreshIndicator(
                  onRefresh: () => ref
                      .read(connectionManagerProvider)
                      .send(RivrProtocol.cmdNtable),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: nodes.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (ctx, i) => NodeTile(node: nodes[i]),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: nodes.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (ctx, i) => NodeTile(node: nodes[i]),
                ),
      floatingActionButton: canRefreshNodes
          ? FloatingActionButton.small(
              onPressed: () => ref
                  .read(connectionManagerProvider)
                  .send(RivrProtocol.cmdNtable),
              tooltip: 'Refresh',
              child: const Icon(Icons.refresh),
            )
          : null,
    );
  }
}
